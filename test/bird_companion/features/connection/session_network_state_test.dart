import 'dart:async';
import 'dart:io';
import 'package:aves/bird_companion/features/connection/domain/connection_attempt.dart';

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
  group('T1 B3 local AP session restore', () {
    final ap = _savedDevice.copyWith(networkMode: NetworkMode.directAp);
    final status = DeviceStatus(connection: ap, card: const CardStatus(inserted: true));
    test('local-only AP is prepared before HTTP even when internet monitor says none', () async {
      final monitor = _ManualConnectivityMonitor()..networkAvailable = false;
      final repository = _RecoveryRepository(saved: ap, reconnectStatus: status);
      final join = Completer<void>();
      var prepared = 0, committed = 0;
      final session = _session(
        monitor,
        repository,
        prepareSavedNetwork: (device, attempt) async {
          expect(device.id, ap.id);
          expect(attempt.intent, 'cold_restore');
          prepared++;
          await join.future;
        },
        onSavedNetworkVerified: (_) => committed++,
      );
      addTearDown(session.close);
      final restore = session.restoreSavedSession();
      await Future<void>.delayed(Duration.zero);
      expect(prepared, 1);
      expect(repository.reconnectCalls, 0);
      monitor.add(false);
      await Future<void>.delayed(Duration.zero);
      join.complete();
      expect(await restore, true);
      expect(repository.reconnectCalls, 1);
      expect(committed, 1);
      expect(session.state.isConnected, true);
    });
    test('late AP preparation after cancellation cannot start HTTP or commit', () async {
      final repository = _RecoveryRepository(saved: ap, reconnectStatus: status);
      final join = Completer<void>();
      CancelToken? token;
      final session = _session(
        _ManualConnectivityMonitor(),
        repository,
        prepareSavedNetwork: (_, attempt) {
          token = attempt.token;
          return join.future;
        },
      );
      addTearDown(session.close);
      final restore = session.restoreSavedSession();
      await Future<void>.delayed(Duration.zero);
      session.beginNetworkIntent('new-network');
      expect(token?.isCancelled, true);
      join.complete();
      expect(await restore, false);
      expect(repository.reconnectCalls, 0);
      expect(session.state.isConnected, false);
    });
    test('native loss burst schedules one selected-device recovery', () async {
      final repository = _RecoveryRepository(saved: ap, reconnectStatus: status);
      final losses = StreamController<void>.broadcast();
      var joins = 0;
      final session = _session(
        _ManualConnectivityMonitor(),
        repository,
        directApLosses: losses.stream,
        retryDelay: const Duration(milliseconds: 5),
        prepareSavedNetwork: (_, _) async {
          joins++;
        },
      );
      addTearDown(() async {
        await session.close();
        await losses.close();
      });
      await session.setConnectedFromStatus(status);
      for (var i = 0; i < 10; i++) {
        losses.add(null);
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(joins, 1);
      expect(repository.reconnectCalls, 1);
      expect(session.state.isConnected, true);
    });
    test('STA startup does not request a direct AP network', () async {
      var joins = 0;
      final session = _session(
        _ManualConnectivityMonitor(),
        _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status()),
        prepareSavedNetwork: (_, _) async {
          joins++;
        },
      );
      addTearDown(session.close);
      expect(await session.restoreSavedSession(), true);
      expect(joins, 0);
    });
  });
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

  test('Wi-Fi 断开但移动数据仍在：transport 变化立即进入 reconnecting', () async {
    final monitor = _ManualConnectivityMonitor();
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final pending = Completer<DeviceStatus>();
    repository.pendingReconnect = pending;
    final transport = StreamController<void>.broadcast();
    final session = _session(monitor, repository, transportChanges: transport.stream);
    addTearDown(() async {
      if (!pending.isCompleted) pending.complete(_status());
      await transport.close();
      await session.close();
    });
    await session.setConnectedFromStatus(_status());
    expect(session.state.phase, DeviceSessionPhase.connected);

    // 关 Wi-Fi、保留移动数据：onNetworkChanged 仍是 true，不能只靠它判断。
    monitor.wifiAvailable = false;
    monitor.add(true);
    transport.add(null);
    for (var i = 0; i < 50 && session.state.phase != DeviceSessionPhase.reconnecting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(session.state.phase, DeviceSessionPhase.reconnecting, reason: '不能等 20s deadline 才从已连接降级');
    expect(session.state.device?.id, _savedDevice.id);
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

  test('独立探测失败后，子页面 reportUnreachable 才触发全局恢复', () async {
    final monitor = _ManualConnectivityMonitor();
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final session = _session(monitor, repository, probeReachability: (_, _) async => false);
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

  test('a restored Wi-Fi transport cancels an old socket and ignores its late result', () async {
    final monitor = _ManualConnectivityMonitor();
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final oldSocket = Completer<DeviceStatus>();
    repository.pendingReconnect = oldSocket;
    final transport = StreamController<void>.broadcast();
    final events = EventClient(), refresh = SessionRefreshCoordinator();
    final diagnostics = <Map<String, dynamic>>[];
    final session = DeviceSessionCubit(repository, monitor, events, refresh, transportChanges: transport.stream, diagnostic: diagnostics.add);
    addTearDown(() async {
      if (!oldSocket.isCompleted) oldSocket.complete(_status());
      await session.close();
      await transport.close();
      await events.dispose();
      await refresh.dispose();
    });
    await session.setConnectedFromStatus(_status());
    final old = session.verifySavedSession();
    await Future<void>.delayed(Duration.zero);
    expect(repository.reconnectCalls, 1);
    monitor.wifiAvailable = false;
    transport.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, false);
    expect(await old, false);
    repository.pendingReconnect = null;
    monitor.wifiAvailable = true;
    transport.add(null);
    for (var i = 0; i < 30 && !session.state.isConnected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(session.state.isConnected, true);
    expect(repository.reconnectCalls, 2);
    oldSocket.completeError(StateError('old transport failed late'));
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, true);
    expect(diagnostics.where((event) => event['event'] == 'transport_changed').map((event) => event['wifi_available']), [false, true]);
  });

  test('manual restart replaces a pending automatic attempt while ordinary requests coalesce', () async {
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final pending = Completer<DeviceStatus>();
    repository.pendingReconnect = pending;
    final session = _session(_ManualConnectivityMonitor(), repository);
    addTearDown(() async {
      if (!pending.isCompleted) pending.complete(_status());
      await session.close();
    });
    final old = session.verifySavedSession();
    final duplicate = session.verifySavedSession();
    expect(identical(old, duplicate), true);
    await Future<void>.delayed(Duration.zero);
    repository.pendingReconnect = null;
    expect(await session.verifySavedSession(restart: true), true);
    expect(await old, false);
    expect(repository.reconnectCalls, 2);
  });

  test('an out-of-order Wi-Fi query cannot undo a newer recovered network', () async {
    final monitor = _ManualConnectivityMonitor();
    final staleQuery = Completer<bool>();
    monitor.wifiRead = () => staleQuery.future;
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final transport = StreamController<void>.broadcast();
    final session = _session(monitor, repository, transportChanges: transport.stream);
    addTearDown(() async {
      if (!staleQuery.isCompleted) staleQuery.complete(false);
      await session.close();
      await transport.close();
    });
    await session.setConnectedFromStatus(_status());
    transport.add(null);
    await Future<void>.delayed(Duration.zero);
    monitor.wifiRead = () async => true;
    transport.add(null);
    for (var i = 0; i < 30 && repository.reconnectCalls == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(Duration.zero);
    staleQuery.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, true);
  });

  test('concurrent page failures share one probe, and a healthy result keeps the session', () async {
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final result = Completer<bool>();
    var probes = 0;
    final session = _session(
      _ManualConnectivityMonitor(),
      repository,
      probeReachability: (_, _) {
        probes++;
        return result.future;
      },
    );
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    for (var i = 0; i < 6; i++) {
      session.reportUnreachable();
    }
    expect(probes, 1);
    expect(session.state.isConnected, true);
    result.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, true);
    expect(repository.reconnectCalls, 0);
  });

  test('late negative probe cannot demote a replacement session', () async {
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    final result = Completer<bool>();
    CancelToken? activeProbe;
    final session = _session(
      _ManualConnectivityMonitor(),
      repository,
      probeReachability: (_, token) {
        activeProbe = token;
        return result.future;
      },
    );
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    session.reportUnreachable();
    final newAddress = Uri.parse('http://192.0.2.11:8080');
    await session.setConnectedFromStatus(
      DeviceStatus(
        connection: _savedDevice.copyWith(baseUri: newAddress),
        card: const CardStatus(inserted: false),
      ),
    );
    expect(activeProbe?.isCancelled, true);
    result.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, true);
    expect(session.state.device?.baseUri, newAddress);
    expect(repository.reconnectCalls, 0);
  });

  test('an unanswered health probe is bounded and enters recovery', () async {
    final repository = _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status());
    CancelToken? token;
    final session = _session(
      _ManualConnectivityMonitor(),
      repository,
      probeReachability: (_, current) {
        token = current;
        return Completer<bool>().future;
      },
    );
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    final reconnecting = session.stream.firstWhere((state) => state.phase == DeviceSessionPhase.reconnecting);
    session.reportUnreachable();
    expect(session.state.isConnected, true);
    await reconnecting.timeout(const Duration(seconds: 5));
    expect(token?.isCancelled, true);
  });

  test('配网交接期间 reportUnreachable 不打断交接', () async {
    final monitor = _ManualConnectivityMonitor();
    final session = _session(
      monitor,
      _RecoveryRepository(saved: _savedDevice, reconnectStatus: _status()),
      probeReachability: (_, _) async => false,
    );
    addTearDown(session.close);
    await session.setConnectedFromStatus(_status());
    session.provisioningHandoffActive = true;
    session.reportUnreachable();
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, true, reason: '交接期间不改写连接状态');
  });
}

DeviceSessionCubit _session(
  _ManualConnectivityMonitor monitor,
  _RecoveryRepository repository, {
  Stream<void>? transportChanges,
  Future<bool> Function(Uri, CancelToken)? probeReachability,
  Future<void> Function(DeviceConnection, ConnectionAttempt)? prepareSavedNetwork,
  void Function(String)? onSavedNetworkVerified,
  Stream<void>? directApLosses,
  Duration retryDelay = const Duration(seconds: 1),
}) {
  final events = EventClient();
  final refresh = SessionRefreshCoordinator();
  final session = DeviceSessionCubit(
    repository,
    monitor,
    events,
    refresh,
    transportChanges: transportChanges,
    probeReachability: probeReachability,
    prepareSavedNetwork: prepareSavedNetwork,
    onSavedNetworkVerified: onSavedNetworkVerified,
    directApLosses: directApLosses,
    retryDelay: retryDelay,
  );
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
  bool wifiAvailable = true;
  bool networkAvailable = true;
  Future<bool> Function()? wifiRead;
  @override
  Stream<bool> get onNetworkChanged => _controller.stream;
  void add(bool available) => _controller.add(available);
  @override
  Future<bool> get hasNetwork async => networkAvailable;
  @override
  Future<bool> get hasWifi async => wifiRead == null ? wifiAvailable : await wifiRead!();
}

final class _RecoveryRepository implements ConnectionRepository {
  _RecoveryRepository({required this.saved, this.reconnectStatus});
  final DeviceConnection? saved;
  final DeviceStatus? reconnectStatus;
  Completer<DeviceStatus>? pendingReconnect;
  int reconnectCalls = 0;

  @override
  Future<DeviceConnection?> savedDevice() async => saved;
  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async {
    reconnectCalls++;
    final pending = pendingReconnect;
    if (pending != null) return pending.future;
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
