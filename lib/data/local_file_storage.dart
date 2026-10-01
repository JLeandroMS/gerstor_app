import 'dart:io';
import 'package:path/path.dart' as p;
import '../domain/models/device_entry.dart';
import '../domain/contracts/file_storage.dart';
import '../core/file_name_validator.dart';

/// Solo sistema de archivos: sin SQL, widgets, permisos ni plugins.
class LocalFileStorage implements FileStorage {
  List<String> _roots = [];
  @override
  List<String> get roots => List.unmodifiable(_roots);
  @override
  Future<void> configureRoots(List<String> roots) async {
    final resolved = <String>[];
    for (final root in roots) {
      try { resolved.add(await Directory(root).resolveSymbolicLinks()); }
      on FileSystemException { /* Volumen no disponible. */ }
    }
    _roots = resolved.toSet().toList();
  }

  /// Resuelve la ruta canónica y exige que pertenezca a una raíz permitida. allowRoot=false evita modificar la raíz. Rechaza Android/data y Android/obb.
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

  /// Lee el contenido directo, sin recursión ni enlaces. Si la lectura termina, devuelve sus elementos. Devuelve objetos leídos del disco, ordenados.
  Future<List<DeviceEntry>> list(String path) async {
    await check(path);
    final entries = <DeviceEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      if (entity is Link) continue;
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.notFound) continue;
      entries.add(DeviceEntry(entity.path, entity is Directory, stat.size, stat.modified));
    }
    entries.sort((a, b) => a.folder != b.folder ? (a.folder ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  /// Valida la carpeta y el nombre; rechaza un destino existente para no sobrescribirlo intencionalmente. Esta comprobación no bloquea cambios de otras aplicaciones.
  Future<String> target(String parent, String name) async {
    await check(parent);
    final result = p.join(parent, FileNameValidator.validateName(name));
    if (await FileSystemEntity.type(result, followLinks: false) != FileSystemEntityType.notFound) {
      throw StateError('Ya existe un elemento con ese nombre. No se sobrescribió.');
    }
    return result;
  }

  /// Crea una carpeta física; su fila de metadatos se incorpora cuando la pantalla vuelve a listar el directorio.
  Future<void> createFolder(String parent, String name) async {
    await Directory(await target(parent, name)).create();
  }

  /// Valida origen y destino, renombra físicamente el elemento sin modificar SQLite. La pantalla refresca después.
  Future<void> rename(DeviceEntry entry, String name) async {
    await check(entry.path, allowRoot: false);
    final dest = await target(p.dirname(entry.path), name);
    if (entry.folder) { await Directory(entry.path).rename(dest); }
    else { await File(entry.path).rename(dest); }
  }

  /// Elimina físicamente el archivo o la carpeta completa. Es permanente. La confirmación se encuentra en la interfaz; el repositorio no abre diálogos.
  Future<void> delete(DeviceEntry entry) async {
    await check(entry.path, allowRoot: false);
    if (entry.folder) { await Directory(entry.path).delete(recursive: true); }
    else { await File(entry.path).delete(); }
  }

  /// Copia recursivamente: crea cada carpeta y copia archivos con File.copy. Rechaza enlaces simbólicos y comprueba las rutas de los descendientes.
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

  /// Valida destino, colisiones y que una carpeta no se pegue dentro de sí misma. Mover usa rename (puede fallar entre volúmenes); copiar usa una carpeta temporal que se limpia en finally.
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
