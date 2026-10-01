// Widgets y diálogos únicamente: no importa SQLite, dart:io, canales ni plugins.
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../application/browser_controller.dart';
import '../domain/models/device_entry.dart';
import '../entry.dart';

class DevicePage extends StatefulWidget {
  final BrowserController controller;
  final WidgetBuilder privateBuilder;
  const DevicePage({super.key, required this.controller, required this.privateBuilder});
  @override
  State<DevicePage> createState() => _DevicePageState();
}
class _DevicePageState extends State<DevicePage> with WidgetsBindingObserver {
  BrowserController get c => widget.controller;
  final search = TextEditingController();
  bool get busy => c.busy;
  bool get access => c.access;
  bool get cutting => c.cutting;
  String? get error => c.error;
  String? get location => c.location;
  DeviceEntry? get clipboard => c.clipboard;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    c.initialize();
  }
  void _changed() {
    if (!mounted) return;
    setState(() {});
    final notice = c.takeNotice();
    if (notice != null) WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) message(notice);
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) c.initialize();
  }
  @override
  void dispose() {
    c.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    // El propietario del controlador es FilesApp, que lo recibió en el arranque.
    super.dispose();
  }
  void message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
  Future<void> initialize() => c.initialize();
  Future<void> permission() => c.requestAccess();
  Future<void> navigate(String path) async {
    final previous = c.location;
    await c.navigate(path);
    if (mounted && (c.location != previous || c.location == path)) {
      search.clear();
      c.setQuery('');
    }
  }

  /// Abre un diálogo para escribir un nombre. Devuelve null si se cancela; la validación final se hace en el repositorio.
  Future<String?> askName(String title, [String initial = '']) async {
    String value = initial;
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextFormField(initialValue: initial, autofocus: true,
        onChanged: (v) => value = v, onFieldSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, value), child: const Text('Guardar'))],
    ));
  }

  /// Despacha la opción del menú. Renombrar pide texto; eliminar pide confirmación; copiar/mover prepara el portapapeles; compartir usa XFile.
  Future<void> action(DeviceEntry entry, String action) async {
    if (busy) return;
    switch (action) {
      case 'rename':
        final name = await askName('Renombrar', entry.name);
        if (name != null && name != entry.name && mounted) await c.rename(entry, name);
        return;
      case 'delete':
        final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('¿Eliminar del teléfono?'),
          content: Text('Se eliminará permanentemente "${entry.name}"${entry.folder ? ' y todo su contenido' : ''}. No hay papelera.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar'))]));
        if (confirm == true && mounted) await c.delete(entry);
        return;
      case 'copy':
      case 'move':
        c.stage(entry, move: action == 'move');
        return;
      case 'share':
        await c.share(entry);
        return;
      case 'info':
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: Text(entry.name), content: SelectableText('${entry.path}\n${entry.folder ? 'Carpeta' : formatBytes(entry.size)}\nModificado: ${entry.modified}\nMetadatos indexados en SQLite.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))]));
        return;
    }
  }

  /// Impide subir desde una raíz de almacenamiento. No permite navegar libremente por los archivos del sistema.
  bool get canUp => c.canUp;
  /// Construye el árbol de widgets a partir del estado actual. Flutter vuelve a invocarlo cuando se solicita reconstrucción.
  @override
  Widget build(BuildContext context) {
    // Búsqueda local de nombres en la carpeta actual, sin consulta SQL ni recorrido global.
    final visible = c.visible;
    // Intercepta Atrás para subir de carpeta antes de permitir salir de la pantalla raíz.
    return PopScope(
      canPop: !canUp && !busy,
      onPopInvokedWithResult: (didPop, result) { if (!didPop && canUp && !busy) navigate(p.dirname(location!)); },
      child: Scaffold(
        appBar: AppBar(title: const Text('Archivos del teléfono'), actions: [
          IconButton(tooltip: 'Volver al inicio', onPressed: busy ? null : () => Navigator.of(context).pop(), icon: const Icon(Icons.home_outlined)),
          IconButton(tooltip: 'Actualizar', onPressed: busy ? null : initialize, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(enabled: !busy, onSelected: (value) {
            if (value == 'private') Navigator.push(context, MaterialPageRoute(builder: widget.privateBuilder));
            else permission();
          }, itemBuilder: (_) => [
            const PopupMenuItem(value: 'private', child: Text('Archivos guardados en la app')),
            const PopupMenuItem(value: 'permission', child: Text('Permiso de almacenamiento')),
          ]),
        ]),
        body: Column(children: [
          if (busy) const LinearProgressIndicator(),
          if (!access && !busy) Expanded(child: Center(child: Padding(
            padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.folder_open, size: 64), const SizedBox(height: 16),
              const Text('Explorá y administrá los archivos que ya están en el celular, sin importarlos.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text('Activá “Permitir administrar todos los archivos” y regresá a la app. Android mantiene protegidos los datos privados de otras aplicaciones.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: permission, child: const Text('Dar acceso a los archivos')),
              if (error != null) Text(error!),
            ]))))
          else if (access) ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
              IconButton(tooltip: 'Subir carpeta', onPressed: canUp && !busy ? () => navigate(p.dirname(location!)) : null, icon: const Icon(Icons.arrow_upward)),
              Expanded(child: DropdownButton<String>(isExpanded: true, value: c.roots.where((r) => location == r || p.isWithin(r, location ?? '')).firstOrNull,
                hint: const Text('Almacenamiento'),
                items: c.roots.map((r) => DropdownMenuItem(value: r, child: Text(r == c.roots.first ? 'Almacenamiento interno' : 'SD / USB: ${p.basename(r)}'))).toList(),
                onChanged: busy ? null : (r) { if (r != null) navigate(r); })),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Text(location ?? '', style: const TextStyle(fontSize: 12)))),
            Padding(padding: const EdgeInsets.all(12), child: TextField(controller: search, onChanged: c.setQuery,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar en esta carpeta', border: OutlineInputBorder()))),
            if (clipboard != null) ListTile(leading: Icon(cutting ? Icons.drive_file_move : Icons.copy),
              title: Text(clipboard!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(cutting ? 'Mover a esta carpeta' : 'Copiar a esta carpeta'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(onPressed: busy ? null : c.paste, child: const Text('Pegar')),
                IconButton(onPressed: busy ? null : c.clearClipboard, icon: const Icon(Icons.close)),
              ])),
            if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            Expanded(child: visible.isEmpty ? Center(child: Text(busy ? 'Cargando…' : error != null ? 'Revisá el permiso o elegí otra carpeta.' : 'No hay elementos en esta carpeta.')) : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90), itemCount: visible.length, itemBuilder: (ctx, index) {
                final entry = visible[index];
                return ListTile(leading: Icon(entry.folder ? Icons.folder : Icons.insert_drive_file, color: entry.folder ? Colors.amber.shade800 : Colors.teal),
                  title: Text(entry.name), subtitle: Text(entry.folder ? 'Carpeta' : formatBytes(entry.size)),
                  onTap: busy ? null : () async {
                    if (entry.folder) { await navigate(entry.path); return; }
                    await c.open(entry);
                  },
                  trailing: PopupMenuButton<String>(enabled: !busy, onSelected: (v) => action(entry, v), itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('Copiar')),
                    const PopupMenuItem(value: 'move', child: Text('Mover')),
                    const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                    if (!entry.folder) const PopupMenuItem(value: 'share', child: Text('Compartir')),
                    const PopupMenuItem(value: 'info', child: Text('Propiedades')),
                    const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ]));
              })),
          ] else const Expanded(child: Center(child: CircularProgressIndicator())),
        ]),
        floatingActionButton: access && location != null ? FloatingActionButton.extended(
          onPressed: busy ? null : () async {
            final name = await askName('Nueva carpeta');
            if (name != null && mounted) await c.createFolder(name);
          }, icon: const Icon(Icons.create_new_folder), label: const Text('Carpeta')) : null,
      ),
    );
  }
}
