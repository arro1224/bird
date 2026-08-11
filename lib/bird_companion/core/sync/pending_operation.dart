import 'package:equatable/equatable.dart';

enum PendingOperationType { updateReview, batchReview, controlJob, createCopyJob }

enum PendingOperationStatus { pending, syncing, failed, conflict }

class PendingOperation extends Equatable {
  const PendingOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.version,
    this.retryCount = 0,
    this.source = 'app',
    this.deviceId,
    this.projectId,
    this.fileId,
    this.status = PendingOperationStatus.pending,
    this.failureReason,
  });

  final String id;
  final PendingOperationType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int? version;
  final int retryCount;
  final String source;
  final String? deviceId;
  final String? projectId;
  final String? fileId;
  final PendingOperationStatus status;
  final String? failureReason;

  PendingOperation copyWith({
    int? retryCount,
    PendingOperationStatus? status,
    String? failureReason,
    bool clearFailureReason = false,
  }) => PendingOperation(
    id: id,
    type: type,
    payload: payload,
    createdAt: createdAt,
    version: version,
    retryCount: retryCount ?? this.retryCount,
    source: source,
    deviceId: deviceId,
    projectId: projectId,
    fileId: fileId,
    status: status ?? this.status,
    failureReason: clearFailureReason ? null : failureReason ?? this.failureReason,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
    'version': version,
    'retry_count': retryCount,
    'source': source,
    'device_id': deviceId,
    'project_id': projectId,
    'file_id': fileId,
    'status': status.name,
    'failure_reason': failureReason,
  };

  factory PendingOperation.fromJson(Map<String, dynamic> json) {
    final type = PendingOperationType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => PendingOperationType.updateReview,
    );
    final payload = json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : <String, dynamic>{};
    final projectId = _firstNonEmpty([
      json['project_id'],
      payload['project_id'],
      payload['batch_id'],
    ]);
    if (type == PendingOperationType.batchReview) {
      payload
        ..remove('batch_id')
        ..remove('project_id');
    }

    return PendingOperation(
      id: json['id']?.toString() ?? '',
      type: type,
      payload: payload,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      version: (json['version'] as num?)?.toInt(),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      source: json['source']?.toString() ?? 'app',
      deviceId: json['device_id']?.toString(),
      projectId: projectId,
      fileId: json['file_id']?.toString() ?? payload['file_id']?.toString(),
      status: PendingOperationStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => PendingOperationStatus.pending,
      ),
      failureReason: json['failure_reason']?.toString(),
    );
  }

  static String? _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    id,
    type,
    payload,
    createdAt,
    version,
    retryCount,
    source,
    deviceId,
    projectId,
    fileId,
    status,
    failureReason,
  ];
}
