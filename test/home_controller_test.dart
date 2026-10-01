import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_archivos/application/home_controller.dart';
import 'package:gestor_archivos/domain/contracts/storage_access.dart';
import 'package:gestor_archivos/domain/contracts/storage_dashboard.dart';
import 'package:gestor_archivos/domain/models/storage_overview.dart';
class AccessFake implements StorageAccess {
  bool allowed = false;
  @override
  Future<bool> hasAccess() async => allowed;
  @override
  Future<void> requestAccess() async { allowed = true; }
  @override
  Future<List<String>> roots() async => ['/phone'];
}
class DashboardFake implements StorageDashboard {
  int reads = 0;
  bool fail = false;
  @override
  Future<StorageOverview> load() async {
    reads++;
    if (fail) throw StateError('volumen extraído');
    return StorageOverview(volumes: [const StorageVolumeInfo(path: '/phone', label: 'Interno', totalBytes: 1000, freeBytes: 400, availableBytes: 300)], shortcuts: []);
  }
}
void main() {
  test('porcentaje excluye espacio libre reservado y soporta capacidad desconocida', () {
    const v = StorageVolumeInfo(path: '/', label: '', totalBytes: 1000, freeBytes: 400, availableBytes: 300);
    expect(v.usedBytes, 600);
    expect(v.usedPercent, 60);
    expect(v.availableBytes, 300);
    const unknown = StorageVolumeInfo(path: '/', label: '', totalBytes: 0, freeBytes: 0, availableBytes: 0);
    expect(unknown.hasCapacity, false);
    expect(unknown.usedFraction, 0);
  });
  test('parsea enteros grandes de Android y carpetas no disponibles', () {
    final overview = StorageOverview.fromMap({
      'volumes': [{'path':'/phone','label':'Interno','totalBytes':128000000000,'freeBytes':64000000000,'availableBytes':63000000000}],
      'shortcuts': [{'id':'music','label':'Música','path':'/phone/Music','available':false}],
    });
    expect(overview.volumes.single.usedPercent, 50);
    expect(overview.shortcuts.single.available, false);
  });
  test('sin permiso no consulta; otorgar carga; revocar elimina información anterior', () async {
    final access = AccessFake();
    final dashboard = DashboardFake();
    final c = HomeController(accessService: access, dashboard: dashboard);
    await c.refresh();
    expect(dashboard.reads, 0);
    await c.refresh(requestPermission: true);
    expect(c.overview!.volumes.single.usedPercent, 60);
    access.allowed = false;
    await c.refresh();
    expect(c.overview, isNull);
    expect(c.access, false);
    c.dispose();
  });
  test('error retira cifras obsoletas y permite reintentar', () async {
    final access = AccessFake()..allowed = true;
    final dashboard = DashboardFake();
    final c = HomeController(accessService: access, dashboard: dashboard);
    await c.refresh();
    dashboard.fail = true;
    await c.refresh();
    expect(c.overview, isNull);
    expect(c.error, contains('volumen extraído'));
    expect(c.busy, false);
    dashboard.fail = false;
    await c.refresh();
    expect(c.error, isNull);
    expect(c.overview, isNotNull);
    c.dispose();
  });
}
