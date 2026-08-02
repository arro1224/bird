import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_cubit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连接发现需要配对后，提交配对码进入已连接状态', () async {
    final repository = _PairingConnectionRepository();
    final events = EventClient();
    final refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(
      repository,
      _OnlineConnectivityMonitor(),
      events,
      refresh,
    );
    final cubit = ConnectionCubit(repository, session);
    addTearDown(() async {
      await cubit.close();
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });

    await cubit.connect(
      Uri.parse('http://192.168.4.1:8080'),
      NetworkMode.manual,
    );
    expect(cubit.state.phase, ConnectionPhase.pairing);
    expect(cubit.state.status?.connection.id, 'device-a');
    expect(session.state.isConnected, isFalse);

    await cubit.pair('2468');
    expect(repository.lastPairingCode, '2468');
    expect(cubit.state.phase, ConnectionPhase.connected);
    expect(session.state.isConnected, isTrue);
  });
}

class _OnlineConnectivityMonitor extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();

  @override
  Future<bool> get hasNetwork async => true;
}

class _PairingConnectionRepository implements ConnectionRepository {
  String? lastPairingCode;

  DeviceStatus get _unpaired => DeviceStatus(
    connection: DeviceConnection(
      id: 'device-a',
      name: '测试盒子',
      baseUri: Uri.parse('http://192.168.4.1:8080'),
      networkMode: NetworkMode.manual,
    ),
    card: const CardStatus(inserted: true, readable: true),
  );

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) async {
    throw PairingRequiredException(_unpaired);
  }

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) async {
    lastPairingCode = pairingCode;
    return DeviceStatus(
      connection: DeviceConnection(
        id: 'device-a',
        name: '测试盒子',
        baseUri: baseUri,
        networkMode: networkMode,
        isPaired: true,
      ),
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
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async => _unpaired;

  @override
  Future<DeviceConnection?> savedDevice() async => null;
}
