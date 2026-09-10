import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';

enum DeviceOverviewConnectionKind { disconnected, connecting, reconnecting, connected, incompatible }

enum DeviceOverviewPrimaryAction { connect, reconnect, details }

class DeviceOverviewViewModel {
  const DeviceOverviewViewModel({
    required this.connectionKind,
    required this.deviceName,
    required this.statusLabel,
    required this.metricsLabel,
    required this.primaryAction,
  });

  final DeviceOverviewConnectionKind connectionKind;
  final String deviceName;
  final String statusLabel;
  final String metricsLabel;
  final DeviceOverviewPrimaryAction primaryAction;

  bool get isConnecting => connectionKind == DeviceOverviewConnectionKind.connecting || connectionKind == DeviceOverviewConnectionKind.reconnecting;

  bool get isBusy => isConnecting;
}

abstract final class DeviceOverviewAdapter {
  static DeviceOverviewViewModel map({
    required DeviceSessionState session,
    required DeviceStatus? status,
  }) {
    final connectionKind = switch (session.phase) {
      DeviceSessionPhase.disconnected => DeviceOverviewConnectionKind.disconnected,
      DeviceSessionPhase.connecting => DeviceOverviewConnectionKind.connecting,
      DeviceSessionPhase.connected => DeviceOverviewConnectionKind.connected,
      DeviceSessionPhase.reconnecting => DeviceOverviewConnectionKind.reconnecting,
      DeviceSessionPhase.incompatible => DeviceOverviewConnectionKind.incompatible,
    };
    final matchingStatus = _matchingStatus(session, status);
    final batteryText = matchingStatus?.batteryPercent == null ? '--' : '${matchingStatus!.batteryPercent}%';
    final storageFreeBytes = matchingStatus?.storageFreeBytes;
    final storageText = storageFreeBytes == null ? '--' : '${(storageFreeBytes / (1024 * 1024 * 1024)).round()} GB';

    return DeviceOverviewViewModel(
      connectionKind: connectionKind,
      deviceName: session.device?.name ?? matchingStatus?.connection.name ?? '未连接拍鸟盒子',
      statusLabel: switch (connectionKind) {
        DeviceOverviewConnectionKind.connected => '已连接',
        DeviceOverviewConnectionKind.connecting || DeviceOverviewConnectionKind.reconnecting => '连接中',
        DeviceOverviewConnectionKind.incompatible => '版本不兼容',
        DeviceOverviewConnectionKind.disconnected => '未连接',
      },
      metricsLabel: '$batteryText · $storageText 可用',
      primaryAction: connectionKind == DeviceOverviewConnectionKind.connected
          ? DeviceOverviewPrimaryAction.details
          : session.phase == DeviceSessionPhase.disconnected && session.device == null
          ? DeviceOverviewPrimaryAction.connect
          : DeviceOverviewPrimaryAction.reconnect,
    );
  }

  static DeviceStatus? _matchingStatus(DeviceSessionState session, DeviceStatus? status) {
    if (session.phase != DeviceSessionPhase.connected || status == null) return null;

    final sessionDevice = session.device;
    if (sessionDevice == null) return status;

    final statusDevice = status.connection;
    final idsAreAvailable = sessionDevice.id.isNotEmpty && statusDevice.id.isNotEmpty;
    final isSameDevice = idsAreAvailable ? sessionDevice.id == statusDevice.id : sessionDevice.baseUri == statusDevice.baseUri;
    return isSameDevice ? status : null;
  }
}
