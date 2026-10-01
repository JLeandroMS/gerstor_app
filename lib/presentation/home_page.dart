import 'package:flutter/material.dart';
import '../application/home_controller.dart';
import '../application/browser_controller.dart';
import '../domain/models/storage_overview.dart';
import '../entry.dart';
import 'device_page.dart';

/// Inicio visual. No utiliza canales Android, SQL ni servicios concretos.
class HomePage extends StatefulWidget {
  final HomeController controller;
  final BrowserController browserController;
  final WidgetBuilder privateBuilder;
  const HomePage({super.key, required this.controller, required this.browserController, required this.privateBuilder});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  HomeController get c => widget.controller;
  bool opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    c.refresh();
  }
  void _changed() { if (mounted) setState(() {}); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (ModalRoute.of(context)?.isCurrent ?? true)) c.refresh();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    super.dispose();
  }
  Future<void> openFolder(String path) async {
    if (opening || c.busy) return;
    setState(() => opening = true);
    try {
      final success = await widget.browserController.openLocation(path);
      if (!mounted) return;
      if (!success) {
        final message = widget.browserController.takeNotice() ?? 'No se pudo abrir esta carpeta.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        await c.refresh();
        return;
      }
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => DevicePage(
        controller: widget.browserController, privateBuilder: widget.privateBuilder)));
      if (mounted) await c.refresh();
    } finally { if (mounted) setState(() => opening = false); }
  }
  IconData folderIcon(String id) => switch (id) {
    'downloads' => Icons.download_rounded,
    'camera' => Icons.camera_alt_rounded,
    'pictures' => Icons.image_rounded,
    'documents' => Icons.description_rounded,
    'music' => Icons.music_note_rounded,
    'videos' => Icons.movie_rounded,
    _ => Icons.folder_rounded,
  };
  Widget volumeCard(StorageVolumeInfo volume) {
    final colors = Theme.of(context).colorScheme;
    return Card(margin: const EdgeInsets.only(bottom: 14), child: Padding(
      padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.storage_rounded, color: colors.primary), const SizedBox(width: 10),
          Expanded(child: Text(volume.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
        ]),
        const SizedBox(height: 18),
        if (volume.hasCapacity) ...[
          Text('${volume.usedPercent.toStringAsFixed(1)} % usado', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 23)),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(
            value: volume.usedFraction, minHeight: 10, backgroundColor: colors.surfaceContainerHighest,
            color: volume.usedFraction >= .9 ? colors.error : colors.primary,
            semanticsLabel: 'Porcentaje de almacenamiento utilizado',
            semanticsValue: '${volume.usedPercent.toStringAsFixed(1)} por ciento')),
          const SizedBox(height: 14),
          Wrap(spacing: 24, runSpacing: 12, children: [
            _capacityLabel('Usado', formatBytes(volume.usedBytes)),
            _capacityLabel('Disponible', formatBytes(volume.availableBytes)),
            _capacityLabel('Total', formatBytes(volume.totalBytes)),
          ]),
        ] else Text(volume.error ?? 'Capacidad no disponible'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(onPressed: opening || c.busy ? null : () => openFolder(volume.path),
          icon: const Icon(Icons.folder_open), label: const Text('Explorar archivos')),
      ])));
  }
  Widget _capacityLabel(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(label, style: const TextStyle(fontSize: 12)), Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))]);
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final overview = c.overview;
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso rápido'), actions: [
        IconButton(tooltip: 'Actualizar almacenamiento', onPressed: c.busy || opening ? null : () => c.refresh(), icon: const Icon(Icons.refresh)),
        PopupMenuButton<String>(enabled: !opening && !c.busy,
          onSelected: (_) async {
            await Navigator.push<void>(context, MaterialPageRoute(builder: widget.privateBuilder));
            if (mounted) await c.refresh();
          }, itemBuilder: (_) => [const PopupMenuItem(
            value: 'private', child: Text('Archivos guardados en la app'))]),
      ]),
      body: RefreshIndicator(onRefresh: () => c.refresh(), child: ListView(
        physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
          if (c.busy || opening) const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator()),
          if (c.error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.error!),
              TextButton(onPressed: c.busy ? null : () => c.refresh(), child: const Text('Reintentar'))]))),
          if (!c.access && !c.busy) Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.folder_open_rounded, size: 48, color: colors.primary), const SizedBox(height: 12),
              const Text('Accedé a tus archivos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 8),
              const Text('Habilitá “Permitir administrar todos los archivos” y regresá para ver tus carpetas.'),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => c.refresh(requestPermission: true), child: const Text('Dar acceso a los archivos')),
            ]))),
          if (c.access && overview != null) ...[
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 650 ? 3 : 2;
              final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(spacing: 12, runSpacing: 12, children: overview.shortcuts.map((folder) => SizedBox(
                width: width, child: Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
                  child: InkWell(onTap: !folder.available || opening || c.busy ? null : () => openFolder(folder.path),
                    child: Padding(padding: const EdgeInsets.all(16), child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(backgroundColor: folder.available ? colors.primaryContainer : colors.surfaceContainerHighest,
                          child: Icon(folderIcon(folder.id), color: folder.available ? colors.primary : colors.outline)),
                        const SizedBox(height: 12),
                        Text(folder.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        if (!folder.available) const Text('No disponible', style: TextStyle(fontSize: 12)),
                      ])))))).toList());
            }),
            const Padding(padding: EdgeInsets.only(top: 26, bottom: 12),
              child: Text('Almacenamiento', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700))),
            for (final volume in overview.volumes) volumeCard(volume),
            if (overview.volumes.isEmpty) const Text('No hay almacenamiento disponible.'),
          ],
          const SizedBox(height: 20),
        ])),
    );
  }
}
