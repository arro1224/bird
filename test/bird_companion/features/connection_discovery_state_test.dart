import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('初次加载后自动搜索，并将最近设备与新发现设备分区', () async {
    final repository = _DiscoveryRepository();
    final eventClient = EventClient();
    final coordinator = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(
      repository,
      _SilentConnectivityMonitor(),
      eventClient,
      coordinator,
    );
    final cubit = ConnectionCubit(repository, session);

    await cubit.load();

    expect(repository.discoverCalls, 1);
    expect(cubit.state.phase, ConnectionPhase.initial);
    expect(cubit.state.recentDevices, [repository.recent]);
    expect(cubit.state.discoveredDevices, [repository.discovered]);

    await cubit.close();
    await session.close();
    await eventClient.dispose();
    await coordinator.dispose();
  });
}

class _SilentConnectivityMonitor extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
}

class _DiscoveryRepository implements ConnectionRepository {
  final recent = DeviceConnection(
    id: 'recent-k7',
    name: '最近的拍鸟伴侣 K7',
    baseUri: Uri.parse('http://192.168.1.8:8080'),
    networkMode: NetworkMode.lan,
  );
  final discovered = DeviceConnection(
    id: 'new-k7',
    name: '拍鸟伴侣 K7',
    baseUri: Uri.parse('http://192.168.1.9:8080'),
    networkMode: NetworkMode.lan,
  );
  var discoverCalls = 0;

  @override
  Future<List<DeviceConnection>> discover() async {
    discoverCalls++;
    return [discovered, recent];
  }

  @override
  Future<List<DeviceConnection>> recentDevices() async => [recent];

  @override
  Future<DeviceStatus> connect(Uri baseUri, {required NetworkMode networkMode}) => throw UnimplementedError();

  @override
  Future<DeviceStatus> reconnect() => throw UnimplementedError();

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> forgetDevice() async {}
}
