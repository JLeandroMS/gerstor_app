import 'package:sqflite/sqflite.dart';
import '../domain/models/device_entry.dart';
import '../domain/contracts/metadata_store.dart';

/// Solo SQLite. Recibe cómo abrir la conexión desde la composición de la app.
class SqliteMetadataStore implements MetadataStore {
  final Future<Database> Function() openConnection;
  Future<Database>? _connection;
  SqliteMetadataStore(this.openConnection);
  Future<Database> get database => _connection ??= openConnection();
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('CREATE TABLE device_entries(path TEXT PRIMARY KEY, parent TEXT NOT NULL, name TEXT NOT NULL, is_folder INTEGER NOT NULL, size INTEGER NOT NULL, modified TEXT NOT NULL)');
    await db.execute('CREATE INDEX device_parent ON device_entries(parent)');
  }


  @override
  Future<void> replaceDirectory(String path, List<DeviceEntry> entries) async {
    final db = await database;
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
  }
  /// Elimina únicamente metadatos de la ruta y de sus descendientes. No borra archivos físicos. Usa substr para no interpretar % o _ del nombre como comodines.
  Future<void> invalidate(String path) async {
    final db = await database;
    // Evita LIKE: los nombres pueden contener % y _.
    await db.delete('device_entries', where: 'path=? OR substr(path,1,?)=?',
      whereArgs: [path, '$path/'.length, '$path/']);
  }


  @override
  Future<void> close() async {
    final connection = _connection;
    if (connection != null) await (await connection).close();
    _connection = null;
  }
}
