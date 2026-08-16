import 'dart:convert';
import 'dart:typed_data';

import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:dio/dio.dart';

class MediaAssetHttpResponse {
  const MediaAssetHttpResponse({
    required this.notModified,
    required this.bytes,
    this.etag,
    this.contentType,
    this.maxAge = const Duration(hours: 1),
  });

  final bool notModified;
  final Uint8List? bytes;
  final String? etag;
  final String? contentType;
  final Duration maxAge;
}

/// Downloads signed media URLs without attaching the REST Bearer token.
class MediaAssetHttpClient {
  MediaAssetHttpClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            ),
          ),
      _ownsDio = dio == null;

  final Dio _dio;
  final bool _ownsDio;

  Future<MediaAssetHttpResponse> fetch(
    Uri uri, {
    String? ifNoneMatch,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.getUri<Object?>(
        uri,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
          headers: {
            if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) 'If-None-Match': ifNoneMatch,
          },
        ),
      );
      final statusCode = response.statusCode;
      if (statusCode == 304) {
        return MediaAssetHttpResponse(
          notModified: true,
          bytes: null,
          etag: response.headers.value('etag') ?? ifNoneMatch,
          maxAge: _maxAge(response.headers.value('cache-control')),
        );
      }
      if (statusCode != null && statusCode >= 200 && statusCode < 300) {
        final bytes = _bytes(response.data);
        if (bytes == null || bytes.isEmpty) {
          throw const MediaAssetFailure(
            kind: MediaAssetFailureKind.other,
            message: 'Media response was empty.',
          );
        }
        return MediaAssetHttpResponse(
          notModified: false,
          bytes: bytes,
          etag: response.headers.value('etag'),
          contentType: response.headers.value('content-type'),
          maxAge: _maxAge(response.headers.value('cache-control')),
        );
      }
      throw _failureFromResponse(response);
    } on MediaAssetFailure {
      rethrow;
    } on DioException catch (error) {
      final response = error.response;
      if (response != null) throw _failureFromResponse(response);
      if (error.type == DioExceptionType.cancel) {
        throw MediaAssetFailure(
          kind: MediaAssetFailureKind.cancelled,
          message: 'Media request was cancelled.',
          cause: error,
        );
      }
      throw MediaAssetFailure(
        kind: MediaAssetFailureKind.transient,
        message: error.message,
        retryable: true,
        cause: error,
      );
    }
  }

  MediaAssetFailure _failureFromResponse(Response<Object?> response) {
    final statusCode = response.statusCode;
    final body = _jsonObject(response.data);
    final errorCode = body['error_code']?.toString();
    final normalizedCode = errorCode?.toLowerCase();
    final detailsValue = body['details'];
    final details = detailsValue is Map ? Map<String, dynamic>.from(detailsValue) : const <String, dynamic>{};
    final retryableValue = body['retryable'];
    final retryAfter = _retryAfter(response.headers.value('retry-after'));
    final kind = switch ((statusCode, normalizedCode)) {
      (404, 'asset_not_ready') => MediaAssetFailureKind.notReady,
      (409, 'asset_failed') => MediaAssetFailureKind.assetFailed,
      (404, 'file_not_found') => MediaAssetFailureKind.fileNotFound,
      (401 || 403, _) => MediaAssetFailureKind.unauthorized,
      (408 || 429, _) => MediaAssetFailureKind.transient,
      (final int code, _) when code >= 500 => MediaAssetFailureKind.transient,
      _ => MediaAssetFailureKind.other,
    };
    return MediaAssetFailure(
      kind: kind,
      statusCode: statusCode,
      errorCode: errorCode,
      message: body['error_message']?.toString(),
      retryable: retryableValue is bool ? retryableValue : kind == MediaAssetFailureKind.notReady || kind == MediaAssetFailureKind.transient,
      retryAfter: retryAfter,
      details: details,
    );
  }

  static Uint8List? _bytes(Object? value) => switch (value) {
    Uint8List() => value,
    List<int>() => Uint8List.fromList(value),
    _ => null,
  };

  static Map<String, dynamic> _jsonObject(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    try {
      final bytes = _bytes(value);
      final decoded = jsonDecode(
        bytes == null ? value?.toString() ?? '' : utf8.decode(bytes),
      );
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  static Duration? _retryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    final date = DateTime.tryParse(value);
    if (date == null) return null;
    final difference = date.toUtc().difference(DateTime.now().toUtc());
    return difference.isNegative ? Duration.zero : difference;
  }

  static Duration _maxAge(String? value) {
    if (value == null) return const Duration(hours: 1);
    for (final part in value.split(',')) {
      final normalized = part.trim().toLowerCase();
      if (normalized == 'no-cache' || normalized == 'no-store') {
        return Duration.zero;
      }
      if (normalized.startsWith('max-age=')) {
        final seconds = int.tryParse(normalized.substring('max-age='.length));
        if (seconds != null && seconds >= 0) {
          return Duration(seconds: seconds);
        }
      }
    }
    return const Duration(hours: 1);
  }

  void dispose() {
    if (_ownsDio) _dio.close(force: true);
  }
}
