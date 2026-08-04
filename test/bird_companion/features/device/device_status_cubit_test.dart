import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a transient status refresh failure keeps an active device session', () async {
    final status = _status();
    final events = EventClient();
    final refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(
      _ConnectionRepository(status),
      _OnlineConnectivityMonitor(),
      events,
      refresh,
    );
    final cubit = DeviceStatusCubit(_FailingDeviceRepository(), session);
    addTearDown(() async {
      await cubit.close();
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });

    await session.connected(
      DeviceSessionState(
        phase: DeviceSessionPhase.connected,
        device: status.connection,
      ),
    );
    await cubit.load();

    expect(session.state.isConnected, isTrue);
    expect(session.state.device, status.connection);
    expect(cubit.state.phase, DeviceStatusPhase.failure);
  });
}

class _OnlineConnectivityMonitor extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();

  @override
  Future<bool> get hasNetwork async => true;
}

class _ConnectionRepository implements ConnectionRepository {
  const _ConnectionRepository(this.status);

  final DeviceStatus status;

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) async => status;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<void> forgetDevice() async {}

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async => status;

  @override
  Future<DeviceConnection?> savedDevice() async => status.connection;

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) async => status;
}

class _FailingDeviceRepository implements DeviceRepository {
  @override
  Future<void> controlJob({
    required String jobId,
    required String action,
    required int version,
  }) async {}

  @override
  Future<DeviceStatus> fetchStatus() => Future<DeviceStatus>.error(
    StateError('temporary status timeout'),
  );

  @override
  Stream<DeviceStatus> watchStatus() => const Stream.empty();
}

DeviceStatus _status() => DeviceStatus(
  connection: DeviceConnection(
    id: 'device-a',
    name: 'K7',
    baseUri: Uri.parse('http://192.168.4.1:8080'),
    networkMode: NetworkMode.hotspot,
  ),
  card: const CardStatus(inserted: true, readable: true),
);
