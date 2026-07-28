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
    'status': status.name,
    'failure_reason': failureReason,
  };

  factory PendingOperation.fromJson(Map<String, dynamic> json) => PendingOperation(
    id: json['id']?.toString() ?? '',
    type: PendingOperationType.values.firstWhere((type) => type.name == json['type'], orElse: () => PendingOperationType.updateReview),
    payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : const {},
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    version: (json['version'] as num?)?.toInt(),
    retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
    source: json['source']?.toString() ?? 'app',
    deviceId: json['device_id']?.toString(),
    status: PendingOperationStatus.values.firstWhere((value) => value.name == json['status'], orElse: () => PendingOperationStatus.pending),
    failureReason: json['failure_reason']?.toString(),
  );

  @override
  List<Object?> get props => [id, type, payload, createdAt, version, retryCount, source, deviceId, status, failureReason];
}
