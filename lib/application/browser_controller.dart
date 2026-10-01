import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../domain/contracts/file_browser.dart';
import '../domain/contracts/storage_access.dart';
import '../domain/contracts/file_actions.dart';
import '../domain/models/device_entry.dart';

/// Estado y coordinación de la pantalla. Recibe contratos; no crea servicios.
class BrowserController extends ChangeNotifier {
  final FileBrowser browser;
  final StorageAccess accessService;
  final FileActions fileActions;
  BrowserController({required this.browser, required this.accessService, required this.fileActions});
  List<DeviceEntry> _entries = [];
  String? _location;
  String _query = '';
  String? _error;
  String? _notice;
  bool _access = false;
  bool _busy = false;
  bool _cutting = false;
  bool _disposed = false;
  DeviceEntry? _clipboard;
  List<DeviceEntry> get entries => List.unmodifiable(_entries);
  List<DeviceEntry> get visible => _entries.where((e) => e.name.toLowerCase().contains(_query.toLowerCase())).toList();
  List<String> get roots => browser.roots;
  String? get location => _location;
  String? get error => _error;
  bool get access => _access;
  bool get busy => _busy;
  bool get cutting => _cutting;
  DeviceEntry? get clipboard => _clipboard;
  bool get canUp => _location != null && !roots.contains(_location);
  void _emit() { if (!_disposed) notifyListeners(); }
  String? takeNotice() { final result = _notice; _notice = null; return result; }
  void setQuery(String value) { _query = value; _emit(); }
  void stage(DeviceEntry entry, {required bool move}) {
    if (_busy || !_access) return;
    _clipboard = entry; _cutting = move;
    _notice = 'Abrí la carpeta de destino y tocá Pegar.';
    _emit();
  }
  void clearClipboard() { if (!_busy) { _clipboard = null; _emit(); } }

  /// busy serializa acciones originadas en esta interfaz. No bloquea otras apps.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _disposed) return;
    _busy = true; _emit();
    try { await action(); }
    catch (e, st) { debugPrint('$e\n$st'); _notice = 'No se pudo completar: $e'; }
    finally { _busy = false; _emit(); }
  }

  /// Abre un acceso rápido solo si puede leer el destino. Devuelve éxito a la vista Inicio.
  Future<bool> openLocation(String path) async {
    if (_busy || _disposed) return false;
    var success = false;
    await _run(() async {
      _access = await accessService.hasAccess();
      if (!_access) { _entries = []; _clipboard = null; throw StateError('Habilitá el permiso de almacenamiento.'); }
      await browser.configureRoots(await accessService.roots());
      final result = await browser.list(path);
      _location = path; _entries = result; _query = ''; _error = null;
      success = true;
    });
    return success;
  }

  Future<void> initialize() => _run(_initialize);
  Future<void> _initialize() async {
    _error = null;
    try {
      _access = await accessService.hasAccess();
      if (!_access) { _entries = []; _clipboard = null; return; }
      await browser.configureRoots(await accessService.roots());
      if (roots.isEmpty) throw StateError('No hay almacenamiento disponible.');
      if (_location == null || !roots.any((r) => r == _location || p.isWithin(r, _location!))) {
        _location = roots.first;
      }
      _entries = await browser.list(_location!);
    } catch (e) { _entries = []; _error = 'No se pudo leer el almacenamiento: $e'; rethrow; }
  }
  Future<void> requestAccess() => _run(() async {
    await accessService.requestAccess();
    await _initialize();
  });
  Future<void> navigate(String path) => _run(() async {
    if (!_access) return;
    final result = await browser.list(path);
    _location = path; _entries = result; _query = ''; _error = null;
  });
  Future<void> up() async { if (canUp) await navigate(p.dirname(_location!)); }

  /// Mantiene el resultado físico como fuente de verdad y refresca incluso ante errores.
  Future<void> _mutate(Future<void> Function() action) => _run(() async {
    if (!_access || _location == null) return;
    try { await action(); }
    finally {
      try { _entries = await browser.list(_location!); _error = null; }
      catch (e) { _entries = []; _error = 'No se pudo actualizar: $e'; }
    }
  });
  Future<void> createFolder(String name) => _mutate(() => browser.createFolder(_location!, name));
  Future<void> rename(DeviceEntry entry, String name) => _mutate(() => browser.rename(entry, name));
  Future<void> delete(DeviceEntry entry) => _mutate(() => browser.delete(entry));
  Future<void> paste() => _mutate(() async {
    final entry = _clipboard;
    if (entry == null) return;
    await browser.paste(entry, _location!, move: _cutting);
    _clipboard = null;
  });
  Future<void> open(DeviceEntry entry) => _run(() => fileActions.open(entry.path));
  Future<void> share(DeviceEntry entry) => _run(() => fileActions.share(entry.path));
  @override
  void dispose() { _disposed = true; super.dispose(); }
}
