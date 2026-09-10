import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/settings/presentation/adapters/device_overview_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceOverviewAdapter', () {
    test('maps every session phase without treating stale status as connected', () {
      final staleStatus = _status(name: '旧设备状态');

      final cases =
          <
            (
              DeviceSessionPhase,
              DeviceOverviewConnectionKind,
              String,
              DeviceOverviewPrimaryAction,
              bool,
            )
          >[
            (
              DeviceSessionPhase.disconnected,
              DeviceOverviewConnectionKind.disconnected,
              '未连接',
              DeviceOverviewPrimaryAction.connect,
              false,
            ),
            (
              DeviceSessionPhase.connecting,
              DeviceOverviewConnectionKind.connecting,
              '连接中',
              DeviceOverviewPrimaryAction.reconnect,
              true,
            ),
            (
              DeviceSessionPhase.reconnecting,
              DeviceOverviewConnectionKind.reconnecting,
              '连接中',
              DeviceOverviewPrimaryAction.reconnect,
              true,
            ),
            (
              DeviceSessionPhase.connected,
              DeviceOverviewConnectionKind.connected,
              '已连接',
              DeviceOverviewPrimaryAction.details,
              false,
            ),
            (
              DeviceSessionPhase.incompatible,
              DeviceOverviewConnectionKind.incompatible,
              '版本不兼容',
              DeviceOverviewPrimaryAction.reconnect,
              false,
            ),
          ];

      for (final (phase, kind, label, action, isBusy) in cases) {
        final overview = DeviceOverviewAdapter.map(
          session: DeviceSessionState(phase: phase),
          status: staleStatus,
        );

        expect(overview.connectionKind, kind, reason: phase.name);
        expect(overview.statusLabel, label, reason: phase.name);
        expect(overview.primaryAction, action, reason: phase.name);
        expect(overview.isBusy, isBusy, reason: phase.name);
        expect(overview.isConnecting, isBusy, reason: phase.name);
      }
    });

    test('connected overview prefers the session device name and rounds free bytes to GiB', () {
      final overview = DeviceOverviewAdapter.map(
        session: DeviceSessionState(
          phase: DeviceSessionPhase.connected,
          device: _connection(id: 'k7', name: '拍鸟伴侣 K7 Pro'),
        ),
        status: _status(
          id: 'k7',
          name: '状态中的旧名称',
          batteryPercent: 82,
          storageFreeBytes: 734000000000,
        ),
      );

      expect(overview.deviceName, '拍鸟伴侣 K7 Pro');
      expect(overview.metricsLabel, '82% · 684 GB 可用');
    });

    test('disconnected overview keeps the known session device and ignores stale status metrics', () {
      final overview = DeviceOverviewAdapter.map(
        session: DeviceSessionState(
          device: _connection(id: 'current', name: '当前盒子'),
        ),
        status: _status(
          id: 'stale',
          name: '旧盒子',
          batteryPercent: 82,
          storageFreeBytes: 734000000000,
        ),
      );

      expect(overview.deviceName, '当前盒子');
      expect(overview.metricsLabel, '-- · -- 可用');
    });

    test('disconnected overview does not adopt a stale status device name', () {
      final overview = DeviceOverviewAdapter.map(
        session: const DeviceSessionState(),
        status: _status(
          id: 'stale',
          name: '旧盒子',
          batteryPercent: 82,
          storageFreeBytes: 734000000000,
        ),
      );

      expect(overview.deviceName, '未连接拍鸟盒子');
      expect(overview.metricsLabel, '-- · -- 可用');
    });

    test('connected overview ignores status from a different device', () {
      final overview = DeviceOverviewAdapter.map(
        session: DeviceSessionState(
          phase: DeviceSessionPhase.connected,
          device: _connection(id: 'current', name: '当前盒子'),
        ),
        status: _status(
          id: 'stale',
          name: '旧盒子',
          batteryPercent: 82,
          storageFreeBytes: 734000000000,
        ),
      );

      expect(overview.deviceName, '当前盒子');
      expect(overview.metricsLabel, '-- · -- 可用');
    });

    test('connected overview falls back to the status when the session device is absent', () {
      final overview = DeviceOverviewAdapter.map(
        session: const DeviceSessionState(phase: DeviceSessionPhase.connected),
        status: _status(
          id: 'balcony',
          name: '阳台盒子',
          batteryPercent: 57,
          storageFreeBytes: 10737418240,
        ),
      );

      expect(overview.deviceName, '阳台盒子');
      expect(overview.metricsLabel, '57% · 10 GB 可用');
    });

    test('uses the disconnected placeholder when neither production model has a device', () {
      final overview = DeviceOverviewAdapter.map(
        session: const DeviceSessionState(),
        status: null,
      );

      expect(overview.deviceName, '未连接拍鸟盒子');
      expect(overview.metricsLabel, '-- · -- 可用');
    });
  });
}

DeviceConnection _connection({String? id, required String name}) => DeviceConnection(
  id: id ?? name,
  name: name,
  baseUri: Uri.parse('http://192.168.4.1:8080'),
  networkMode: NetworkMode.hotspot,
);

DeviceStatus _status({
  String? id,
  required String name,
  int? batteryPercent,
  int? storageFreeBytes,
}) => DeviceStatus(
  connection: _connection(id: id, name: name),
  card: const CardStatus(inserted: true, readable: true),
  batteryPercent: batteryPercent,
  storageFreeBytes: storageFreeBytes,
);
