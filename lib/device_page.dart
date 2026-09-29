import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'device_repository.dart';
import 'entry.dart';

class DevicePage extends StatefulWidget {
  final WidgetBuilder privateBuilder;
  const DevicePage({super.key, required this.privateBuilder});
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> with WidgetsBindingObserver {
  static const channel = MethodChannel('gestor/storage');
  DeviceRepository? repo;
  List<DeviceEntry> entries = [];
  String? location;
  String query = '';
  String? error;
  bool access = false;
  bool busy = false;
  bool cutting = false;
  DeviceEntry? clipboard;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    // La conexión se conserva mientras haya operaciones async pendientes.
    super.dispose();
  }

  void message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> initialize() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      if (!Platform.isAndroid) throw StateError('El explorador requiere Android.');
      access = await channel.invokeMethod<bool>('hasAccess') ?? false;
      if (!access) { entries = []; return; }
      final roots = await channel.invokeListMethod<String>('roots') ?? [];
      repo = await DeviceRepository.open(roots);
      location ??= repo!.roots.isEmpty ? null : repo!.roots.first;
      if (location == null) throw StateError('No hay almacenamiento disponible.');
      entries = await repo!.list(location!);
    } catch (e, st) {
      debugPrint('$e\n$st');
      error = 'No se pudo leer el almacenamiento: $e';
      entries = [];
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> navigate(String path) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final result = await repo!.list(path);
      if (!mounted) return;
      setState(() { location = path; entries = result; query = ''; search.clear(); });
    } catch (e, st) {
      debugPrint('$e\n$st');
      message('No se puede abrir esta carpeta: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> operate(Future<void> Function() action) async {
    if (busy || repo == null) return;
    setState(() => busy = true);
    try { await action(); }
    catch (e, st) { debugPrint('$e\n$st'); message('No se pudo completar: $e'); }
    finally {
      try { entries = await repo!.list(location!); error = null; }
      catch (e) { entries = []; error = 'No se pudo actualizar: $e'; }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> permission() async {
    try {
      await channel.invokeMethod<bool>('requestAccess');
      if (mounted) await initialize();
    } catch (e) { message('No se pudo solicitar el permiso: $e'); }
  }

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

  Future<void> action(DeviceEntry entry, String action) async {
    if (busy) return;
    switch (action) {
      case 'rename':
        final name = await askName('Renombrar', entry.name);
        if (name != null && name != entry.name && mounted) await operate(() => repo!.rename(entry, name));
        return;
      case 'delete':
        final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('¿Eliminar del teléfono?'),
          content: Text('Se eliminará permanentemente "${entry.name}"${entry.folder ? ' y todo su contenido' : ''}. No hay papelera.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar'))]));
        if (confirm == true && mounted) await operate(() => repo!.delete(entry));
        return;
      case 'copy':
      case 'move':
        setState(() { clipboard = entry; cutting = action == 'move'; });
        message('Abrí la carpeta de destino y tocá Pegar.');
        return;
      case 'share':
        try { await Share.shareXFiles([XFile(entry.path)]); }
        catch (e) { message('No se pudo compartir: $e'); }
        return;
      case 'info':
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: Text(entry.name), content: SelectableText('${entry.path}\n${entry.folder ? 'Carpeta' : formatBytes(entry.size)}\nModificado: ${entry.modified}\nMetadatos indexados en SQLite.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))]));
        return;
    }
  }

  bool get canUp => location != null && repo != null && !repo!.roots.contains(location);
  @override
  Widget build(BuildContext context) {
    final visible = entries.where((e) => e.name.toLowerCase().contains(query.toLowerCase())).toList();
    return PopScope(
      canPop: !canUp && !busy,
      onPopInvokedWithResult: (didPop, result) { if (!didPop && canUp && !busy) navigate(p.dirname(location!)); },
      child: Scaffold(
        appBar: AppBar(title: const Text('Archivos del teléfono'), actions: [
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
              Expanded(child: DropdownButton<String>(isExpanded: true, value: repo?.roots.where((r) => location == r || p.isWithin(r, location ?? '')).firstOrNull,
                hint: const Text('Almacenamiento'),
                items: (repo?.roots ?? []).map((r) => DropdownMenuItem(value: r, child: Text(r == repo!.roots.first ? 'Almacenamiento interno' : 'SD / USB: ${p.basename(r)}'))).toList(),
                onChanged: busy ? null : (r) { if (r != null) navigate(r); })),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Text(location ?? '', style: const TextStyle(fontSize: 12)))),
            Padding(padding: const EdgeInsets.all(12), child: TextField(controller: search, onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar en esta carpeta', border: OutlineInputBorder()))),
            if (clipboard != null) ListTile(leading: Icon(cutting ? Icons.drive_file_move : Icons.copy),
              title: Text(clipboard!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(cutting ? 'Mover a esta carpeta' : 'Copiar a esta carpeta'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(onPressed: busy ? null : () => operate(() async {
                  await repo!.paste(clipboard!, location!, move: cutting);
                  clipboard = null;
                }), child: const Text('Pegar')),
                IconButton(onPressed: busy ? null : () => setState(() => clipboard = null), icon: const Icon(Icons.close)),
              ])),
            if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
            Expanded(child: visible.isEmpty ? Center(child: Text(busy ? 'Cargando…' : error != null ? 'Revisá el permiso o elegí otra carpeta.' : 'No hay elementos en esta carpeta.')) : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90), itemCount: visible.length, itemBuilder: (ctx, index) {
                final entry = visible[index];
                return ListTile(leading: Icon(entry.folder ? Icons.folder : Icons.insert_drive_file, color: entry.folder ? Colors.amber.shade800 : Colors.teal),
                  title: Text(entry.name), subtitle: Text(entry.folder ? 'Carpeta' : formatBytes(entry.size)),
                  onTap: busy ? null : () async {
                    if (entry.folder) { await navigate(entry.path); return; }
                    try {
                      final result = await OpenFilex.open(entry.path);
                      if (result.type != ResultType.done) message(result.message);
                    } catch (e) { message('No se pudo abrir: $e'); }
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
            if (name != null && mounted) await operate(() => repo!.createFolder(location!, name));
          }, icon: const Icon(Icons.create_new_folder), label: const Text('Carpeta')) : null,
      ),
    );
  }
}
