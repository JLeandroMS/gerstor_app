import '../models/storage_overview.dart';
/// Capacidad y rutas frecuentes. Separado del contrato de permisos y del CRUD.
abstract interface class StorageDashboard {
  Future<StorageOverview> load();
}
