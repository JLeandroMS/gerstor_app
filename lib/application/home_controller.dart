import 'package:flutter/foundation.dart';
import '../core/native_update_required.dart';
import '../domain/contracts/storage_access.dart';
import '../domain/contracts/storage_dashboard.dart';
import '../domain/models/storage_overview.dart';
/// Estado del inicio; recibe los servicios por contrato y nunca abre SQLite.
class HomeController extends ChangeNotifier {
  final StorageAccess accessService;
  final StorageDashboard dashboard;
  HomeController({required this.accessService, required this.dashboard});
  bool _busy = false;
  bool _access = false;
  bool _disposed = false;
  String? _error;
  StorageOverview? _overview;
  bool get busy => _busy;
  bool get access => _access;
  String? get error => _error;
  StorageOverview? get overview => _overview;
  void _emit() { if (!_disposed) notifyListeners(); }
  Future<void> refresh({bool requestPermission = false}) async {
    if (_busy || _disposed) return;
    _busy = true; _error = null; _emit();
    try {
      if (requestPermission) await accessService.requestAccess();
      _access = await accessService.hasAccess();
      _overview = _access ? await dashboard.load() : null;
    } on NativeUpdateRequired catch (e) {
      _overview = null; _error = e.toString();
    } catch (e, st) {
      debugPrint('$e\n$st'); _overview = null; _error = 'No se pudo cargar el inicio: $e';
    } finally { _busy = false; _emit(); }
  }
  @override
  void dispose() { _disposed = true; super.dispose(); }
}
