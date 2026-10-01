import 'package:flutter/services.dart';
import '../core/native_update_required.dart';
import '../domain/contracts/storage_dashboard.dart';
import '../domain/models/storage_overview.dart';
/// El método dashboard requiere que MainActivity y Dart provengan de la misma versión.
class AndroidStorageDashboard implements StorageDashboard {
  final MethodChannel channel;
  const AndroidStorageDashboard({this.channel = const MethodChannel('gestor/storage')});
  @override
  Future<StorageOverview> load() async {
    try {
      final value = await channel.invokeMapMethod<Object?, Object?>('dashboard');
      if (value == null) throw StateError('Android no devolvió información de almacenamiento.');
      return StorageOverview.fromMap(value);
    } on MissingPluginException {
      // Nunca sustituir las estadísticas reales por ceros o datos inventados.
      throw const NativeUpdateRequired();
    }
  }
}
