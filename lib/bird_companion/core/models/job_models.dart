import 'package:equatable/equatable.dart';

enum BirdJobType { import, analysis, copy, sync, unknown }

enum BirdJobState { idle, running, paused, completed, failed, cancelled, unknown }

extension BirdJobTypeWireValue on BirdJobType {
  static BirdJobType fromWire(String? value) => switch (value) {
    'import' => BirdJobType.import,
    'analysis' => BirdJobType.analysis,
    'copy' => BirdJobType.copy,
    'sync' => BirdJobType.sync,
    _ => BirdJobType.unknown,
  };

  String get label => switch (this) {
    BirdJobType.import => '导入',
    BirdJobType.analysis => '分析',
    BirdJobType.copy => '复制',
    BirdJobType.sync => '同步',
    BirdJobType.unknown => '未知任务',
  };
}

extension BirdJobStateWireValue on BirdJobState {
  static BirdJobState fromWire(String? value) => switch (value) {
    'idle' => BirdJobState.idle,
    'running' => BirdJobState.running,
    'paused' => BirdJobState.paused,
    'completed' => BirdJobState.completed,
    'failed' => BirdJobState.failed,
    'cancelled' => BirdJobState.cancelled,
    _ => BirdJobState.unknown,
  };

  String get label => switch (this) {
    BirdJobState.idle => '空闲',
    BirdJobState.running => '运行中',
    BirdJobState.paused => '已暂停',
    BirdJobState.completed => '已完成',
    BirdJobState.failed => '异常',
    BirdJobState.cancelled => '已取消',
    BirdJobState.unknown => '状态未知',
  };
}

class BirdJobStatus extends Equatable {
  const BirdJobStatus({
    required this.id,
    required this.type,
    required this.state,
    this.progress = 0,
    this.totalCount = 0,
    this.finishedCount = 0,
    this.failedCount = 0,
    this.currentFile,
    this.speedBytesPerSecond,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final BirdJobType type;
  final BirdJobState state;
  final double progress;
  final int totalCount;
  final int finishedCount;
  final int failedCount;
  final String? currentFile;
  final double? speedBytesPerSecond;
  final String? errorCode;
  final String? errorMessage;

  bool get canPause => state == BirdJobState.running;
  bool get canResume => state == BirdJobState.paused;
  bool get canRetry => state == BirdJobState.failed;
  bool get canDelete => state == BirdJobState.completed || state == BirdJobState.failed || state == BirdJobState.cancelled;
  bool get canRestore => state == BirdJobState.cancelled;

  factory BirdJobStatus.fromJson(Map<String, dynamic> json) {
    return BirdJobStatus(
      id: json['job_id']?.toString() ?? '',
      type: BirdJobTypeWireValue.fromWire(json['job_type']?.toString()),
      state: BirdJobStateWireValue.fromWire(json['job_state']?.toString()),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      finishedCount: (json['finished_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      currentFile: json['current_file']?.toString(),
      speedBytesPerSecond: (json['speed_bytes_per_second'] as num?)?.toDouble(),
      errorCode: json['error_code']?.toString(),
      errorMessage: json['error_message']?.toString(),
    );
  }

  @override
  List<Object?> get props => [id, type, state, progress, totalCount, finishedCount, failedCount, currentFile, speedBytesPerSecond, errorCode, errorMessage];
}

class CopyJob extends Equatable {
  const CopyJob({required this.status, required this.mode, required this.targetPath});

  final BirdJobStatus status;
  final String mode;
  final String targetPath;

  @override
  List<Object?> get props => [status, mode, targetPath];
}
