class JobFailure {
  const JobFailure({required this.fileId, required this.reason, this.code, this.retryable = true});
  final String fileId;
  final String reason;
  final String? code;
  final bool retryable;
  factory JobFailure.fromJson(Map<String, dynamic> json) =>
      JobFailure(fileId: json['file_id']?.toString() ?? '', reason: json['reason']?.toString() ?? json['message']?.toString() ?? '未知错误', code: json['error_code']?.toString(), retryable: json['retryable'] != false);
}
