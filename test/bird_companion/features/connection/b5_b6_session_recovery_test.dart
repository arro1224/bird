import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('offline startup retains the saved device without reconnecting', () async {
    final repository = _RecoveryRepository(saved: _savedDevice);
    final events = EventClient();
    final refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(
      repository,
      _FixedConnectivityMonitor(false),
      events,
      refresh,
    );
    addTearDown(() async {
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });

    final restored = await session.restoreSavedSession();

    expect(restored, isFalse);
    expect(repository.reconnectCalls, 0);
    expect(session.state.device, _savedDevice);
    expect(session.state.isConnected, isFalse);
  });

  test('online startup restores once and runs retained-write recovery', () async {
    final repository = _RecoveryRepository(
      saved: _savedDevice,
      reconnectStatus: _status(_savedDevice),
    );
    final events = EventClient();
    final refresh = SessionRefreshCoordinator();
    var recoveryCalls = 0;
    final session = DeviceSessionCubit(
      repository,
      _FixedConnectivityMonitor(true),
      events,
      refresh,
      onConnectionRecovered: () async {
        recoveryCalls++;
      },
    );
    addTearDown(() async {
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });

    final restored = await session.restoreSavedSession();

    expect(restored, isTrue);
    expect(repository.reconnectCalls, 1);
    expect(recoveryCalls, 1);
    expect(session.state.isConnected, isTrue);
    expect(refresh.generation, 2);
  });

  test('dynamic address updates the active device and refreshes B views', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final acceptedSockets = <_AcceptedServerSocket>[];
    final firstSocketAccepted = Completer<_AcceptedServerSocket>();
    final serverSubscription = server.transform(WebSocketTransformer()).listen((
      socket,
    ) {
      final closed = Completer<void>();
      final accepted = _AcceptedServerSocket(
        socket: socket,
        closed: closed.future,
      );
      acceptedSockets.add(accepted);
      socket.listen(
        (_) {},
        onError: (_, _) {
          if (!closed.isCompleted) closed.complete();
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        cancelOnError: false,
      );
      if (!firstSocketAccepted.isCompleted) {
        firstSocketAccepted.complete(accepted);
      }
    });
    final api = ApiClient();
    final eventEndpoints = <Uri>[];
    final eventAuthorizations = <Object?>[];
    final clientChannels = <IOWebSocketChannel>[];
    final events = EventClient(
      connector: (endpoint, headers) {
        eventEndpoints.add(endpoint);
        eventAuthorizations.add(headers['Authorization']);
        final channel = IOWebSocketChannel.connect(endpoint, headers: headers);
        clientChannels.add(channel);
        return channel;
      },
    );
    final coordinator = SessionCoordinator(
      api,
      events,
      MemorySecureSessionStore(),
    );
    final refresh = SessionRefreshCoordinator();
    final repository = _RecoveryRepository(saved: _savedDevice);
    final session = DeviceSessionCubit(
      repository,
      _FixedConnectivityMonitor(true),
      events,
      refresh,
      sessionCoordinator: coordinator,
    );
    addTearDown(() async {
      try {
        await session.close();
        await coordinator.dispose();
        await events.dispose();
        await api.dispose();
        await refresh.dispose();
      } finally {
        try {
          await Future.wait(
            acceptedSockets.map((connection) => connection.socket.close()),
          );
        } finally {
          try {
            await serverSubscription.cancel();
          } finally {
            await server.close(force: true);
          }
        }
      }
    });

    final oldBase = Uri.parse('http://127.0.0.1:${server.port}');
    final newBase = Uri.parse('http://localhost:${server.port}');
    final oldDevice = _savedDevice.copyWith(baseUri: oldBase);
    await session.setConnectedFromStatus(_status(oldDevice));
    final credential = SessionCredential(
      deviceId: oldDevice.id,
      baseUri: oldBase,
      accessToken: 'synthetic-session-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      apiVersion: 'v1',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
    );
    await coordinator.activate(credential);
    final oldConnection = await firstSocketAccepted.future.timeout(
      const Duration(seconds: 2),
    );
    expect(acceptedSockets, hasLength(1));
    final generationBeforeMove = refresh.generation;

    await coordinator.activate(
      SessionCredential(
        deviceId: credential.deviceId,
        baseUri: newBase,
        accessToken: credential.accessToken,
        expiresAt: credential.expiresAt,
        apiVersion: credential.apiVersion,
        clientId: credential.clientId,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await clientChannels.first.sink.done.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('old client WebSocket sink stayed open'),
    );
    await oldConnection.closed.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('old server WebSocket stayed open'),
    );

    expect(session.state.device?.id, oldDevice.id);
    expect(session.state.device?.baseUri, newBase);
    expect(refresh.generation, greaterThan(generationBeforeMove));
    expect(api.baseUri, newBase);
    expect(eventEndpoints.last.host, 'localhost');
    expect(eventAuthorizations.last, 'Bearer synthetic-session-token');
    expect(
      api.resolveMediaReference('/media/photo-1/preview'),
      newBase.resolve('/media/photo-1/preview').toString(),
    );

    final generationBeforeForeignEvent = refresh.generation;
    await coordinator.activate(
      SessionCredential(
        deviceId: 'bbx-foreign-device',
        baseUri: oldBase,
        accessToken: credential.accessToken,
        expiresAt: credential.expiresAt,
        apiVersion: credential.apiVersion,
        clientId: credential.clientId,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(session.state.device?.id, oldDevice.id);
    expect(session.state.device?.baseUri, newBase);
    expect(refresh.generation, generationBeforeForeignEvent);
  });
}

final class _AcceptedServerSocket {
  const _AcceptedServerSocket({required this.socket, required this.closed});

  final WebSocket socket;
  final Future<void> closed;
}

final _savedDevice = DeviceConnection(
  id: 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
  name: '测试盒子',
  baseUri: Uri.parse('http://192.0.2.10:8080'),
  networkMode: NetworkMode.infrastructureSta,
  isPaired: true,
);

DeviceStatus _status(DeviceConnection device) => DeviceStatus(
  connection: device,
  card: const CardStatus(inserted: true, readable: true),
);

final class _FixedConnectivityMonitor extends ConnectivityMonitor {
  _FixedConnectivityMonitor(this.available);

  final bool available;

  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();

  @override
  Future<bool> get hasNetwork async => available;
}

final class _RecoveryRepository implements ConnectionRepository {
  _RecoveryRepository({required this.saved, this.reconnectStatus});

  final DeviceConnection? saved;
  final DeviceStatus? reconnectStatus;
  int reconnectCalls = 0;

  @override
  Future<DeviceConnection?> savedDevice() async => saved;

  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async {
    reconnectCalls++;
    return reconnectStatus ?? (throw StateError('offline'));
  }

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> forgetDevice() async {}
}
