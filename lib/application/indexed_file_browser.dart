import '../domain/contracts/file_browser.dart';
import '../domain/contracts/file_storage.dart';
import '../domain/contracts/metadata_store.dart';
import '../domain/models/device_entry.dart';

/// Coordina disco e índice por contratos; no contiene SQL ni llamadas dart:io.
/// Las operaciones físicas y SQL no forman una única transacción distribuida.
class IndexedFileBrowser implements FileBrowser {
  final FileStorage storage;
  final MetadataStore metadata;
  IndexedFileBrowser({required this.storage, required this.metadata});
  @override
  List<String> get roots => storage.roots;
  @override
  Future<void> configureRoots(List<String> roots) => storage.configureRoots(roots);
  @override
  Future<List<DeviceEntry>> list(String path) async {
    final entries = await storage.list(path);
    await metadata.replaceDirectory(path, entries);
    return entries;
  }
  @override
  Future<void> createFolder(String parent, String name) => storage.createFolder(parent, name);
  @override
  Future<void> rename(DeviceEntry entry, String name) async {
    await storage.rename(entry, name);
    await metadata.invalidate(entry.path);
  }
  @override
  Future<void> delete(DeviceEntry entry) async {
    await storage.delete(entry);
    await metadata.invalidate(entry.path);
  }
  @override
  Future<void> paste(DeviceEntry entry, String parent, {required bool move}) async {
    await storage.paste(entry, parent, move: move);
    if (move) await metadata.invalidate(entry.path);
  }
}
