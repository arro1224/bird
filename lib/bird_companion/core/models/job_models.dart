import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:equatable/equatable.dart';

const jobControlActions = {
  'pause',
  'resume',
  'cancel',
  'retry_failed',
  'skip_failed',
};

const jobAvailableActions = {...jobControlActions, 'delete'};

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
    this.startedAt,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
    this.errorCode,
    this.errorMessage,
    this.version,
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
  final DateTime? startedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;
  final String? errorCode;
  final String? errorMessage;
  final int? version;

  bool get canPause => availableActions.contains('pause');
  bool get canResume => state != BirdJobState.cancelled && availableActions.contains('resume');
  bool get canRetry => availableActions.contains('retry_failed');
  bool get canCancel => availableActions.contains('cancel');
  bool get canSkipFailed => availableActions.contains('skip_failed');
  bool get canDelete => availableActions.contains('delete');
  bool get canRestore => state == BirdJobState.cancelled && availableActions.contains('resume');

  factory BirdJobStatus.fromJson(Map<String, dynamic> json) {
    final type = BirdJobTypeWireValue.fromWire(
      ProtocolValidation.requiredId(json, 'job_type'),
    );
    final state = BirdJobStateWireValue.fromWire(
      ProtocolValidation.requiredId(json, 'job_state'),
    );
    if (type == BirdJobType.unknown) {
      throw const ProtocolCompatibilityException(
        'job_type',
        '不是 birdbox-v1 支持的任务类型',
      );
    }
    if (state == BirdJobState.unknown || state == BirdJobState.idle) {
      throw const ProtocolCompatibilityException(
        'job_state',
        '不是 birdbox-v1 支持的任务状态',
      );
    }
    return BirdJobStatus(
      id: ProtocolValidation.requiredId(json, 'job_id'),
      type: type,
      state: state,
      progress: _requiredUnitInterval(json, 'progress'),
      totalCount: _requiredNonNegativeInt(json, 'total_count'),
      finishedCount: _requiredNonNegativeInt(
        json,
        'finished_count',
      ),
      failedCount: _requiredNonNegativeInt(json, 'failed_count'),
      currentFile: json['current_file']?.toString(),
      speedBytesPerSecond: ProtocolValidation.optionalNonNegativeDouble(
        json,
        'speed_bytes_per_second',
      ),
      sourceProjectId: json['source_project_id']?.toString(),
      sourceProjectName: json['source_project_name']?.toString(),
      workflowStage: json['workflow_stage']?.toString(),
      skippedCount: _requiredNonNegativeInt(json, 'skipped_count'),
      estimatedRemainingSeconds: json['estimated_remaining_seconds'] == null
          ? null
          : ProtocolValidation.nonNegativeInt(
              json,
              'estimated_remaining_seconds',
            ),
      availableActions: _availableActions(json),
      startedAt: ProtocolValidation.optionalDateTime(json, 'started_at'),
      createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
      updatedAt: ProtocolValidation.optionalDateTime(json, 'updated_at'),
      finishedAt: ProtocolValidation.optionalDateTime(json, 'finished_at'),
      errorCode: json['error_code']?.toString(),
      errorMessage: json['error_message']?.toString(),
      version: ProtocolValidation.optionalNonNegativeInt(json, 'version'),
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
    if (startedAt != null) 'started_at': startedAt!.toUtc().toIso8601String(),
    if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
    if (finishedAt != null) 'finished_at': finishedAt!.toUtc().toIso8601String(),
    if (errorCode != null) 'error_code': errorCode,
    if (errorMessage != null) 'error_message': errorMessage,
    if (version != null) 'version': version,
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
    startedAt,
    createdAt,
    updatedAt,
    finishedAt,
    errorCode,
    errorMessage,
    version,
  ];
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw ProtocolCompatibilityException(key, '不能为空');
  }
  return ProtocolValidation.nonNegativeInt(json, key);
}

double _requiredUnitInterval(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw ProtocolCompatibilityException(key, '不能为空');
  }
  return ProtocolValidation.unitInterval(json, key);
}

List<String> _availableActions(Map<String, dynamic> json) {
  final raw = json['available_actions'];
  if (raw is! List) {
    throw const ProtocolCompatibilityException(
      'available_actions',
      '必须是动作列表',
    );
  }
  final actions = <String>[];
  final seen = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final value = raw[index];
    if (value is! String || !jobAvailableActions.contains(value)) {
      throw ProtocolCompatibilityException(
        'available_actions[$index]',
        '不是 birdbox-v1 支持的任务动作',
      );
    }
    if (!seen.add(value)) {
      throw ProtocolCompatibilityException(
        'available_actions[$index]',
        '不能重复',
      );
    }
    actions.add(value);
  }
  return List.unmodifiable(actions);
}

class CopyJob extends Equatable {
  const CopyJob({required this.status, required this.mode, required this.targetPath});

  final BirdJobStatus status;
  final String mode;
  final String targetPath;

  @override
  List<Object?> get props => [status, mode, targetPath];
}
