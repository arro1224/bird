import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({required this.message, this.code, this.statusCode, this.cause});

  final String message;
  final String? code;
  final int? statusCode;
  final Object? cause;

  factory ApiException.fromDio(DioException error) {
    final responseData = error.response?.data;
    final data = responseData is Map ? Map<String, dynamic>.from(responseData) : const <String, dynamic>{};
    return ApiException(
      message: data['error_message']?.toString() ?? data['message']?.toString() ?? error.message ?? '无法连接盒子服务。',
      code: data['error_code']?.toString(),
      statusCode: error.response?.statusCode,
      cause: error,
    );
  }

  @override
  String toString() => 'ApiException(code: $code, statusCode: $statusCode, message: $message)';
}
