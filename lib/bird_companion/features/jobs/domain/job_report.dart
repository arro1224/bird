import 'package:aves/bird_companion/core/models/protocol_validation.dart';

enum JobReportResult {
  success,
  partialSuccess,
  failed,
  cancelled,
  unknown,
}

class JobReport {
  const JobReport({
    required this.jobId,
    required this.result,
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
    required this.skippedCount,
    this.copiedBytes,
    this.manifestId,
    this.startedAt,
    this.finishedAt,
  });

  final String jobId;
  final JobReportResult result;
  final int totalCount;
  final int successCount;
  final int failedCount;
  final int skippedCount;
  final int? copiedBytes;
  final String? manifestId;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  factory JobReport.fromJson(Map<String, dynamic> json) => JobReport(
    jobId: ProtocolValidation.requiredId(json, 'job_id'),
    result: _requiredResult(json),
    totalCount: _requiredNonNegativeInt(json, 'total_count'),
    successCount: _requiredNonNegativeInt(json, 'success_count'),
    failedCount: _requiredNonNegativeInt(json, 'failed_count'),
    skippedCount: _requiredNonNegativeInt(json, 'skipped_count'),
    copiedBytes: _optionalNonNegativeInt(json, 'copied_bytes'),
    manifestId: _optionalString(json, 'manifest_id'),
    startedAt: _optionalDateTime(json, 'started_at'),
    finishedAt: _optionalDateTime(json, 'finished_at'),
  );

  static JobReportResult _requiredResult(Map<String, dynamic> json) {
    final result = json['result'];
    return switch (result) {
      'success' => JobReportResult.success,
      'partial_success' => JobReportResult.partialSuccess,
      'failed' => JobReportResult.failed,
      'cancelled' => JobReportResult.cancelled,
      _ => throw const ProtocolCompatibilityException(
        'result',
        '必须是 birdbox-v1 定义的任务结果',
      ),
    };
  }

  static int _requiredNonNegativeInt(
    Map<String, dynamic> json,
    String key,
  ) {
    if (!json.containsKey(key) || json[key] == null) {
      throw ProtocolCompatibilityException(key, '不能为空');
    }
    return ProtocolValidation.nonNegativeInt(json, key);
  }

  static int? _optionalNonNegativeInt(
    Map<String, dynamic> json,
    String key,
  ) {
    if (!json.containsKey(key)) return null;
    if (json[key] == null) {
      throw ProtocolCompatibilityException(key, '存在时必须是非负整数');
    }
    return ProtocolValidation.nonNegativeInt(json, key);
  }

  static String? _optionalString(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw ProtocolCompatibilityException(key, '必须是字符串或 null');
    }
    return value;
  }

  static DateTime? _optionalDateTime(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw ProtocolCompatibilityException(key, '必须是 ISO-8601 时间或 null');
    }
    return ProtocolValidation.optionalDateTime(json, key);
  }
}
