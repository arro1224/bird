import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';

const copyModes = {'keep', 'all', 'dual'};

class StorageTarget {
  const StorageTarget({required this.id, required this.name, required this.freeBytes, required this.totalBytes, required this.online});
  final String id, name;
  final int freeBytes, totalBytes;
  final bool online;

  factory StorageTarget.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final online = json['online'];
    if (name is! String || name.trim().isEmpty) {
      throw const ProtocolCompatibilityException(
        'targets[].name',
        '必须是非空字符串',
      );
    }
    if (online is! bool) {
      throw const ProtocolCompatibilityException(
        'targets[].online',
        '必须是布尔值',
      );
    }
    return StorageTarget(
      id: ProtocolValidation.requiredId(json, 'id'),
      name: name.trim(),
      freeBytes: _requiredNonNegativeInt(json, 'free_bytes'),
      totalBytes: _requiredNonNegativeInt(json, 'total_bytes'),
      online: online,
    );
  }
}

class CopyEstimate {
  const CopyEstimate({
    required this.mode,
    required this.fileCount,
    required this.requiredBytes,
    required this.pendingCount,
    required this.targets,
    this.version = 0,
  });
  final String mode;
  final int fileCount, requiredBytes, pendingCount;
  final List<StorageTarget> targets;
  final int version;

  factory CopyEstimate.fromJson(
    Map<String, dynamic> json, {
    required String requestedMode,
  }) {
    final mode = ProtocolValidation.requiredId(json, 'mode');
    if (!copyModes.contains(mode) || mode != requestedMode) {
      throw ProtocolCompatibilityException(
        'mode',
        '必须与请求的复制范围 $requestedMode 一致',
      );
    }
    final rawTargets = json['targets'];
    if (rawTargets is! List) {
      throw const ProtocolCompatibilityException(
        'targets',
        '必须是目标存储列表',
      );
    }
    return CopyEstimate(
      mode: mode,
      fileCount: _requiredNonNegativeInt(json, 'file_count'),
      requiredBytes: _requiredNonNegativeInt(json, 'required_bytes'),
      pendingCount: _requiredNonNegativeInt(json, 'pending_count'),
      targets: rawTargets.indexed
          .map((entry) {
            final item = entry.$2;
            if (item is! Map) {
              throw ProtocolCompatibilityException(
                'targets[${entry.$1}]',
                '必须是对象',
              );
            }
            return StorageTarget.fromJson(Map<String, dynamic>.from(item));
          })
          .toList(growable: false),
      version: _requiredNonNegativeInt(json, 'version'),
    );
  }
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw ProtocolCompatibilityException(key, '不能为空');
  }
  return ProtocolValidation.nonNegativeInt(json, key);
}

abstract interface class CopyRepository {
  Future<CopyEstimate> estimate(String batchId, String mode);
  Future<BirdJobStatus> create(
    String batchId,
    String mode,
    String targetId, {
    required bool xmpEnabled,
    required bool verifyAfterCopy,
    required int version,
  });
}
