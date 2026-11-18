import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:dio/dio.dart';

final class ApiConnectionFailure {
  const ApiConnectionFailure({this.requestId, required this.route, required this.errorType});
  final String? requestId;
  final String route, errorType;
}

/// Records transport attempts only; no request/response body or arbitrary header
/// is ever serialized. Unknown route segments are replaced, not copied.
final class HttpRequestDiagnostics extends Interceptor {
  HttpRequestDiagnostics({RequestIdFactory? ids}) : _ids = ids ?? SecureRequestIdFactory();
  final RequestIdFactory _ids;
  void Function(Map<String, dynamic>)? record;
  Map<String, Object?> Function()? context;
  static const _key = 'bird_phone_http_trace';
  static String? requestId(RequestOptions? options) => (options?.extra[_key] as _HttpTrace?)?.id;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      String? supplied;
      for (final entry in options.headers.entries) {
        if (entry.key.toLowerCase() == 'x-request-id' && entry.value is String && isUuidV4(entry.value as String)) supplied = (entry.value as String).toLowerCase();
      }
      final id = supplied ?? _ids.create();
      final uri = options.uri;
      if (options.extra['bird_signed_asset'] != true && (uri.path.startsWith('${ApiEndpoints.apiV1Prefix}/') || uri.path == ApiEndpoints.health)) {
        options.headers.removeWhere((key, _) => key.toLowerCase() == 'x-request-id');
        options.headers['X-Request-Id'] = id;
      }
      final trace = _HttpTrace(id, {
        ...?context?.call(),
        'request_id': id,
        'method': const {'GET', 'POST', 'DELETE', 'PUT', 'PATCH', 'HEAD'}.contains(options.method) ? options.method : 'OTHER',
        'route': safeRoute(uri),
        'request_kind': uri.path == ApiEndpoints.health
            ? 'reachability'
            : uri.path.startsWith('${ApiEndpoints.apiV1Prefix}/')
            ? 'api'
            : 'asset_or_public',
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'queue_ms': null,
        'connect_ms': null,
        'receive_ms': null,
        'timing_source': 'dio_interceptor_total',
      });
      options.extra[_key] = trace;
      _emit({'event': 'http_request_started', ...trace.fields});
    } catch (_) {
      /* Observability cannot block requests. */
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _finish(response.requestOptions, response: response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _finish(err.requestOptions, response: err.response, error: err);
    handler.next(err);
  }

  void _finish(RequestOptions options, {Response? response, DioException? error}) {
    try {
      final trace = options.extra[_key];
      if (trace is! _HttpTrace || trace.finished) return;
      trace.finished = true;
      final responseId = response?.headers.map['x-request-id']?.firstOrNull;
      _emit({
        'event': 'http_request_finished',
        ...trace.fields,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'elapsed_ms': trace.clock.elapsedMilliseconds,
        'http_status': response?.statusCode,
        'response_request_id': responseId != null && isUuidV4(responseId) ? responseId.toLowerCase() : null,
        'outcome': error != null || (response?.statusCode ?? 0) >= 400 ? 'failed' : 'ok',
        'error_class': error?.type.name,
        'error_code': error?.type.name ?? ((response?.statusCode ?? 0) >= 400 ? 'http_error' : null),
        'cancelled': error?.type == DioExceptionType.cancel,
        'timeout': const {DioExceptionType.connectionTimeout, DioExceptionType.sendTimeout, DioExceptionType.receiveTimeout}.contains(error?.type),
      });
    } catch (_) {
      /* Never expose or serialize an exception value. */
    }
  }

  void _emit(Map<String, dynamic> fields) {
    try {
      record?.call(fields);
    } catch (_) {}
  }

  static String safeRoute(Uri uri) {
    final segments = uri.pathSegments;
    if (uri.path == '/health' || uri.path == '/healthz') return uri.path;
    if (segments.length < 3 || segments[0] != 'api' || segments[1] != 'v1') return '/{asset_or_unknown}';
    const roots = {
      'device',
      'projects',
      'files',
      'jobs',
      'storage',
      'species',
      'logs',
      'pairing',
      'recognition-capabilities',
      'copy-capabilities',
      'copy-preferences',
      'copy-scope-options',
      'batches',
      'copy-jobs',
      'copy-previews',
      'copy-selections',
      'copy-selection-sessions',
      'smart-follow-sessions',
      'smart-follow-metadata-updates',
      'metadata-update-previews',
      'smart-follow-metadata-previews',
      'events',
    };
    if (!roots.contains(segments[2])) return '${ApiEndpoints.apiV1Prefix}/{unknown}';
    const literals = {
      'current',
      'status',
      'pair',
      'session',
      'sessions',
      'refresh',
      'revoke',
      'cards',
      'scan',
      'rescan',
      'devices',
      'source',
      'files',
      'groups',
      'scenes',
      'actions',
      'analysis-jobs',
      'imports',
      'resume',
      'copy',
      'estimate',
      'thumbnail',
      'preview',
      'history',
      'decision',
      'failures',
      'report',
      'export',
      'recognition-events',
      'smart-follow-sessions',
      'copy-jobs',
      'copy-assets',
      'copy-selections',
      'copy-selection-sessions',
      'chunks',
      'seal',
      'items',
      'events',
      'metadata-update-availability',
      'metadata-updates',
      'alias',
      'safe-remove',
      'pause',
      'cancel',
      'retry',
    };
    return '${ApiEndpoints.apiV1Prefix}/${segments[2]}${segments.skip(3).map((s) => '/${literals.contains(s) ? s : '{id}'}').join()}';
  }
}

final class _HttpTrace {
  _HttpTrace(this.id, this.fields);
  final String id;
  final Map<String, Object?> fields;
  final clock = Stopwatch()..start();
  bool finished = false;
}
