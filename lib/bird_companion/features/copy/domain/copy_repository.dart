import 'package:aves/bird_companion/core/models/job_models.dart';

class StorageTarget {
  const StorageTarget({required this.id, required this.name, required this.freeBytes, required this.totalBytes, required this.online});
  final String id, name;
  final int freeBytes, totalBytes;
  final bool online;
  factory StorageTarget.fromJson(Map<String, dynamic> j) =>
      StorageTarget(id: j['id']?.toString() ?? '', name: j['name']?.toString() ?? '目标存储', freeBytes: (j['free_bytes'] as num?)?.toInt() ?? 0, totalBytes: (j['total_bytes'] as num?)?.toInt() ?? 0, online: j['online'] != false);
}

class CopyEstimate {
  const CopyEstimate({required this.mode, required this.fileCount, required this.requiredBytes, required this.pendingCount, required this.targets});
  final String mode;
  final int fileCount, requiredBytes, pendingCount;
  final List<StorageTarget> targets;
}

abstract interface class CopyRepository {
  Future<CopyEstimate> estimate(String batchId, String mode);
  Future<BirdJobStatus> create(String batchId, String mode, String targetId, {required bool xmpEnabled});
}
