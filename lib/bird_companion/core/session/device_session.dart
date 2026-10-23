import 'package:aves/bird_companion/core/models/device_models.dart';

enum DeviceSessionPhase { disconnected, connecting, connected, reconnecting, incompatible }

class DeviceSessionState {
  const DeviceSessionState({this.phase = DeviceSessionPhase.disconnected, this.device, this.lastUpdatedAt, this.message, this.attemptId, this.operationId, this.verificationStage});

  final DeviceSessionPhase phase;
  final DeviceConnection? device;
  final DateTime? lastUpdatedAt;
  final String? message;
  final String? attemptId;
  final String? operationId;
  final String? verificationStage;

  bool get isConnected => phase == DeviceSessionPhase.connected;
  bool get isVerifying => phase == DeviceSessionPhase.connecting || phase == DeviceSessionPhase.reconnecting;

  DeviceSessionState copyWith({
    DeviceSessionPhase? phase,
    DeviceConnection? device,
    DateTime? lastUpdatedAt,
    String? message,
    bool clearDevice = false,
    bool clearMessage = false,
    String? attemptId,
    String? operationId,
    String? verificationStage,
  }) => DeviceSessionState(
    phase: phase ?? this.phase,
    device: clearDevice ? null : device ?? this.device,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    message: clearMessage ? null : message ?? this.message,
    attemptId: attemptId ?? this.attemptId,
    operationId: operationId ?? this.operationId,
    verificationStage: verificationStage ?? this.verificationStage,
  );
}
