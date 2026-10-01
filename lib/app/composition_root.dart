import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../application/browser_controller.dart';
import '../application/home_controller.dart';
import '../platform/android_storage_dashboard.dart';
import '../application/indexed_file_browser.dart';
import '../data/local_file_storage.dart';
import '../data/sqlite_metadata_store.dart';
import '../platform/android_storage_access.dart';
import '../platform/plugin_file_actions.dart';
import '../legacy/file_repository.dart';

/// Único lugar donde se eligen e instancian las implementaciones del explorador.
/// Usa inyección por constructor; no utiliza localizadores de servicio globales.
class AppDependencies {
  final BrowserController controller;
  final HomeController homeController;
  final Future<FileRepository> Function() openPrivateRepository;
  AppDependencies({required this.controller, required this.homeController, required this.openPrivateRepository});
  factory AppDependencies.production() {
    final metadata = SqliteMetadataStore(() async => openDatabase(
      p.join(await getDatabasesPath(), 'device_files.db'),
      version: 1,
      onCreate: SqliteMetadataStore.createSchema,
    ));
    final browser = IndexedFileBrowser(storage: LocalFileStorage(), metadata: metadata);
    const access = AndroidStorageAccess();
    return AppDependencies(
      homeController: HomeController(accessService: access, dashboard: const AndroidStorageDashboard()),
      controller: BrowserController(browser: browser,
        accessService: access, fileActions: PluginFileActions()),
      openPrivateRepository: FileRepository.open,
    );
  }
}
