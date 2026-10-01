/// Datos del sistema de archivos. No depende de Flutter ni de un canal nativo.
class StorageVolumeInfo {
  final String path;
  final String label;
  final int totalBytes;
  final int freeBytes;
  final int availableBytes;
  final String? error;
  const StorageVolumeInfo({required this.path, required this.label,
    required this.totalBytes, required this.freeBytes, required this.availableBytes, this.error});
  bool get hasCapacity => error == null && totalBytes > 0;
  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes > 0 ? totalBytes : 0).toInt();
  double get usedFraction => hasCapacity ? (usedBytes / totalBytes).clamp(0.0, 1.0).toDouble() : 0;
  double get usedPercent => usedFraction * 100;
  factory StorageVolumeInfo.fromMap(Map<Object?, Object?> map) => StorageVolumeInfo(
    path: map['path'] as String, label: map['label'] as String,
    totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
    freeBytes: (map['freeBytes'] as num?)?.toInt() ?? 0,
    availableBytes: (map['availableBytes'] as num?)?.toInt() ?? 0,
    error: map['error'] as String?);
}
class QuickFolder {
  final String id;
  final String label;
  final String path;
  final bool available;
  const QuickFolder({required this.id, required this.label, required this.path, required this.available});
  factory QuickFolder.fromMap(Map<Object?, Object?> map) => QuickFolder(
    id: map['id'] as String, label: map['label'] as String,
    path: map['path'] as String, available: map['available'] == true);
}
class StorageOverview {
  final List<StorageVolumeInfo> volumes;
  final List<QuickFolder> shortcuts;
  StorageOverview({required List<StorageVolumeInfo> volumes, required List<QuickFolder> shortcuts})
    : volumes = List.unmodifiable(volumes), shortcuts = List.unmodifiable(shortcuts);
  factory StorageOverview.fromMap(Map<Object?, Object?> map) => StorageOverview(
    volumes: (map['volumes'] as List? ?? []).map((v) => StorageVolumeInfo.fromMap(Map<Object?, Object?>.from(v as Map))).toList(),
    shortcuts: (map['shortcuts'] as List? ?? []).map((v) => QuickFolder.fromMap(Map<Object?, Object?>.from(v as Map))).toList());
}
