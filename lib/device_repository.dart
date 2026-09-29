import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'file_repository.dart';

class DeviceEntry {
  final String path;
  final bool folder;
  final int size;
  final DateTime modified;
  DeviceEntry(this.path, this.folder, this.size, this.modified);
  String get name => p.basename(path);
}

/// El disco es la fuente de verdad; SQLite mantiene el índice de metadatos.
/// Nunca copia los archivos a la base de datos ni elimina archivos al limpiar el índice.
class DeviceRepository {
  final Database db;
  final List<String> roots;
  DeviceRepository(this.db, this.roots);

  static Future<DeviceRepository> open(List<String> roots) async {
    final db = await openDatabase(p.join(await getDatabasesPath(), 'device_files.db'),
      version: 1, onCreate: createSchema);
    final canonical = <String>[];
    for (final root in roots) {
      try { canonical.add(await Directory(root).resolveSymbolicLinks()); }
      on FileSystemException { /* Volumen extraído o no disponible. */ }
    }
    return DeviceRepository(db, canonical.toSet().toList());
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('CREATE TABLE device_entries(path TEXT PRIMARY KEY, parent TEXT NOT NULL, name TEXT NOT NULL, is_folder INTEGER NOT NULL, size INTEGER NOT NULL, modified TEXT NOT NULL)');
    await db.execute('CREATE INDEX device_parent ON device_entries(parent)');
  }

  Future<void> check(String path, {bool allowRoot = true}) async {
    final canonical = await File(path).resolveSymbolicLinks();
    if (!roots.any((r) => (allowRoot && p.equals(r, canonical)) || p.isWithin(r, canonical))) {
      throw StateError('La ruta está fuera del almacenamiento permitido.');
    }
    for (final root in roots) {
      final relative = p.relative(canonical, from: root);
      if (relative == 'Android/data' || relative.startsWith('Android/data/') ||
          relative == 'Android/obb' || relative.startsWith('Android/obb/')) {
        throw StateError('Android protege esta carpeta.');
      }
    }
  }

  Future<List<DeviceEntry>> list(String path) async {
    await check(path);
    final entries = <DeviceEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      if (entity is Link) continue;
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.notFound) continue;
      entries.add(DeviceEntry(entity.path, entity is Directory, stat.size, stat.modified));
    }
    // Solo sustituye el índice si la lectura de la carpeta termina correctamente.
    await db.transaction((tx) async {
      await tx.delete('device_entries', where: 'parent=?', whereArgs: [path]);
      final batch = tx.batch();
      for (final entry in entries) {
        batch.insert('device_entries', {'path': entry.path, 'parent': path,
          'name': entry.name, 'is_folder': entry.folder ? 1 : 0,
          'size': entry.folder ? 0 : entry.size, 'modified': entry.modified.toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    entries.sort((a, b) => a.folder != b.folder ? (a.folder ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  Future<String> target(String parent, String name) async {
    await check(parent);
    final result = p.join(parent, FileRepository.validateName(name));
    if (await FileSystemEntity.type(result, followLinks: false) != FileSystemEntityType.notFound) {
      throw StateError('Ya existe un elemento con ese nombre. No se sobrescribió.');
    }
    return result;
  }

  Future<void> createFolder(String parent, String name) async {
    await Directory(await target(parent, name)).create();
  }

  Future<void> invalidate(String path) async {
    // Evita LIKE: los nombres pueden contener % y _.
    await db.delete('device_entries', where: 'path=? OR substr(path,1,?)=?',
      whereArgs: [path, '$path/'.length, '$path/']);
  }

  Future<void> rename(DeviceEntry entry, String name) async {
    await check(entry.path, allowRoot: false);
    final dest = await target(p.dirname(entry.path), name);
    if (entry.folder) { await Directory(entry.path).rename(dest); }
    else { await File(entry.path).rename(dest); }
    await invalidate(entry.path);
  }

  Future<void> delete(DeviceEntry entry) async {
    await check(entry.path, allowRoot: false);
    if (entry.folder) { await Directory(entry.path).delete(recursive: true); }
    else { await File(entry.path).delete(); }
    await invalidate(entry.path);
  }

  Future<void> _copy(String source, String dest) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.link) throw StateError('No se copian enlaces simbólicos.');
    if (type == FileSystemEntityType.directory) {
      await Directory(dest).create();
      await for (final child in Directory(source).list(followLinks: false)) {
        await check(child.path);
        await _copy(child.path, p.join(dest, p.basename(child.path)));
      }
    } else if (type == FileSystemEntityType.file) {
      await File(source).copy(dest);
    } else { throw StateError('El archivo de origen ya no existe.'); }
  }

  Future<void> paste(DeviceEntry entry, String parent, {required bool move}) async {
    await check(entry.path, allowRoot: false);
    await check(parent);
    final source = await File(entry.path).resolveSymbolicLinks();
    final canonicalParent = await Directory(parent).resolveSymbolicLinks();
    if (p.equals(source, canonicalParent) || p.isWithin(source, canonicalParent)) {
      throw StateError('No podés pegar una carpeta dentro de sí misma.');
    }
    final dest = await target(parent, entry.name);
    if (move) {
      // rename es atómico en el mismo volumen. Entre volúmenes se informa el error
      // y se conserva el origen; el usuario puede copiar y después eliminar.
      if (entry.folder) { await Directory(entry.path).rename(dest); }
      else { await File(entry.path).rename(dest); }
      await invalidate(entry.path);
    } else {
      final staging = await Directory(parent).createTemp('.gestor-copy-');
      final temp = p.join(staging.path, entry.name);
      try {
        await _copy(entry.path, temp);
        await target(parent, entry.name); // comprueba colisión otra vez antes de publicar
        if (entry.folder) { await Directory(temp).rename(dest); }
        else { await File(temp).rename(dest); }
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    }
  }
}
