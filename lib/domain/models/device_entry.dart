import 'package:path/path.dart' as p;

/// Datos de un archivo compartido; no conoce Flutter ni SQLite.
class DeviceEntry {
  final String path;
  final bool folder;
  final int size;
  final DateTime modified;
  DeviceEntry(this.path, this.folder, this.size, this.modified);
  /// Obtiene el último componente de la ruta, por ejemplo tarea.pdf, usando path.basename.
  String get name => p.basename(path);
}

