import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'entry.dart';

class FileRepository {
  final Database db;
  final Directory storage;
  FileRepository(this.db, this.storage);

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''CREATE TABLE entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      parent_id INTEGER REFERENCES entries(id) ON DELETE CASCADE,
      name TEXT NOT NULL COLLATE NOCASE,
      is_folder INTEGER NOT NULL CHECK(is_folder IN (0,1)),
      storage_key TEXT UNIQUE,
      size INTEGER NOT NULL DEFAULT 0 CHECK(size >= 0),
      mime TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      modified_at TEXT NOT NULL,
      CHECK((is_folder=1 AND storage_key IS NULL) OR
            (is_folder=0 AND storage_key IS NOT NULL))
    )''');
    await db.execute(
      'CREATE UNIQUE INDEX unique_name ON entries(IFNULL(parent_id,0), name COLLATE NOCASE)',
    );
    await db.execute('CREATE INDEX by_parent ON entries(parent_id)');
  }

  static Future<FileRepository> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final storage = await Directory(p.join(dir.path, 'contents'))
        .create(recursive: true);
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'files.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: createSchema,
    );
    final repo = FileRepository(db, storage);
    await repo.removeOrphans();
    return repo;
  }

  /// La UI serializa las operaciones. Las claves internas no dependen del nombre
  /// visible: mover/renombrar es una transacción de metadatos sin mover bytes.
  File physical(Entry entry) {
    if (entry.isFolder || entry.storageKey == null) {
      throw StateError('Una carpeta no tiene contenido binario.');
    }
    return File(p.join(storage.path, entry.storageKey!));
  }

  static String validateName(String input) {
    final name = input.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.length > 180 ||
        RegExp(r'[\x00-\x1f/\\:*?"<>|]').hasMatch(name) ||
        name.endsWith('.')) {
      throw const FormatException(
        'Usá un nombre de 1 a 180 caracteres, sin / \\ : * ? " < > | ni punto final.',
      );
    }
    return name;
  }

  Future<Entry> get(int id, [DatabaseExecutor? executor]) async {
    final rows = await (executor ?? db).query(
      'entries',
      where: 'id=?',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('El elemento ya no existe.');
    return Entry.fromMap(rows.single);
  }

  Future<List<Entry>> children(int? parent) async => (await db.query(
    'entries',
    where: 'parent_id IS ?',
    whereArgs: [parent],
  )).map(Entry.fromMap).toList();

  Future<List<Entry>> all() async =>
      (await db.query('entries')).map(Entry.fromMap).toList();

  Future<void> _checkParent(DatabaseExecutor tx, int? parent) async {
    if (parent != null && !(await get(parent, tx)).isFolder) {
      throw StateError('El destino debe ser una carpeta.');
    }
  }

  Future<void> _checkName(
    DatabaseExecutor tx,
    int? parent,
    String name, {
    int? exclude,
  }) async {
    final rows = await tx.query(
      'entries',
      where: 'parent_id IS ? AND name=? COLLATE NOCASE AND id != ?',
      whereArgs: [parent, name, exclude ?? -1],
    );
    if (rows.isNotEmpty) throw StateError('Ya existe "$name" en esa carpeta.');
  }

  Future<String> _availableName(int? parent, String raw, bool folder) async {
    final name = validateName(raw);
    final names = (await children(parent))
        .map((e) => e.name.toLowerCase())
        .toSet();
    if (!names.contains(name.toLowerCase())) return name;
    final extension = folder ? '' : p.extension(name);
    final base = folder ? name : p.basenameWithoutExtension(name);
    for (var i = 1; ; i++) {
      final candidate = '$base ($i)$extension';
      if (!names.contains(candidate.toLowerCase()))
        return validateName(candidate);
    }
  }

  Future<int> createFolder(int? parent, String raw) async {
    final name = validateName(raw);
    return db.transaction((tx) async {
      await _checkParent(tx, parent);
      await _checkName(tx, parent, name);
      final now = DateTime.now().toIso8601String();
      return tx.insert('entries', {
        'parent_id': parent,
        'name': name,
        'is_folder': 1,
        'created_at': now,
        'modified_at': now,
      });
    });
  }

  Future<int> importFile(File source, String raw, int? parent) async {
    final name = await _availableName(parent, raw, false);
    final key =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    final target = File(p.join(storage.path, key));
    try {
      // File.copy no carga todo el archivo en RAM.
      await source.copy(target.path);
      final size = await target.length();
      return await db.transaction((tx) async {
        await _checkParent(tx, parent);
        await _checkName(tx, parent, name);
        final now = DateTime.now().toIso8601String();
        return tx.insert('entries', {
          'parent_id': parent,
          'name': name,
          'is_folder': 0,
          'storage_key': key,
          'size': size,
          'mime': lookupMimeType(name) ?? 'application/octet-stream',
          'created_at': now,
          'modified_at': now,
        });
      });
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  Future<void> rename(int id, String raw) async {
    final name = validateName(raw);
    await db.transaction((tx) async {
      final entry = await get(id, tx);
      await _checkName(tx, entry.parentId, name, exclude: id);
      await tx.update(
        'entries',
        {
          'name': name,
          'mime': entry.isFolder
              ? ''
              : (lookupMimeType(name) ?? 'application/octet-stream'),
          'modified_at': DateTime.now().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  Future<void> _checkDestination(
    DatabaseExecutor tx,
    int source,
    int? parent,
  ) async {
    await _checkParent(tx, parent);
    int? cursor = parent;
    while (cursor != null) {
      if (cursor == source)
        throw StateError(
          'No podés colocar una carpeta dentro de sí misma ni de sus subcarpetas.',
        );
      cursor = (await get(cursor, tx)).parentId;
    }
  }

  Future<void> move(int id, int? parent) async {
    await db.transaction((tx) async {
      final entry = await get(id, tx);
      await _checkDestination(tx, id, parent);
      await _checkName(tx, parent, entry.name, exclude: id);
      await tx.update(
        'entries',
        {'parent_id': parent, 'modified_at': DateTime.now().toIso8601String()},
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  /// Comprueba todo el lote y aplica los cambios en una sola transacción.
  Future<void> moveMany(List<int> ids, int? parent) async {
    if (ids.isEmpty || ids.toSet().length != ids.length) {
      throw StateError('Seleccioná elementos distintos para mover.');
    }
    await db.transaction((tx) async {
      await _checkParent(tx, parent);
      final names = <String>{};
      for (final id in ids) {
        final entry = await get(id, tx);
        await _checkDestination(tx, id, parent);
        await _checkName(tx, parent, entry.name, exclude: id);
        if (!names.add(entry.name.toLowerCase())) {
          throw StateError(
            'Dos elementos seleccionados tienen el mismo nombre.',
          );
        }
      }
      for (final id in ids) {
        await tx.update(
          'entries',
          {
            'parent_id': parent,
            'modified_at': DateTime.now().toIso8601String(),
          },
          where: 'id=?',
          whereArgs: [id],
        );
      }
    });
  }

  /// Una copia fallida elimina los resultados que haya creado este lote.
  Future<void> copyMany(List<int> ids, int? parent) async {
    if (ids.isEmpty || ids.toSet().length != ids.length) {
      throw StateError('Seleccioná elementos distintos para copiar.');
    }
    for (final id in ids) {
      await _checkDestination(db, id, parent);
    }
    final created = <int>[];
    try {
      for (final id in ids) {
        created.add(await copy(id, parent));
      }
    } catch (_) {
      for (final id in created.reversed) {
        await delete(id);
      }
      rethrow;
    }
  }

  Future<int> compress(List<int> ids, int? parent, String rawName) async {
    if (ids.isEmpty || ids.toSet().length != ids.length) {
      throw StateError('Seleccioná elementos distintos para comprimir.');
    }
    final name = validateName(rawName);
    if (!name.toLowerCase().endsWith('.zip')) {
      throw const FormatException('El archivo debe terminar en .zip');
    }
    final temp = await Directory.systemTemp.createTemp('gestor_zip_');
    final output = File(p.join(temp.path, 'archive.zip'));
    final encoder = ZipFileEncoder();
    var opened = false;
    try {
      encoder.create(output.path);
      opened = true;
      Future<void> addEntry(Entry entry, String prefix) async {
        final relative = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
        if (entry.isFolder) {
          encoder.addArchiveFile(ArchiveFile.directory('$relative/'));
          for (final child in await children(entry.id)) {
            await addEntry(child, relative);
          }
        } else {
          await encoder.addFile(physical(entry), relative);
        }
      }

      for (final id in ids) {
        await addEntry(await get(id), '');
      }
      await encoder.close();
      opened = false;
      return await importFile(output, name, parent);
    } finally {
      if (opened) {
        try {
          await encoder.close();
        } catch (_) {
          /* Conservar error original. */
        }
      }
      await temp.delete(recursive: true);
    }
  }

  /// Extrae dentro de una carpeta nueva; rechaza rutas peligrosas y enlaces.
  Future<int> extract(int zipId, int? parent) async {
    final zip = await get(zipId);
    if (zip.isFolder || !zip.name.toLowerCase().endsWith('.zip')) {
      throw StateError('Seleccioná un archivo .zip para extraer.');
    }
    final input = InputFileStream(physical(zip).path);
    int? created;
    try {
      final archive = ZipDecoder().decodeStream(input);
      if (archive.length > 1000)
        throw StateError('El ZIP contiene más de 1000 entradas.');
      var total = 0;
      final partsByEntry = <ArchiveFile, List<String>>{};
      final seen = <String>{};
      for (final item in archive) {
        if (item.isSymbolicLink)
          throw StateError('No se admiten enlaces en ZIP.');
        final normalized = item.name.replaceAll('\\', '/');
        final parts = normalized.split('/')
          ..removeWhere((part) => part.isEmpty);
        if (parts.isEmpty ||
            normalized.startsWith('/') ||
            normalized.contains('//') ||
            normalized.contains(':')) {
          throw StateError('El ZIP contiene una ruta inválida.');
        }
        for (final part in parts) {
          validateName(part);
        }
        final key = parts.join('/').toLowerCase();
        if (!seen.add(key)) throw StateError('El ZIP tiene nombres repetidos.');
        total += item.size;
        if (total > 1024 * 1024 * 1024) {
          throw StateError('El ZIP excede 1 GB descomprimido.');
        }
        partsByEntry[item] = parts;
      }
      final folderName = await _availableName(
        parent,
        '${p.basenameWithoutExtension(zip.name)} extraído',
        true,
      );
      created = await createFolder(parent, folderName);
      final folders = <String, int>{'': created};
      Future<int> ensureFolder(List<String> parts) async {
        var current = created!;
        var path = '';
        for (final segment in parts) {
          path = path.isEmpty ? segment : '$path/$segment';
          if (folders.containsKey(path)) {
            current = folders[path]!;
            continue;
          }
          current = await createFolder(current, segment);
          folders[path] = current;
        }
        return current;
      }

      final temp = await Directory.systemTemp.createTemp('gestor_extract_');
      try {
        var index = 0;
        for (final item in archive) {
          final parts = partsByEntry[item]!;
          if (item.isDirectory) {
            await ensureFolder(parts);
          } else {
            final folderId = await ensureFolder(
              parts.sublist(0, parts.length - 1),
            );
            final extracted = File(p.join(temp.path, 'entry_${index++}'));
            final output = OutputFileStream(extracted.path);
            try {
              item.writeContent(output);
            } finally {
              await output.close();
            }
            if (await extracted.length() > item.size ||
                await extracted.length() > 1024 * 1024 * 1024) {
              throw StateError(
                'El tamaño extraído no coincide con el índice del ZIP.',
              );
            }
            await importFile(extracted, parts.last, folderId);
            await extracted.delete();
          }
        }
      } finally {
        await temp.delete(recursive: true);
      }
      return created;
    } catch (_) {
      if (created != null) await delete(created);
      rethrow;
    } finally {
      await input.close();
    }
  }

  Future<int> copy(int id, int? parent) async {
    await _checkDestination(db, id, parent);
    final entry = await get(id);
    if (!entry.isFolder) return importFile(physical(entry), entry.name, parent);
    final name = await _availableName(parent, entry.name, true);
    final newId = await createFolder(parent, name);
    try {
      for (final child in await children(id)) {
        await copy(child.id, newId);
      }
      return newId;
    } catch (_) {
      // Revierte una copia recursiva incompleta por un error recuperable.
      await delete(newId);
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    // Primero confirma la eliminación lógica en SQLite; luego elimina bytes.
    // Si la app se cierra entre ambos pasos, removeOrphans limpia al reiniciar.
    await db.transaction((tx) async {
      await tx.delete('entries', where: 'id=?', whereArgs: [id]);
    });
    await removeOrphans();
  }

  Future<void> removeOrphans() async {
    final rows = await db.query(
      'entries',
      columns: ['storage_key'],
      where: 'is_folder=0',
    );
    final keys = rows.map((row) => row['storage_key']).toSet();
    await for (final file in storage.list()) {
      if (file is File && !keys.contains(p.basename(file.path))) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint('Limpieza pendiente: $e');
        }
      }
    }
  }

  /// Copia temporal con el nombre visible para aplicaciones externas.
  Future<File> externalFile(Entry entry) async {
    final dir = await getTemporaryDirectory();
    final out = await Directory(p.join(dir.path, 'outgoing', '${entry.id}'))
        .create(recursive: true);
    for (final old in await out.list().toList()) {
      if (old is File) await old.delete();
    }
    return physical(entry).copy(p.join(out.path, entry.name));
  }

  Future<void> close() => db.close();
}
