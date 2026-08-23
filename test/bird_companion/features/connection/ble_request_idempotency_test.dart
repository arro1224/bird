import 'dart:convert';

import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secure factory produces unique RFC 4122 UUID v4 request IDs', () {
    final factory = SecureRequestIdFactory();
    final identifiers = List<String>.generate(128, (_) => factory.create()).toSet();

    expect(identifiers, hasLength(128));
    expect(identifiers.every(isUuidV4), isTrue);
  });

  test('retrying the same request preserves its request ID and bytes', () {
    final requestId = SecureRequestIdFactory().create();
    final request = BleCommandRequest(
      type: BleCommandType.startDirectAp,
      requestId: requestId,
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
      payload: const {
        'authorization': {'type': 'pairing_session', 'value': 'REDACTED_TEST_ONLY'},
      },
    );
    const codec = BleMessageCodec();

    final firstAttempt = codec.encodeRequest(request);
    final retryAttempt = codec.encodeRequest(request);
    expect(retryAttempt, firstAttempt);
    expect((jsonDecode(utf8.decode(retryAttempt)) as Map<String, dynamic>)['request_id'], requestId);
  });
}
