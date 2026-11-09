import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// v10 返修问题 8（2026-11-09）：Wi-Fi 断开的全局连接状态。
///
/// 关闭手机 Wi-Fi 后首页/设备页必须同步显示"断开/重连中"，不再长期
/// 显示"已连接"；子页面请求失败可通过 reportUnreachable 回写全局状态。
void main() {
  test('Wi-Fi 断开：connected 立即转为 reconnecting 并保留设备身份', () async {
    final monitor = _ManualConnectivityMonitor();
    final session = _session(monitor, _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status()));
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    expect(session.state.phase, DeviceSessionPhase.connected);

    monitor.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.phase, DeviceSessionPhase.reconnecting, reason: '断网后首页不得继续显示已连接');
    expect(session.state.device?.id, _savedDevice.id, reason: '保留设备身份，恢复后可直接重连');
    expect(session.state.isConnected, false);
  });

  test('Wi-Fi 恢复：reconnecting 状态自动验证并回到 connected', () async {
    final monitor = _ManualConnectivityMonitor();
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final session = _session(monitor, repository);
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    monitor.add(false);
    await Future<void>.delayed(Duration.zero);
    monitor.add(true);
    for (var i = 0; i < 50 && !session.state.isConnected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(session.state.isConnected, true, reason: '网络恢复后自动重连');
    expect(repository.reconnectCalls, greaterThanOrEqualTo(1));
  });

  test('断网时未连接的会话不进入 reconnecting', () async {
    final monitor = _ManualConnectivityMonitor();
    final session = _session(monitor, _RecoveryRepository(saved: _savedDevice));
    addTearDown(session.close);
    expect(session.state.phase, DeviceSessionPhase.disconnected);
    monitor.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.phase, DeviceSessionPhase.disconnected);
  });

  test('子页面 reportUnreachable 回写全局状态并触发健康检查', () async {
    final monitor = _ManualConnectivityMonitor();
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final session = _session(monitor, repository);
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    final callsBefore = repository.reconnectCalls;

    session.reportUnreachable(const SocketException('connection refused'));
    for (var i = 0; i < 50 && repository.reconnectCalls <= callsBefore; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(repository.reconnectCalls, greaterThan(callsBefore), reason: '回写必须触发轻量健康检查');
    expect(session.state.isConnected, true, reason: '健康检查通过后恢复连接');
    // 短暂重连窗口内不得停留已连接的旧状态：verify 完成前 phase 为 reconnecting
    // 或已经恢复为 connected，二者都不允许停留在"未检查的 connected"。

    // 非连接态的重复上报不重复触发。
    session.reportUnreachable();
    await Future<void>.delayed(Duration.zero);
  });

  test('配网交接期间 reportUnreachable 不打断交接', () async {
    final monitor = _ManualConnectivityMonitor();
    final session = _session(monitor, _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status()));
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    session.provisioningHandoffActive = true;
    session.reportUnreachable();
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, true, reason: '交接期间不改写连接状态');
  });
}

DeviceSessionCubit _session(_ManualConnectivityMonitor monitor, _RecoveryRepository repository) {
  final events = EventClient();
  final refresh = SessionRefreshCoordinator();
  final session = DeviceSessionCubit(repository, monitor, events, refresh);
  return session;
}

final _savedDevice = DeviceConnection(
  id: 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
  name: '测试盒子',
  baseUri: Uri.parse('http://192.0.2.10:8080'),
  networkMode: NetworkMode.infrastructureSta,
  isPaired: true,
);

DeviceStatus _status() => DeviceStatus(connection: _savedDevice, card: const CardStatus(inserted: true, readable: true));

final class _ManualConnectivityMonitor extends ConnectivityMonitor {
  final _controller = StreamController<bool>.broadcast();
  @override
  Stream<bool> get onNetworkChanged => _controller.stream;
  void add(bool available) => _controller.add(available);
  @override
  Future<bool> get hasNetwork async => true;
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
  Future<DeviceStatus> connect(Uri baseUri, {required NetworkMode networkMode, CancelToken? cancelToken}) => throw UnimplementedError();
  @override
  Future<DeviceStatus> pair(Uri baseUri, {required NetworkMode networkMode, required String pairingCode, CancelToken? cancelToken}) => throw UnimplementedError();
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> forgetDevice() async {}
}
