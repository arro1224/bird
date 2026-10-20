import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

/// App-facing API. The MethodChannel adapter translates the e160043ef wire ABI
/// and checks ownership snapshots; missing methods never imply BOND_NONE.
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

final class PublicGattSnapshot {
  const PublicGattSnapshot({
    required this.connectionGeneration,
    required this.gattInstanceId,
    required this.characteristicUuids,
    this.hasCharacteristicInventory = true,
    this.connected = true,
    this.linkReady = true,
    this.preparing = false,
    this.inflightRequest,
  });
  final int connectionGeneration, gattInstanceId;
  final Set<String> characteristicUuids;
  final bool hasCharacteristicInventory, connected, linkReady, preparing;
  final String? inflightRequest;

  factory PublicGattSnapshot.fromPlatform(Map<Object?, Object?> value) {
    final uuids = value['characteristicUuids'];
    final connected = value['connected'], ready = value['linkReady'], preparing = value['preparing'];
    final generation = value['connectionGeneration'], instance = value['gattInstanceId'], inflight = value['inflightRequest'];
    if (connected is! bool ||
        ready is! bool ||
        preparing is! bool ||
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
      inflightRequest: inflight as String?,
      hasCharacteristicInventory: uuids != null,
      characteristicUuids: Set.unmodifiable((uuids as List? ?? const []).cast<String>().map((uuid) => uuid.toLowerCase())),
    );
  }
}
