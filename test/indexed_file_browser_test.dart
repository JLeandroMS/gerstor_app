import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_archivos/application/indexed_file_browser.dart';
import 'package:gestor_archivos/domain/contracts/file_storage.dart';
import 'package:gestor_archivos/domain/contracts/metadata_store.dart';
import 'package:gestor_archivos/domain/models/device_entry.dart';
class MemoryStorage implements FileStorage {
  bool fail = false;
  @override
  List<String> roots = ['/phone'];
  @override
  Future<void> configureRoots(List<String> value) async { roots = value; }
  @override
  Future<List<DeviceEntry>> list(String path) async {
    if (fail) throw StateError('lectura fallida');
    return [];
  }
  @override
  Future<void> createFolder(String parent, String name) async {}
  @override
  Future<void> rename(DeviceEntry entry, String name) async { if (fail) throw StateError('fallo'); }
  @override
  Future<void> delete(DeviceEntry entry) async { if (fail) throw StateError('fallo'); }
  @override
  Future<void> paste(DeviceEntry entry, String parent, {required bool move}) async {}
}
class MemoryMetadata implements MetadataStore {
  int replacements = 0;
  final invalidated = <String>[];
  @override
  Future<void> replaceDirectory(String path, List<DeviceEntry> entries) async { replacements++; }
  @override
  Future<void> invalidate(String path) async { invalidated.add(path); }
  @override
  Future<void> close() async {}
}
void main() {
  test('fallo físico no sustituye índice ni invalida metadatos', () async {
    final storage = MemoryStorage()..fail = true;
    final metadata = MemoryMetadata();
    final browser = IndexedFileBrowser(storage: storage, metadata: metadata);
    await expectLater(browser.list('/phone'), throwsStateError);
    final entry = DeviceEntry('/phone/a', false, 1, DateTime(2026));
    await expectLater(browser.delete(entry), throwsStateError);
    expect(metadata.replacements, 0);
    expect(metadata.invalidated, isEmpty);
    storage.fail = false;
    await browser.delete(entry);
    expect(metadata.invalidated, ['/phone/a']);
  });
}
