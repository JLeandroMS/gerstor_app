import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/contracts/storage_access.dart';

/// Adaptador Android. Encapsula permisos y raíces; el resumen usa otro contrato.
class AndroidStorageAccess implements StorageAccess {
  final MethodChannel channel;
  const AndroidStorageAccess({this.channel = const MethodChannel('gestor/storage')});
  void _requireAndroid() {
    if (!Platform.isAndroid) throw StateError('El explorador requiere Android.');
  }
  @override
  Future<bool> hasAccess() async {
    _requireAndroid();
    return await channel.invokeMethod<bool>('hasAccess') ?? false;
  }
  @override
  Future<void> requestAccess() async {
    _requireAndroid();
    await channel.invokeMethod<bool>('requestAccess');
  }
  @override
  Future<List<String>> roots() async {
    _requireAndroid();
    return await channel.invokeListMethod<String>('roots') ?? [];
  }
}
