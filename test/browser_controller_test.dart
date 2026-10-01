import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_archivos/application/browser_controller.dart';
import 'package:gestor_archivos/domain/contracts/file_browser.dart';
import 'package:gestor_archivos/domain/contracts/storage_access.dart';
import 'package:gestor_archivos/domain/contracts/file_actions.dart';
import 'package:gestor_archivos/domain/models/device_entry.dart';

class FakeBrowser implements FileBrowser {
  @override
  List<String> roots = ['/phone'];
  int reads = 0;
  bool fail = false;
  Completer<List<DeviceEntry>>? pending;
  final item = DeviceEntry('/phone/a.txt', false, 5, DateTime(2026));
  @override
  Future<void> configureRoots(List<String> value) async { roots = value; }
  @override
  Future<List<DeviceEntry>> list(String path) async {
    reads++;
    if (fail) throw StateError('sin acceso');
    if (pending != null) return pending!.future;
    return [item];
  }
  @override
  Future<void> createFolder(String parent, String name) async {}
  @override
  Future<void> rename(DeviceEntry entry, String name) async {}
  @override
  Future<void> delete(DeviceEntry entry) async {}
  @override
  Future<void> paste(DeviceEntry entry, String parent, {required bool move}) async {}
}
class FakeAccess implements StorageAccess {
  bool allowed = true;
  @override
  Future<bool> hasAccess() async => allowed;
  @override
  Future<void> requestAccess() async {}
  @override
  Future<List<String>> roots() async => ['/phone'];
}
class FakeActions implements FileActions {
  String? opened;
  @override
  Future<void> open(String path) async { opened = path; }
  @override
  Future<void> share(String path) async {}
}
void main() {
  late FakeBrowser browser;
  late FakeAccess access;
  late FakeActions actions;
  late BrowserController controller;
  setUp(() {
    browser = FakeBrowser(); access = FakeAccess(); actions = FakeActions();
    controller = BrowserController(browser: browser, accessService: access, fileActions: actions);
  });
  tearDown(() => controller.dispose());
  test('sin permiso no lee almacenamiento y revocación limpia lista y portapapeles', () async {
    await controller.initialize();
    controller.stage(browser.item, move: false);
    final reads = browser.reads;
    access.allowed = false;
    await controller.initialize();
    expect(browser.reads, reads);
    expect(controller.entries, isEmpty);
    expect(controller.clipboard, isNull);
    expect(controller.access, isFalse);
  });
  test('fallo de navegación conserva carpeta y comunica el error', () async {
    await controller.initialize();
    browser.fail = true;
    await controller.navigate('/phone/denied');
    expect(controller.location, '/phone');
    expect(controller.takeNotice(), contains('sin acceso'));
    expect(controller.busy, isFalse);
  });
  test('carga pendiente impide segunda operación y búsqueda no consulta disco', () async {
    browser.pending = Completer<List<DeviceEntry>>();
    final first = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    await controller.initialize();
    expect(browser.reads, 1);
    browser.pending!.complete([browser.item]);
    await first;
    controller.setQuery('A.TXT');
    expect(controller.visible.single, browser.item);
    expect(browser.reads, 1);
  });
  test('abrir delega en FileActions sustituible', () async {
    await controller.open(browser.item);
    expect(actions.opened, browser.item.path);
  });
}
