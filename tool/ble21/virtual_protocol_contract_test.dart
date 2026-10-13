import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual Java virtual protocol messages satisfy strict production RC4 parsers', () {
    final file = File('build/ble21-protocol-samples.json');
    expect(file.existsSync(), isTrue, reason: 'Run :virtualBirdBox:testDebugUnitTest --rerun-tasks first.');
    final document = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(document['evidence_kind'], 'native_simulated_protocol_messages');
    final samples = document['samples'] as List;
    expect(samples, hasLength(16));
    const codec = BleMessageCodec();
    for (final sample in samples) {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(sample['message'])));
      if (sample['kind'] == 'device_info') {
        expect(codec.decodeDeviceInfo(bytes).deviceId, 'bbx-b1e11001b1e11001b1e11001b1e11001');
      } else {
        final response = codec.decodeResponse(bytes);
        if (response is BleSuccessResponse && response.event.payload is ProvisioningNetworkStatus) {
          final status = response.event.payload as ProvisioningNetworkStatus;
          expect(status.busy && status.operationState.terminal, isFalse);
        }
      }
    }
  });
}
