import '../models/device_entry.dart';
/// Casos de uso que necesita el controlador del explorador.
abstract interface class FileBrowser {
  List<String> get roots;
  Future<void> configureRoots(List<String> roots);
  Future<List<DeviceEntry>> list(String path);
  Future<void> createFolder(String parent, String name);
  Future<void> rename(DeviceEntry entry, String name);
  Future<void> delete(DeviceEntry entry);
  Future<void> paste(DeviceEntry entry, String parent, {required bool move});
}
