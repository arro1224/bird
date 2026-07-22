import 'package:aves/bird_companion/core/models/device_models.dart';

enum DeviceSessionPhase { disconnected, connecting, connected, reconnecting, incompatible }

class DeviceSessionState {
  const DeviceSessionState({this.phase = DeviceSessionPhase.disconnected, this.device, this.lastUpdatedAt, this.message});

  final DeviceSessionPhase phase;
  final DeviceConnection? device;
  final DateTime? lastUpdatedAt;
  final String? message;

  bool get isConnected => phase == DeviceSessionPhase.connected;

  DeviceSessionState copyWith({
    DeviceSessionPhase? phase,
    DeviceConnection? device,
    DateTime? lastUpdatedAt,
    String? message,
    bool clearDevice = false,
    bool clearMessage = false,
  }) => DeviceSessionState(
    phase: phase ?? this.phase,
    device: clearDevice ? null : device ?? this.device,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    message: clearMessage ? null : message ?? this.message,
  );
}
