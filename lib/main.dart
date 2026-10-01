import 'package:flutter/material.dart';
import 'app/composition_root.dart';
import 'presentation/home_page.dart';
import 'legacy/private_files_page.dart';

/// Arranca Flutter y compone las dependencias fuera de las pantallas.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FilesApp(dependencies: AppDependencies.production()));
}
class FilesApp extends StatefulWidget {
  final AppDependencies dependencies;
  const FilesApp({super.key, required this.dependencies});
  @override
  State<FilesApp> createState() => _FilesAppState();
}
class _FilesAppState extends State<FilesApp> {
  @override
  void dispose() {
    widget.dependencies.controller.dispose();
    widget.dependencies.homeController.dispose();
    // SQLite es una conexión de duración de proceso. No se cierra bajo una tarea en vuelo.
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mis archivos', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF176B67),
      scaffoldBackgroundColor: const Color(0xFFF5F7F8)),
    home: HomePage(controller: widget.dependencies.homeController,
      browserController: widget.dependencies.controller,
      privateBuilder: (_) => FilesPage(openRepository: widget.dependencies.openPrivateRepository)),
  );
}
