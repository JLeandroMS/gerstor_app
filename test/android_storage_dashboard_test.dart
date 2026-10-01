import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_archivos/platform/android_storage_dashboard.dart';
import 'package:gestor_archivos/core/native_update_required.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gestor/storage');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('Kotlin anterior produce solicitud de actualización, no cifras falsas', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException('Método dashboard ausente');
    });
    await expectLater(const AndroidStorageDashboard().load(), throwsA(isA<NativeUpdateRequired>()));
  });
  test('dashboard nativo devuelve capacidad real y accesos', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'dashboard');
      return {
        'volumes': [{'path':'/phone','label':'Interno','totalBytes':1000,'freeBytes':400,'availableBytes':300}],
        'shortcuts': [{'id':'pictures','label':'Imágenes','path':'/phone/Pictures','available':true}],
      };
    });
    final result = await const AndroidStorageDashboard().load();
    expect(result.volumes.single.usedPercent, 60);
    expect(result.shortcuts.single.path, '/phone/Pictures');
  });
}
