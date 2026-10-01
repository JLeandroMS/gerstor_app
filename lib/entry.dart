// MODELO DEL MODO PRIVADO. Entry representa una fila de entries. DeviceEntry, el modelo del explorador real, está en device_repository.dart.
// Guía de lectura: docs/GUIA_DEL_CODIGO.md. Los comentarios explican el código existente.

/// SQLite almacena metadatos. El contenido binario se guarda en disco.
/// Modelo inmutable de una fila de la tabla privada entries.
class Entry {
  final int id;
  final int? parentId;
  final String name;
  final bool isFolder;
  final String? storageKey;
  final int size;
  final String mime;
  final DateTime created;
  final DateTime modified;

  const Entry({
    required this.id,
    required this.parentId,
    required this.name,
    required this.isFolder,
    required this.storageKey,
    required this.size,
    required this.mime,
    required this.created,
    required this.modified,
  });

  /// Convierte tipos SQLite en tipos Dart; is_folder se convierte a bool y las fechas a DateTime.
  factory Entry.fromMap(Map<String, Object?> row) => Entry(
    id: row['id'] as int,
    parentId: row['parent_id'] as int?,
    name: row['name'] as String,
    isFolder: row['is_folder'] == 1,
    storageKey: row['storage_key'] as String?,
    size: row['size'] as int,
    mime: row['mime'] as String,
    created: DateTime.parse(row['created_at'] as String),
    modified: DateTime.parse(row['modified_at'] as String),
  );
}

/// Convierte bytes a un texto legible en B, KB, MB o GB; no cambia el tamaño físico.
String formatBytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
