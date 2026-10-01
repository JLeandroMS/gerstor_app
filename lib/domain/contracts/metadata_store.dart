import '../models/device_entry.dart';
/// Persistencia de metadatos, independiente del disco y de la interfaz visual.
abstract interface class MetadataStore {
  Future<void> replaceDirectory(String path, List<DeviceEntry> entries);
  Future<void> invalidate(String path);
  Future<void> close();
}
