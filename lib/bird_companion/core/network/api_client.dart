import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  Uri? get baseUri => _baseUri;
  Uri? _baseUri;
  String? _accessToken;
  String _apiVersion = 'v1';

  void setSession({String? accessToken, String? apiVersion}) {
    _accessToken = accessToken;
    if (apiVersion != null && apiVersion.isNotEmpty) _apiVersion = apiVersion;
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

  Future<Map<String, dynamic>> getUri(Uri uri, {CancelToken? cancelToken}) => _request(() => _dio.getUri<Map<String, dynamic>>(uri, cancelToken: cancelToken));

  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey}) => _request(
    () => _dio.post<Map<String, dynamic>>(
      path,
      data: data,
      options: Options(headers: {'X-Idempotency-Key': idempotencyKey ?? _newRequestId()}),
    ),
  );

  Future<Map<String, dynamic>> delete(String path) => _request(() => _dio.delete<Map<String, dynamic>>(path));

  Future<Map<String, dynamic>> _request(Future<Response<Map<String, dynamic>>> Function() request) async {
    try {
      final response = await request();
      final data = response.data;
      if (data == null) return const {};
      final envelope = data['data'];
      return envelope is Map ? Map<String, dynamic>.from(envelope) : data;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  String _newRequestId() => 'app-${DateTime.now().microsecondsSinceEpoch}';
}
