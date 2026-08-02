import 'package:equatable/equatable.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';

enum BirdJobType { import, analysis, copy, sync, unknown }

enum BirdJobState {
  queued,
  idle,
  running,
  paused,
  completed,
  failed,
  cancelled,
  unknown,
}

extension BirdJobTypeWireValue on BirdJobType {
  static BirdJobType fromWire(String? value) => switch (value) {
    'import' => BirdJobType.import,
    'analysis' => BirdJobType.analysis,
    'copy' => BirdJobType.copy,
    'sync' => BirdJobType.sync,
    _ => BirdJobType.unknown,
  };

  String get label => switch (this) {
    BirdJobType.import => '读取照片',
    BirdJobType.analysis => '识别照片',
    BirdJobType.copy => '保存照片',
    BirdJobType.sync => '更新修改',
    BirdJobType.unknown => '其他处理',
  };
}

extension BirdJobStateWireValue on BirdJobState {
  static BirdJobState fromWire(String? value) => switch (value) {
    'queued' => BirdJobState.queued,
    'idle' => BirdJobState.idle,
    'running' => BirdJobState.running,
    'paused' => BirdJobState.paused,
    'completed' => BirdJobState.completed,
    'failed' => BirdJobState.failed,
    'cancelled' => BirdJobState.cancelled,
    _ => BirdJobState.unknown,
  };

  String get label => switch (this) {
    BirdJobState.queued => '等待开始',
    BirdJobState.idle => '等待开始',
    BirdJobState.running => '正在处理',
    BirdJobState.paused => '已暂停',
    BirdJobState.completed => '已完成',
    BirdJobState.failed => '处理失败',
    BirdJobState.cancelled => '已取消',
    BirdJobState.unknown => '暂时无法确认',
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
    this.sourceProjectId,
    this.sourceProjectName,
    this.workflowStage,
    this.skippedCount = 0,
    this.estimatedRemainingSeconds,
    this.availableActions = const [],
    this.createdAt,
    this.updatedAt,
    this.errorCode,
    this.errorMessage,
    this.version = 0,
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
  final String? sourceProjectId;
  final String? sourceProjectName;
  final String? workflowStage;
  final int skippedCount;
  final int? estimatedRemainingSeconds;
  final List<String> availableActions;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? errorCode;
  final String? errorMessage;
  final int version;

  bool get canPause => state == BirdJobState.running;
  bool get canResume => state == BirdJobState.paused;
  bool get canRetry => state == BirdJobState.failed;
  bool get canDelete => state == BirdJobState.completed || state == BirdJobState.failed || state == BirdJobState.cancelled;
  bool get canRestore => state == BirdJobState.cancelled;

  factory BirdJobStatus.fromJson(Map<String, dynamic> json) {
    return BirdJobStatus(
      id: ProtocolValidation.requiredId(json, 'job_id'),
      type: BirdJobTypeWireValue.fromWire(json['job_type']?.toString()),
      state: BirdJobStateWireValue.fromWire(json['job_state']?.toString()),
      progress: ProtocolValidation.unitInterval(json, 'progress'),
      totalCount: ProtocolValidation.nonNegativeInt(json, 'total_count'),
      finishedCount: ProtocolValidation.nonNegativeInt(
        json,
        'finished_count',
      ),
      failedCount: ProtocolValidation.nonNegativeInt(json, 'failed_count'),
      currentFile: json['current_file']?.toString(),
      speedBytesPerSecond: ProtocolValidation.optionalNonNegativeDouble(
        json,
        'speed_bytes_per_second',
      ),
      sourceProjectId: json['source_project_id']?.toString(),
      sourceProjectName: json['source_project_name']?.toString(),
      workflowStage: json['workflow_stage']?.toString(),
      skippedCount: ProtocolValidation.nonNegativeInt(json, 'skipped_count'),
      estimatedRemainingSeconds: json['estimated_remaining_seconds'] == null
          ? null
          : ProtocolValidation.nonNegativeInt(
              json,
              'estimated_remaining_seconds',
            ),
      availableActions: (json['available_actions'] as List? ?? const []).map((value) => value.toString()).toList(growable: false),
      createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
      updatedAt: ProtocolValidation.optionalDateTime(json, 'updated_at'),
      errorCode: json['error_code']?.toString(),
      errorMessage: json['error_message']?.toString(),
      version: ProtocolValidation.nonNegativeInt(json, 'version'),
    );
  }

  Map<String, dynamic> toJson() => {
    'job_id': id,
    'job_type': type.name,
    'job_state': state == BirdJobState.idle ? 'idle' : state.name,
    'progress': progress,
    'total_count': totalCount,
    'finished_count': finishedCount,
    'failed_count': failedCount,
    'skipped_count': skippedCount,
    'available_actions': availableActions,
    if (currentFile != null) 'current_file': currentFile,
    if (speedBytesPerSecond != null) 'speed_bytes_per_second': speedBytesPerSecond,
    if (sourceProjectId != null) 'source_project_id': sourceProjectId,
    if (sourceProjectName != null) 'source_project_name': sourceProjectName,
    if (workflowStage != null) 'workflow_stage': workflowStage,
    if (estimatedRemainingSeconds != null) 'estimated_remaining_seconds': estimatedRemainingSeconds,
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
    if (errorCode != null) 'error_code': errorCode,
    if (errorMessage != null) 'error_message': errorMessage,
    'version': version,
  };

  @override
  List<Object?> get props => [
    id,
    type,
    state,
    progress,
    totalCount,
    finishedCount,
    failedCount,
    currentFile,
    speedBytesPerSecond,
    sourceProjectId,
    sourceProjectName,
    workflowStage,
    skippedCount,
    estimatedRemainingSeconds,
    availableActions,
    createdAt,
    updatedAt,
    errorCode,
    errorMessage,
    version,
  ];
}

class CopyJob extends Equatable {
  const CopyJob({required this.status, required this.mode, required this.targetPath});

  final BirdJobStatus status;
  final String mode;
  final String targetPath;

  @override
  List<Object?> get props => [status, mode, targetPath];
}
