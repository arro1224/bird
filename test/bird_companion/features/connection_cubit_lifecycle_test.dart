import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连接页面关闭后完成中的请求不会继续 emit', () async {
    final repository = _DelayedConnectionRepository();
    final eventClient = EventClient();
    final refreshCoordinator = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(repository, _SilentConnectivityMonitor(), eventClient, refreshCoordinator);
    final cubit = ConnectionCubit(repository, session);

    final future = cubit.connect(Uri.parse('http://127.0.0.1:8080'), NetworkMode.manual);
    await cubit.close();
    repository.complete();

    await expectLater(future, completes);
    await session.close();
    await eventClient.dispose();
    await refreshCoordinator.dispose();
  });

  test('连接失败后的重试会重复最后一次连接而不是只刷新最近设备', () async {
    final repository = _RetryConnectionRepository();
    final eventClient = EventClient();
    final refreshCoordinator = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(repository, _SilentConnectivityMonitor(), eventClient, refreshCoordinator);
    final cubit = ConnectionCubit(repository, session);
    final uri = Uri.parse('http://127.0.0.1:8080');

    await cubit.connect(uri, NetworkMode.manual);
    expect(cubit.state.phase, ConnectionPhase.failure);

    await cubit.retry();

    expect(repository.connectCalls, 2);
    expect(cubit.state.phase, ConnectionPhase.connected);
    expect(cubit.state.status?.connection.baseUri, uri);
    await cubit.close();
    await session.close();
    await eventClient.dispose();
    await refreshCoordinator.dispose();
  });

  test('返回查找设备后会忽略迟到的连接成功结果', () async {
    final repository = _DelayedConnectionRepository();
    final eventClient = EventClient();
    final refreshCoordinator = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(repository, _SilentConnectivityMonitor(), eventClient, refreshCoordinator);
    final cubit = ConnectionCubit(repository, session);

    final future = cubit.connect(Uri.parse('http://127.0.0.1:8080'), NetworkMode.manual);
    expect(cubit.state.phase, ConnectionPhase.connecting);

    cubit.cancelConnection();
    repository.complete();
    await future;

    expect(cubit.state.phase, ConnectionPhase.initial);
    expect(session.state.isConnected, isFalse);
    await cubit.close();
    await session.close();
    await eventClient.dispose();
    await refreshCoordinator.dispose();
  });

  test('切换设备模式取消连接时保留原有已连接会话', () async {
    final repository = _DelayedConnectionRepository();
    final eventClient = EventClient();
    final refreshCoordinator = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(
      repository,
      _SilentConnectivityMonitor(),
      eventClient,
      refreshCoordinator,
    );
    await session.setConnectedFromStatus(_connectedStatus('old-device'));
    final oldDevice = session.state.device;
    final cubit = ConnectionCubit(
      repository,
      session,
      preserveExistingSession: true,
    );

    final future = cubit.connect(
      Uri.parse('http://192.168.4.2:8080'),
      NetworkMode.manual,
    );
    cubit.cancelConnection();
    repository.complete();
    await future;

    expect(session.state.isConnected, isTrue);
    expect(session.state.device, oldDevice);
    await cubit.close();
    await session.close();
    await eventClient.dispose();
    await refreshCoordinator.dispose();
  });

  test('切换设备模式连接失败时保留原有已连接会话', () async {
    final repository = _AlwaysFailConnectionRepository();
    final eventClient = EventClient();
    final refreshCoordinator = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(
      repository,
      _SilentConnectivityMonitor(),
      eventClient,
      refreshCoordinator,
    );
    await session.setConnectedFromStatus(_connectedStatus('old-device'));
    final oldDevice = session.state.device;
    final cubit = ConnectionCubit(
      repository,
      session,
      preserveExistingSession: true,
    );

    await cubit.connect(
      Uri.parse('http://192.168.4.2:8080'),
      NetworkMode.manual,
    );

    expect(cubit.state.phase, ConnectionPhase.failure);
    expect(session.state.isConnected, isTrue);
    expect(session.state.device, oldDevice);
    await cubit.close();
    await session.close();
    await eventClient.dispose();
    await refreshCoordinator.dispose();
  });
}

DeviceStatus _connectedStatus(String id) => DeviceStatus(
  connection: DeviceConnection(
    id: id,
    name: '拍鸟伴侣 K7',
    baseUri: Uri.parse('http://192.168.4.1:8080'),
    networkMode: NetworkMode.lan,
  ),
  card: const CardStatus(inserted: true, readable: true),
);

class _SilentConnectivityMonitor extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
}

class _DelayedConnectionRepository implements ConnectionRepository {
  final _completer = Completer<DeviceStatus>();

  void complete() => _completer.complete(
    DeviceStatus(
      connection: DeviceConnection(
        id: 'mock',
        name: '模拟盒子',
        baseUri: Uri.parse('http://127.0.0.1:8080'),
        networkMode: NetworkMode.manual,
      ),
      card: const CardStatus(inserted: true, readable: true),
    ),
  );

  @override
  Future<DeviceStatus> connect(Uri baseUri, {required NetworkMode networkMode}) => _completer.future;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceStatus> reconnect() => _completer.future;
}

class _RetryConnectionRepository implements ConnectionRepository {
  var connectCalls = 0;

  @override
  Future<DeviceStatus> connect(Uri baseUri, {required NetworkMode networkMode}) async {
    connectCalls++;
    if (connectCalls == 1) throw StateError('temporary failure');
    return DeviceStatus(
      connection: DeviceConnection(id: 'mock', name: '模拟盒子', baseUri: baseUri, networkMode: networkMode),
      card: const CardStatus(inserted: true, readable: true),
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceStatus> reconnect() => throw UnimplementedError();
}

class _AlwaysFailConnectionRepository implements ConnectionRepository {
  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
  }) => throw StateError('temporary failure');

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceStatus> reconnect() => throw UnimplementedError();
}
