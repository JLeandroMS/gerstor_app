import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../domain/contracts/file_actions.dart';

/// Adaptador de plugins. Puede reemplazarse sin cambiar widgets ni controlador.
class PluginFileActions implements FileActions {
  @override
  Future<void> open(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) throw StateError(result.message);
  }
  @override
  Future<void> share(String path) async { await Share.shareXFiles([XFile(path)]); }
}
