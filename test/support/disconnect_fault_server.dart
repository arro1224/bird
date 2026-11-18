import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/diagnostics/http_request_diagnostics.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

/// Loopback transport control only. Responses and credentials are synthetic;
/// this server does not perform recognition, storage or physical Wi-Fi changes.
class DisconnectFault {
  const DisconnectFault({this.status = 200, this.delay = Duration.zero, this.gate});
  final int status;
  final Duration delay;
  final Future<void>? gate;
}

class DisconnectFaultServer {
  DisconnectFaultServer({this.deviceId = 'bbx-5118b55118b55118b55118b55118b551'});
  static const token = 'b5-synthetic-loopback-token';
  final String deviceId;
  final faults = <String, DisconnectFault>{};
  final records = <Map<String, dynamic>>[];
  final sockets = <WebSocket>{};
  final _pending = <Future<void>>{};
  final _closing = Completer<void>();
  HttpServer? _server;
  late int _port;
  bool rejectEvents = false;
  int eventStatus = 503;
  Uri get baseUri => Uri.parse('http://127.0.0.1:$_port');
  Uri get eventUri => baseUri.replace(scheme: 'ws', path: '/api/v1/events');
  DeviceStatus get status => DeviceStatus(
    connection: DeviceConnection(id: deviceId, name: 'B5 loopback control', baseUri: baseUri, networkMode: NetworkMode.manual, isPaired: true),
    card: const CardStatus(inserted: true, readable: true),
  );

  Future<void> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _port = _server!.port;
    _server!.listen((request) {
      final task = _handle(request);
      _pending.add(task);
      unawaited(task.whenComplete(() => _pending.remove(task)));
    });
  }

  Future<void> _handle(HttpRequest request) async {
    final watch = Stopwatch()..start();
    final started = DateTime.now().toUtc().toIso8601String();
    final path = request.uri.path;
    final supplied = request.headers.value('X-Request-Id');
    final requestId = supplied != null && isUuidV4(supplied) ? supplied.toLowerCase() : SecureRequestIdFactory().create();
    var code = 200;
    var delivered = false;
    try {
      await request.drain<void>();
      if (path == '/api/v1/events') {
        if (rejectEvents) {
          code = eventStatus;
          request.response.statusCode = code;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        code = 101;
        socket.listen((_) {}, onError: (_, _) => sockets.remove(socket), onDone: () => sockets.remove(socket));
        return;
      }
      final fault = faults[path] ?? const DisconnectFault();
      code = fault.status;
      if (fault.gate != null) await Future.any([fault.gate!, _closing.future]);
      if (fault.delay > Duration.zero) await Future.any([Future<void>.delayed(fault.delay), _closing.future]);
      if (_closing.isCompleted) return;
      if (path != '/health' && path != '/api/v1/device/status' && request.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $token') code = 401;
      final Object payload = path == '/api/v1/device/status' ? statusJson() : {'healthy': true, 'items': <Object>[], 'synthetic': true};
      final bytes = utf8.encode(jsonEncode({'data': payload}));
      request.response
        ..statusCode = code
        ..headers.contentType = ContentType.json
        ..headers.set('X-Request-Id', requestId)
        ..contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
      delivered = true;
    } catch (_) {
      // A timed-out, suspended or cancelled client may close its socket.
    } finally {
      records.add({
        'event': path == '/api/v1/events' ? 'websocket_handshake' : 'api_request',
        'request_id': requestId,
        'route': HttpRequestDiagnostics.safeRoute(request.uri),
        'method': request.method,
        'status': code,
        'started_at': started,
        'finished_at': DateTime.now().toUtc().toIso8601String(),
        'elapsed_ms': watch.elapsedMilliseconds,
        'write_returned': delivered,
        'authorization_present': request.headers.value(HttpHeaders.authorizationHeader) != null,
        'environment': 'loopback_control',
      });
    }
  }

  Map<String, dynamic> statusJson() => {
    'device_id': deviceId,
    'device_name': 'B5 loopback control',
    'network_mode': 'manual',
    'software_version': 'synthetic-b5',
    'card': {'inserted': true, 'readable': true},
  };

  int requests(String route) => records.where((record) => record['route'] == route).length;

  Future<void> closeEvents([int code = 4000]) async {
    final active = sockets.toList();
    await Future.wait(active.map((socket) => socket.close(code)));
  }

  Future<void> suspend() async {
    final server = _server;
    _server = null;
    await closeEvents();
    await server?.close(force: true);
  }

  Future<void> resume() => start(port: _port);

  Future<void> settle() async {
    if (_pending.isNotEmpty) await Future.wait(_pending.toList());
  }

  Future<void> close() async {
    if (!_closing.isCompleted) _closing.complete();
    await suspend();
    await settle();
  }
}

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8767 : int.parse(args.single);
  final server = DisconnectFaultServer();
  await server.start(port: port);
  // Delays can be customized by a local harness through the class above.
  // No control endpoint is installed on a real box or production App.
  stdout.writeln('B5 synthetic transport control: ${server.baseUri}');
}
