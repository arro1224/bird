import 'package:aves/bird_companion/core/models/protocol_validation.dart';

class JobFailure {
  const JobFailure({
    required this.fileId,
    required this.reason,
    this.filename,
    this.code,
    this.retryable = true,
  });
  final String fileId;
  final String? filename;
  final String reason;
  final String? code;
  final bool retryable;

  factory JobFailure.fromJson(Map<String, dynamic> json) {
    final reason = json['reason'];
    final retryable = json['retryable'];
    if (reason is! String || reason.trim().isEmpty) {
      throw const ProtocolCompatibilityException(
        'failures[].reason',
        '必须是非空字符串',
      );
    }
    if (retryable != null && retryable is! bool) {
      throw const ProtocolCompatibilityException(
        'failures[].retryable',
        '必须是布尔值',
      );
    }
    final filename = json['filename'];
    return JobFailure(
      fileId: ProtocolValidation.requiredId(json, 'file_id'),
      filename: filename is String && filename.trim().isNotEmpty ? filename.trim() : null,
      reason: reason.trim(),
      code: json['error_code']?.toString(),
      retryable: retryable == true,
    );
  }
}
