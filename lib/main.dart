import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import 'entry.dart';
import 'device_page.dart';
import 'file_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FilesApp());
}

class FilesApp extends StatelessWidget {
  const FilesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mis archivos',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF176B67),
      scaffoldBackgroundColor: const Color(0xFFF5F7F8),
    ),
    home: DevicePage(privateBuilder: (_) => const FilesPage()),
  );
}

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  FileRepository? repo;
  List<Entry> entries = [];
  final List<Entry> trail = [];
  final search = TextEditingController();
  bool busy = true;
  String? startupError;
  String order = 'nombre';
  String filter = 'todos';
  final Set<int> selectedIds = {};
  bool selecting = false;
  List<int> clipboard = [];
  bool cutting = false;
  int? get parent => trail.isEmpty ? null : trail.last.id;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final opened = await FileRepository.open();
      if (!mounted) {
        await opened.close();
        return;
      }
      repo = opened;
      await refresh();
    } catch (e, st) {
      debugPrint('$e\n$st');
      if (mounted)
        setState(() => startupError = 'No se pudo abrir la base de datos: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final result = await repo!.all();
    if (mounted) setState(() => entries = result);
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || repo == null) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e, st) {
      debugPrint('$e\n$st');
      message('No se pudo completar: $e');
    } finally {
      try {
        await refresh();
      } catch (e) {
        message('Error al actualizar: $e');
      }
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    search.dispose();
    // La base se mantiene abierta durante la vida de esta pantalla principal.
    super.dispose();
  }

  String fullPath(Entry e) {
    final names = <String>[e.name];
    int? id = e.parentId;
    final visited = <int>{e.id};
    final byId = {for (final item in entries) item.id: item};
    while (id != null && visited.add(id)) {
      final ancestor = byId[id];
      if (ancestor == null) break;
      names.insert(0, ancestor.name);
      id = ancestor.parentId;
    }
    return '/${names.join('/')}';
  }

  String category(Entry e) {
    if (e.isFolder) return 'carpetas';
    if (e.mime.startsWith('image/')) return 'imágenes';
    if (e.mime.startsWith('video/')) return 'videos';
    if (e.mime.startsWith('audio/')) return 'audio';
    return 'documentos';
  }

  List<Entry> get visible {
    final query = search.text.trim().toLowerCase();
    final result = entries
        .where(
          (e) =>
              (query.isEmpty
                  ? e.parentId == parent
                  : e.name.toLowerCase().contains(query)) &&
              (filter == 'todos' || category(e) == filter),
        )
        .toList();
    result.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      final compared = switch (order) {
        'fecha' => b.modified.compareTo(a.modified),
        'tamaño' => b.size.compareTo(a.size),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return compared != 0 ? compared : a.id.compareTo(b.id);
    });
    return result;
  }

  void enter(Entry entry) {
    final byId = {for (final e in entries) e.id: e};
    final path = <Entry>[entry];
    var id = entry.parentId;
    while (id != null) {
      final ancestor = byId[id];
      if (ancestor == null) break;
      path.insert(0, ancestor);
      id = ancestor.parentId;
    }
    setState(() {
      trail
        ..clear()
        ..addAll(path);
      search.clear();
      filter = 'todos';
    });
  }

  void goBack() {
    if (busy) return;
    setState(() {
      if (selecting) {
        selecting = false;
        selectedIds.clear();
      } else if (search.text.isNotEmpty) {
        search.clear();
      } else if (trail.isNotEmpty) {
        trail.removeLast();
      }
      filter = 'todos';
    });
  }

  void toggleSelected(Entry entry) {
    setState(() {
      selecting = true;
      if (!selectedIds.add(entry.id)) selectedIds.remove(entry.id);
    });
  }

  void stage(List<int> ids, bool moveItems) {
    if (ids.isEmpty) return;
    setState(() {
      clipboard = List.of(ids);
      cutting = moveItems;
      selectedIds.clear();
      selecting = false;
      search.clear();
    });
    message('Abrí la carpeta de destino y tocá Pegar.');
  }

  Future<void> compressSelected(List<int> ids) async {
    if (ids.isEmpty) return;
    final name = await askName('Nombre del ZIP', initial: 'archivos.zip');
    if (name == null || !mounted) return;
    await run(() async {
      final result = name.toLowerCase().endsWith('.zip') ? name : '$name.zip';
      await repo!.compress(ids, parent, result);
      if (mounted)
        setState(() {
          selecting = false;
          selectedIds.clear();
        });
      message('ZIP creado: $result');
    });
  }

  Future<String?> askName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final key = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLength: 180,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (value) {
              try {
                FileRepository.validateName(value ?? '');
                return null;
              } on FormatException catch (e) {
                return e.message;
              }
            },
            onFieldSubmitted: (_) {
              if (key.currentState!.validate())
                Navigator.pop(dialog, controller.text.trim());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate())
                Navigator.pop(dialog, controller.text.trim());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // El campo puede seguir montado durante la animación de cierre del diálogo.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return value;
  }

  Future<void> importFiles() async {
    await run(() async {
      final selected = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (selected == null) return;
      var imported = 0;
      final failed = <String>[];
      for (final file in selected.files) {
        try {
          if (file.path == null) throw StateError('Sin acceso al archivo');
          await repo!.importFile(File(file.path!), file.name, parent);
          imported++;
        } catch (e) {
          debugPrint('Importación: $e');
          failed.add(file.name);
        }
      }
      message(
        '$imported archivo(s) importado(s).${failed.isEmpty ? '' : ' No se pudieron importar: ${failed.join(', ')}'}',
      );
    });
  }

  Future<void> openEntry(Entry e) async {
    if (e.isFolder) {
      enter(e);
      return;
    }
    await run(() async {
      final file = await repo!.externalFile(e);
      final result = await OpenFilex.open(file.path, type: e.mime);
      if (result.type != ResultType.done) {
        message(
          'No se pudo abrir. Instalá una aplicación compatible con este tipo de archivo. ${result.message}',
        );
      }
    });
  }

  Future<void> action(String action, Entry e) async {
    if (action == 'rename') {
      final name = await askName('Renombrar', initial: e.name);
      if (name != null && mounted) await run(() => repo!.rename(e.id, name));
    } else if (action == 'copy' || action == 'move') {
      stage([e.id], action == 'move');
    } else if (action == 'compress') {
      await compressSelected([e.id]);
    } else if (action == 'extract') {
      await run(() async {
        await repo!.extract(e.id, parent);
        message('Archivo extraído en una carpeta nueva.');
      });
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('¿Eliminar definitivamente?'),
          content: Text(
            'Se eliminará "${e.name}"${e.isFolder ? ' y todo su contenido' : ''}. Esta acción no se puede deshacer. El archivo original que importaste no se elimina.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await run(() async {
          await repo!.delete(e.id);
          if (mounted) setState(() => clipboard = []);
          message('Eliminado.');
        });
      }
    } else if (action == 'share') {
      await run(() async {
        final file = await repo!.externalFile(e);
        await Share.shareXFiles([
          XFile(file.path, mimeType: e.mime),
        ], subject: e.name);
      });
    } else if (action == 'details') {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(e.name),
          content: SingleChildScrollView(
            child: SelectableText(
              'Tipo: ${e.isFolder ? 'Carpeta' : e.mime}\n'
              'Ubicación: ${fullPath(e)}\n'
              '${e.isFolder ? 'Elementos directos: ${entries.where((item) => item.parentId == e.id).length}' : 'Tamaño: ${formatBytes(e.size)} (${e.size} bytes)'}\n'
              'Creado: ${e.created.toLocal().toString().split('.').first}\n'
              'Modificado: ${e.modified.toLocal().toString().split('.').first}\n'
              'ID SQLite: ${e.id}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  IconData icon(Entry e) => switch (category(e)) {
    'carpetas' => Icons.folder_rounded,
    'imágenes' => Icons.image_outlined,
    'videos' => Icons.movie_outlined,
    'audio' => Icons.audio_file_outlined,
    _ => Icons.description_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final list = visible;
    final totalBytes = entries
        .where((e) => !e.isFolder)
        .fold<int>(0, (n, e) => n + e.size);
    return PopScope(
      canPop: !busy && !selecting && trail.isEmpty && search.text.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: selecting || trail.isNotEmpty || search.text.isNotEmpty
              ? IconButton(
                  onPressed: busy ? null : goBack,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: Text(
            selecting ? '${selectedIds.length} seleccionados' : 'Mis archivos',
          ),
          actions: [
            if (!selecting)
              IconButton(
                tooltip: 'Seleccionar varios',
                icon: const Icon(Icons.checklist),
                onPressed: busy ? null : () => setState(() => selecting = true),
              ),
            IconButton(
              tooltip: 'Acerca de',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('Gestor local · SQLite'),
                  content: const Text(
                    'Organizá copias de tus archivos sin internet. Usá Importar para agregarlas.\n\nSQLite guarda los metadatos y las carpetas; el contenido se guarda en el almacenamiento privado. Compartir permite sacar una copia de la aplicación.\n\nDesinstalar la app o borrar sus datos elimina sus archivos internos. No modifica tus originales. No necesita acceso total al almacenamiento.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('Entendido'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: startupError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(startupError!),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            startupError = null;
                            busy = true;
                          });
                          initialize();
                        },
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  if (busy) const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.storage, color: Color(0xFF176B67)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${entries.where((e) => !e.isFolder).length} archivos · ${formatBytes(totalBytes)}\nAlmacenamiento local',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: search,
                      enabled: !busy,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar en todas las carpetas',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => setState(search.clear),
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children:
                          [
                                'todos',
                                'carpetas',
                                'imágenes',
                                'videos',
                                'audio',
                                'documentos',
                              ]
                              .map(
                                (value) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(value),
                                    selected: filter == value,
                                    onSelected: busy
                                        ? null
                                        : (_) => setState(() => filter = value),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            search.text.isNotEmpty
                                ? 'Resultados globales (${list.length})'
                                : '/Mis archivos${trail.isEmpty ? '' : '/${trail.map((e) => e.name).join('/')}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Ordenar',
                          enabled: !busy,
                          icon: const Icon(Icons.sort),
                          onSelected: (v) => setState(() => order = v),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'nombre',
                              child: Text('Nombre A–Z'),
                            ),
                            const PopupMenuItem(
                              value: 'fecha',
                              child: Text('Más recientes'),
                            ),
                            const PopupMenuItem(
                              value: 'tamaño',
                              child: Text('Mayor tamaño'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (selecting)
                    Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Seleccionar visibles',
                            onPressed: busy
                                ? null
                                : () => setState(
                                    () => selectedIds.addAll(
                                      list.map((e) => e.id),
                                    ),
                                  ),
                            icon: const Icon(Icons.select_all),
                          ),
                          Expanded(
                            child: Text('${selectedIds.length} seleccionados'),
                          ),
                          IconButton(
                            tooltip: 'Copiar selección',
                            onPressed: busy || selectedIds.isEmpty
                                ? null
                                : () => stage(selectedIds.toList(), false),
                            icon: const Icon(Icons.copy),
                          ),
                          IconButton(
                            tooltip: 'Mover selección',
                            onPressed: busy || selectedIds.isEmpty
                                ? null
                                : () => stage(selectedIds.toList(), true),
                            icon: const Icon(Icons.drive_file_move_outline),
                          ),
                          IconButton(
                            tooltip: 'Comprimir selección en ZIP',
                            onPressed: busy || selectedIds.isEmpty
                                ? null
                                : () => compressSelected(selectedIds.toList()),
                            icon: const Icon(Icons.folder_zip_outlined),
                          ),
                        ],
                      ),
                    ),
                  if (clipboard.isNotEmpty)
                    Container(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${cutting ? 'Mover' : 'Copiar'}: ${clipboard.length} elemento(s)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: busy || search.text.isNotEmpty
                                ? null
                                : () => run(() async {
                                    final ids = List<int>.of(clipboard);
                                    if (cutting) {
                                      await repo!.moveMany(ids, parent);
                                    } else {
                                      await repo!.copyMany(ids, parent);
                                    }
                                    if (mounted) setState(() => clipboard = []);
                                    message('Operación completada.');
                                  }),
                            child: const Text('Pegar'),
                          ),
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => clipboard = []),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: AbsorbPointer(
                      absorbing: busy,
                      child: list.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_open_rounded,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 12),
                                    Text('No hay elementos para mostrar'),
                                    SizedBox(height: 4),
                                    Text(
                                      'Importá archivos o creá una carpeta.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 16),
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                final e = list[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 3,
                                  ),
                                  child: ListTile(
                                    leading: selecting
                                        ? Checkbox(
                                            value: selectedIds.contains(e.id),
                                            onChanged: (_) => toggleSelected(e),
                                          )
                                        : Icon(
                                            icon(e),
                                            color: e.isFolder
                                                ? const Color(0xFFB87C14)
                                                : const Color(0xFF176B67),
                                            size: 32,
                                          ),
                                    title: Text(
                                      e.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      search.text.isNotEmpty
                                          ? fullPath(e)
                                          : e.isFolder
                                          ? 'Carpeta'
                                          : '${formatBytes(e.size)} · ${e.modified.toLocal().toString().split(' ').first}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: selecting
                                        ? () => toggleSelected(e)
                                        : () => openEntry(e),
                                    onLongPress: () => toggleSelected(e),
                                    trailing: selecting
                                        ? null
                                        : PopupMenuButton<String>(
                                            onSelected: (value) =>
                                                action(value, e),
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                value: 'rename',
                                                child: Text('Renombrar'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'copy',
                                                child: Text('Copiar'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'move',
                                                child: Text('Mover'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'compress',
                                                child: Text('Comprimir en ZIP'),
                                              ),
                                              if (!e.isFolder &&
                                                  e.name.toLowerCase().endsWith(
                                                    '.zip',
                                                  ))
                                                const PopupMenuItem(
                                                  value: 'extract',
                                                  child: Text(
                                                    'Extraer ZIP aquí',
                                                  ),
                                                ),
                                              if (!e.isFolder)
                                                const PopupMenuItem(
                                                  value: 'share',
                                                  child: Text(
                                                    'Compartir / sacar copia',
                                                  ),
                                                ),
                                              const PopupMenuItem(
                                                value: 'details',
                                                child: Text('Detalles'),
                                              ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Eliminar'),
                                              ),
                                            ],
                                          ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy || startupError != null
                        ? null
                        : () async {
                            final name = await askName('Nueva carpeta');
                            if (name != null && mounted)
                              await run(() async {
                                await repo!.createFolder(parent, name);
                              });
                          },
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Carpeta'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy || startupError != null
                        ? null
                        : importFiles,
                    icon: const Icon(Icons.add),
                    label: const Text('Importar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
