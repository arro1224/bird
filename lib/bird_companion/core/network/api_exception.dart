import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.retryable = false,
    this.details = const {},
    this.cause,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final bool retryable;
  final Map<String, dynamic> details;
  final Object? cause;

  factory ApiException.fromDio(DioException error) {
    final responseData = error.response?.data;
    final data = responseData is Map ? Map<String, dynamic>.from(responseData) : const <String, dynamic>{};
    final nested = data['error'] is Map ? Map<String, dynamic>.from(data['error'] as Map) : const <String, dynamic>{};
    final statusCode = error.response?.statusCode;
    final detailsValue = data['details'] ?? nested['details'];
    final details = detailsValue is Map ? Map<String, dynamic>.from(detailsValue) : const <String, dynamic>{};
    final retryableValue = data['retryable'] ?? nested['retryable'];
    return ApiException(
      message: data['error_message']?.toString() ?? nested['message']?.toString() ?? data['message']?.toString() ?? error.message ?? '无法连接盒子服务。',
      code: data['error_code']?.toString() ?? nested['code']?.toString(),
      statusCode: statusCode,
      retryable: retryableValue is bool ? retryableValue : _isRetryable(error.type, statusCode),
      details: details,
      cause: error,
    );
  }

  static bool _isRetryable(DioExceptionType type, int? statusCode) {
    if (statusCode == 408 || statusCode == 429) return true;
    if (statusCode != null && statusCode >= 500) return true;
    return type == DioExceptionType.connectionError || type == DioExceptionType.connectionTimeout || type == DioExceptionType.receiveTimeout || type == DioExceptionType.sendTimeout;
  }

  @override
  String toString() =>
      'ApiException(code: $code, statusCode: $statusCode, '
      'retryable: $retryable, message: $message)';
}
