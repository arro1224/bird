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
    result: switch (json['result']?.toString()) {
      'success' => JobReportResult.success,
      'partial_success' => JobReportResult.partialSuccess,
      'failed' => JobReportResult.failed,
      'cancelled' => JobReportResult.cancelled,
      _ => JobReportResult.unknown,
    },
    totalCount: ProtocolValidation.nonNegativeInt(json, 'total_count'),
    successCount: ProtocolValidation.nonNegativeInt(json, 'success_count'),
    failedCount: ProtocolValidation.nonNegativeInt(json, 'failed_count'),
    skippedCount: ProtocolValidation.nonNegativeInt(json, 'skipped_count'),
    copiedBytes: ProtocolValidation.optionalNonNegativeInt(
      json,
      'copied_bytes',
    ),
    manifestId: json['manifest_id']?.toString(),
    startedAt: ProtocolValidation.optionalDateTime(json, 'started_at'),
    finishedAt: ProtocolValidation.optionalDateTime(json, 'finished_at'),
  );
}
