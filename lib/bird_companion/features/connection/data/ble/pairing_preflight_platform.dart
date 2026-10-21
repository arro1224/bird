import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

/// App-facing API for the R1/R2 ownership-checked native ABI.
/// Missing methods never imply BOND_NONE.
abstract interface class BirdBoxPairingPreflightPlatform {
  Future<NativeBondSnapshot> getNativeBondState(int connectionGeneration, {required String platformDeviceId});
  Future<PublicGattSnapshot> getGattOwnershipState(int connectionGeneration);
  Future<void> writePairingPreflight({required String requestId, required int connectionGeneration, required int gattInstanceId, required Uint8List fragmentBytes});
  Future<void> prepareControlledReconnect({required String requestId, required int connectionGeneration, required int gattInstanceId, required String reason});
}

final class NativeBondSnapshot {
  const NativeBondSnapshot({required this.state, required this.connectionGeneration, required this.gattInstanceId});
  final NativeBondState state;
  final int connectionGeneration, gattInstanceId;
}

/// Engine-scoped release evidence; absence of this additive field is not success.
final class NativeGattReleaseSnapshot {
  const NativeGattReleaseSnapshot({required this.connectionGeneration, required this.gattInstanceId, required this.state, required this.resultCode, required this.disconnectObserved, required this.closeCompleted, this.traceId});
  final int connectionGeneration, gattInstanceId;
  final String state, resultCode;
  final bool disconnectObserved, closeCompleted;
  final String? traceId;

  bool confirms((int, int) owner, {String? traceId}) => connectionGeneration == owner.$1 && gattInstanceId == owner.$2 && (traceId == null || this.traceId == traceId) && state == 'confirmed';

  factory NativeGattReleaseSnapshot.fromPlatform(Object value) {
    if (value is! Map) throw const ProvisioningProtocolException('gatt_ownership', 'invalid native release record');
    final generation = value['connectionGeneration'], instance = value['gattInstanceId'];
    final state = value['state'], result = value['resultCode'], trace = value['traceId'];
    final disconnected = value['disconnectObserved'], closed = value['closeCompleted'];
    if (generation is! int ||
        generation <= 0 ||
        instance is! int ||
        instance <= 0 ||
        trace != null && (trace is! String || trace.isEmpty) ||
        disconnected is! bool ||
        closed is! bool ||
        !const {'disconnecting', 'confirmed', 'unconfirmed'}.contains(state) ||
        state == 'confirmed' && (result != 'retired_gatt_disconnected' || !disconnected || !closed) ||
        state == 'disconnecting' && (result != 'awaiting_disconnect' || disconnected || closed) ||
        state == 'unconfirmed' && (!const {'disconnect_callback_missing', 'close_failed', 'release_superseded'}.contains(result) || disconnected && closed)) {
      throw const ProvisioningProtocolException('gatt_ownership', 'invalid native release record');
    }
    return NativeGattReleaseSnapshot(connectionGeneration: generation, gattInstanceId: instance, state: state as String, resultCode: result as String, disconnectObserved: disconnected, closeCompleted: closed, traceId: trace as String?);
  }
}

final class PublicGattSnapshot {
  const PublicGattSnapshot({
    required this.connectionGeneration,
    required this.gattInstanceId,
    required this.characteristicUuids,
    this.hasCharacteristicInventory = true,
    this.connected = true,
    this.linkReady = true,
    this.preparing = false,
    this.retiring = false,
    this.inflightRequest,
    this.lastRelease,
  });
  final int connectionGeneration, gattInstanceId;
  final Set<String> characteristicUuids;
  final bool hasCharacteristicInventory, connected, linkReady, preparing, retiring;
  final String? inflightRequest;
  final NativeGattReleaseSnapshot? lastRelease;

  factory PublicGattSnapshot.fromPlatform(Map<Object?, Object?> value) {
    final uuids = value['characteristicUuids'];
    final connected = value['connected'], ready = value['linkReady'], preparing = value['preparing'];
    final generation = value['connectionGeneration'], instance = value['gattInstanceId'], inflight = value['inflightRequest'];
    final retiring = value.containsKey('retiring') ? value['retiring'] : false;
    if (connected is! bool ||
        ready is! bool ||
        preparing is! bool ||
        retiring is! bool ||
        retiring && connected ||
        generation is! int ||
        generation < 0 ||
        instance is! int ||
        instance < 0 ||
        !const {'absent', 'connected', 'discovering', 'discovered', 'ready'}.contains(value['discoveryState']) ||
        inflight != null && inflight is! String ||
        uuids != null && (uuids is! List || uuids.any((uuid) => uuid is! String)) ||
        connected && (generation == 0 || instance == 0) ||
        !connected && (ready || instance != 0 || value['discoveryState'] != 'absent')) {
      throw const ProvisioningProtocolException('gatt_ownership', 'invalid native ownership snapshot');
    }
    return PublicGattSnapshot(
      connectionGeneration: generation,
      gattInstanceId: instance,
      connected: connected,
      linkReady: ready,
      preparing: preparing,
      retiring: retiring,
      inflightRequest: inflight as String?,
      lastRelease: value['lastRelease'] == null ? null : NativeGattReleaseSnapshot.fromPlatform(value['lastRelease']!),
      hasCharacteristicInventory: uuids != null,
      characteristicUuids: Set.unmodifiable((uuids as List? ?? const []).cast<String>().map((uuid) => uuid.toLowerCase())),
    );
  }
}
