import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/storage/cache_schema_migrator.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/connection_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'direct_ap_handoff_test.dart' show MemoryHandoffStorage, until;

void main() {
  test('old authentication cleanup cannot delete a newly activated credential or report it offline', () async {
    final api = _AuthApi(), events = _SlowEvents()..ready.complete();
    final store = SerializedSecureSessionStore(MemorySecureSessionStore());
    final coordinator = SessionCoordinator(api, events, store);
    final failures = <SessionAuthenticationFailure>[];
    final subscription = coordinator.authenticationFailures.listen(failures.add);
    await coordinator.activate(_credential(_oldDevice.baseUri));
    final oldClose = Completer<void>();
    events.nextDisconnect = oldClose;
    api.failures.add(401);
    await until(() => events.disconnects == 2);
    await coordinator.activate(_credential(_newDevice.baseUri));
    oldClose.complete();
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.activeBaseUri, _newDevice.baseUri);
    expect((await store.read(_oldDevice.id))!.baseUri, _newDevice.baseUri);
    expect(failures, isEmpty);
    await subscription.cancel();
    await coordinator.dispose();
    await events.dispose();
    await api.dispose();
  });

  test('the same authenticated socket can finish for a newer verifier without restarting', () async {
    final api = ApiClient(), events = _SlowEvents();
    final coordinator = SessionCoordinator(api, events, MemorySecureSessionStore());
    final tokenA = CancelToken(), tokenB = CancelToken();
    final credential = _credential(_oldDevice.baseUri);
    final first = coordinator.activate(credential, persist: false, cancelToken: tokenA);
    final cancelled = expectLater(first, throwsA(isA<DioException>()));
    await until(() => events.currentState == EventConnectionState.connecting);
    tokenA.cancel('superseded');
    final second = coordinator.activate(credential, persist: false, cancelToken: tokenB);
    events.ready.complete();
    await second;
    await cancelled;
    coordinator.requireConnectedSession(_oldDevice.id, _oldDevice.baseUri);
    expect(events.connects, 1);
    expect(events.disconnects, 1);
    await coordinator.dispose();
    await events.dispose();
    await api.dispose();
  });

  test('saved endpoint is tried before discovery, fallback is restricted to the same identity', () async {
    final cache = MemoryHandoffStorage();
    await cache.write(CacheSchemaMigrator.activeDeviceKey, _oldDevice.toJson());
    final calls = <Uri>[];
    final api = _Api((uri, expected, token) async {
      calls.add(uri);
      expect(expected, _oldDevice.id);
      if (uri == _oldDevice.baseUri) throw TimeoutException('stale address');
      return _status(_newDevice);
    });
    var discovered = 0;
    final repository = ConnectionRepositoryImpl(
      api,
      cache,
      KnownDeviceDiscoverySource(() async {
        discovered++;
        expect(calls, [_oldDevice.baseUri]);
        return [DeviceConnection(id: 'other-device', name: 'other', baseUri: _newDevice.baseUri, networkMode: NetworkMode.infrastructureSta), _newDevice];
      }),
    );
    expect((await repository.reconnect()).connection.baseUri, _newDevice.baseUri);
    expect(discovered, 1);
    expect(calls, [_oldDevice.baseUri, _newDevice.baseUri]);
  });

  test('a cancelled platform save cannot finish after and overwrite the next saved address', () async {
    final cache = _DelayedCache();
    final repository = ConnectionRepositoryImpl(_Api((uri, _, _) async => _status(uri == _oldDevice.baseUri ? _oldDevice : _newDevice)), cache, KnownDeviceDiscoverySource(() async => []));
    final token = CancelToken();
    final old = repository.connectExpected(_oldDevice.baseUri, networkMode: NetworkMode.infrastructureSta, expectedDeviceId: _oldDevice.id, cancelToken: token);
    final rejected = expectLater(old, throwsA(isA<DioException>()));
    await until(() => cache.started);
    token.cancel('new intent');
    final next = repository.connectExpected(_newDevice.baseUri, networkMode: NetworkMode.infrastructureSta, expectedDeviceId: _newDevice.id, cancelToken: CancelToken());
    cache.release.complete();
    await rejected;
    await next;
    expect((await repository.savedDevice())!.baseUri, _newDevice.baseUri);
  });

  test('shared secure-store queue preserves the newer credential after a delayed older write', () async {
    final delegate = _DelayedCredentials();
    final store = SerializedSecureSessionStore(delegate);
    final old = store.write(_credential(_oldDevice.baseUri));
    await until(() => delegate.started);
    final next = store.write(_credential(_newDevice.baseUri));
    delegate.release.complete();
    await Future.wait([old, next]);
    expect((await store.read(_oldDevice.id))!.baseUri, _newDevice.baseUri);
  });
}

final _oldDevice = DeviceConnection(id: 'bbx-82f41c9e7a3d4b68a1501e21e536c649', name: 'box', baseUri: Uri.parse('http://192.0.2.10:8080'), networkMode: NetworkMode.infrastructureSta);
final _newDevice = _oldDevice.copyWith(baseUri: Uri.parse('http://192.0.2.20:8080'));
DeviceStatus _status(DeviceConnection device) => DeviceStatus(connection: device, card: const CardStatus(inserted: true, readable: true));
SessionCredential _credential(Uri uri) => SessionCredential(deviceId: _oldDevice.id, baseUri: uri, accessToken: 'test-token', expiresAt: DateTime.now().add(const Duration(hours: 1)), apiVersion: 'v1', clientId: 'test-client');

class _Api implements ConnectionApi {
  _Api(this.read);
  final Future<DeviceStatus> Function(Uri, String?, CancelToken?) read;
  @override
  Future<DeviceStatus> handshake(Uri baseUri, NetworkMode networkMode, {CancelToken? cancelToken, String? expectedDeviceId}) => read(baseUri, expectedDeviceId, cancelToken);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _DelayedCache extends MemoryHandoffStorage {
  final release = Completer<void>();
  bool started = false;
  @override
  Future<void> write(String key, Object? value) async {
    if (key == CacheSchemaMigrator.activeDeviceKey && !started) {
      started = true;
      await release.future;
    }
    await super.write(key, value);
  }
}

class _DelayedCredentials extends MemorySecureSessionStore {
  final release = Completer<void>();
  bool started = false;
  @override
  Future<void> write(SessionCredential credential) async {
    if (!started) {
      started = true;
      await release.future;
    }
    await super.write(credential);
  }
}

class _SlowEvents extends EventClient {
  final ready = Completer<void>();
  int connects = 0, disconnects = 0;
  var phase = EventConnectionState.disconnected;
  Completer<void>? nextDisconnect;
  @override
  EventConnectionState get currentState => phase;
  @override
  Future<void> connect(Uri uri, {required String accessToken, String apiVersion = 'v1'}) async {
    connects++;
    phase = EventConnectionState.connecting;
    await ready.future;
    phase = EventConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    final pending = nextDisconnect;
    nextDisconnect = null;
    phase = EventConnectionState.disconnected;
    await pending?.future;
  }
}

class _AuthApi extends ApiClient {
  final failures = StreamController<int>.broadcast();
  @override
  Stream<int> get authenticationFailures => failures.stream;
  @override
  Future<void> dispose() async {
    await failures.close();
    await super.dispose();
  }
}
