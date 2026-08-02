import 'dart:async';
import 'dart:typed_data';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:dio/dio.dart';

class ApiBinaryResponse {
  const ApiBinaryResponse({
    required this.bytes,
    this.contentDisposition,
  });

  final Uint8List bytes;
  final String? contentDisposition;
}

class SignedAssetDownloadException implements Exception {
  const SignedAssetDownloadException({this.statusCode});

  final int? statusCode;
  bool get isExpired => statusCode == 401 || statusCode == 403;

  @override
  String toString() => isExpired
      ? 'SignedAssetDownloadException: signed address expired ($statusCode)'
      : 'SignedAssetDownloadException: download failed'
            '${statusCode == null ? '' : ' ($statusCode)'}';
}

class ApiClient {
  ApiClient({Dio? dio, Dio? publicDio, Dio? assetDio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
            ),
          ),
      _publicDio =
          publicDio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              headers: const {
                'Accept': 'application/json',
                'X-Client-Source': 'bird-companion-app',
                'X-Api-Version': 'v1',
              },
            ),
          ),
      _assetDio =
          assetDio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            ),
          );

  final Dio _dio;
  final Dio _publicDio;
  final Dio _assetDio;
  final _authenticationFailures = StreamController<int>.broadcast();

  Uri? get baseUri => _baseUri;
  Stream<int> get authenticationFailures => _authenticationFailures.stream;
  Uri? _baseUri;
  String? _accessToken;
  String _apiVersion = 'v1';

  void setSession({String? accessToken, String? apiVersion}) {
    _accessToken = accessToken;
    if (apiVersion != null && apiVersion.isNotEmpty) _apiVersion = apiVersion;
    _dio.options.headers['X-Api-Version'] = _apiVersion;
    _publicDio.options.headers['X-Api-Version'] = _apiVersion;
    if (accessToken == null || accessToken.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $accessToken';
    }
  }

  void configure(Uri baseUri) {
    if (!baseUri.hasScheme || baseUri.host.isEmpty) {
      throw ArgumentError.value(baseUri, 'baseUri', '必须是完整的盒子服务地址，例如 http://192.168.4.1:8080。');
    }
    _baseUri = baseUri;
    _dio.options.baseUrl = baseUri.toString().replaceFirst(RegExp(r'/$'), '');
    _dio.options.headers = {
      ..._dio.options.headers,
      'X-Client-Source': 'bird-companion-app',
      'X-Api-Version': _apiVersion,
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }

  /// Clear the in-memory address as well as persisted connection metadata.
  void clearSession() {
    _baseUri = null;
    _accessToken = null;
    _dio.options.baseUrl = '';
    _dio.options.headers.remove('Authorization');
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters}) => _request(
    () => _dio.get<Map<String, dynamic>>(path, queryParameters: queryParameters),
  );

  Future<Map<String, dynamic>> getUri(Uri uri, {CancelToken? cancelToken}) => _request(
    () => _publicDio.getUri<Map<String, dynamic>>(
      uri,
      cancelToken: cancelToken,
    ),
    reportAuthenticationFailure: false,
  );

  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey}) => _request(
    () => _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: Options(headers: {'X-Idempotency-Key': idempotencyKey ?? _newRequestId()}),
    ),
  );

  Future<Map<String, dynamic>> postUri(
    Uri uri, {
    Object? data,
    String? idempotencyKey,
  }) => _request(
    () => _publicDio.postUri<Map<String, dynamic>>(
      uri,
      data: data,
      options: Options(
        headers: {
          'X-Api-Version': _apiVersion,
          'X-Idempotency-Key': idempotencyKey ?? _newRequestId(),
        },
      ),
    ),
    reportAuthenticationFailure: false,
  );

  Future<Map<String, dynamic>> delete(String path) => _request(() => _dio.delete<Map<String, dynamic>>(path));

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() request, {
    bool reportAuthenticationFailure = true,
  }) async {
    try {
      final response = await request();
      final payload = unwrapResponse(response.data);
      final resolved = resolveMediaReferences(payload, baseUri: _baseUri);
      if (resolved is Map) return Map<String, dynamic>.from(resolved);
      throw const ProtocolCompatibilityException(
        'response.data',
        '当前端点必须返回对象',
      );
    } on DioException catch (error) {
      final exception = ApiException.fromDio(error);
      if (reportAuthenticationFailure && (exception.statusCode == 401 || exception.statusCode == 403)) {
        _authenticationFailures.add(exception.statusCode!);
      }
      throw exception;
    }
  }

  /// Downloads a short-lived signed asset without copying the REST Bearer
  /// token to a URL that may be hosted by another origin.
  Future<ApiBinaryResponse> downloadSignedBytes(Uri uri) async {
    try {
      final response = await _assetDio.getUri<List<int>>(
        uri,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const SignedAssetDownloadException();
      }
      return ApiBinaryResponse(
        bytes: Uint8List.fromList(data),
        contentDisposition: response.headers.value('content-disposition'),
      );
    } on DioException catch (error) {
      // Do not retain or expose the signed URL (including its query string).
      throw SignedAssetDownloadException(
        statusCode: error.response?.statusCode,
      );
    }
  }

  String resolveMediaReference(String value) {
    return _resolveMediaString(value, _baseUri);
  }

  /// Removes the optional `{data: ...}` success envelope without assuming
  /// whether the payload is an object, list, or a 204/null response.
  static Object? unwrapResponse(Object? value) {
    if (value == null) return const <String, dynamic>{};
    if (value is Map) {
      final normalized = Map<String, dynamic>.from(value);
      if (!normalized.containsKey('data')) return normalized;
      return normalized['data'] ?? const <String, dynamic>{};
    }
    if (value is List) return List<Object?>.from(value);
    throw const ProtocolCompatibilityException(
      'response',
      '必须是对象、列表或空响应',
    );
  }

  /// Resolves only contract-defined media references and leaves signed,
  /// absolute URLs untouched.
  static Object? resolveMediaReferences(
    Object? value, {
    Uri? baseUri,
    String? key,
  }) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): resolveMediaReferences(
            entry.value,
            baseUri: baseUri,
            key: entry.key.toString(),
          ),
      };
    }
    if (value is List) {
      return value.map((item) => resolveMediaReferences(item, baseUri: baseUri)).toList(growable: false);
    }
    if (value is String && (key == 'thumb_ref' || key == 'preview_ref')) {
      return _resolveMediaString(value, baseUri);
    }
    return value;
  }

  static String _resolveMediaString(String value, Uri? baseUri) {
    final reference = Uri.tryParse(value);
    if (reference == null || reference.hasScheme || baseUri == null) {
      return value;
    }
    return baseUri.resolveUri(reference).toString();
  }

  String _newRequestId() => 'app-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> dispose() async {
    await _authenticationFailures.close();
    _dio.close(force: true);
    _publicDio.close(force: true);
    _assetDio.close(force: true);
  }
}
