import 'dart:convert';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/pairing_preflight_codec.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = PairingPreflightCodec();
  const prepareId = '550e8400-e29b-41d4-a716-446655440000';
  const confirmId = '550e8400-e29b-41d4-a716-446655440001';
  const clientId = 'a870bcb1-d423-4d66-96f7-f809ce786543';
  const deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
  const fakeToken = 'FAKE_PREFLIGHT_TEST_TOKEN_ONLY';
  final now = DateTime.utc(2026, 10, 20);

  PrepareSystemPairingRequest prepare() => PrepareSystemPairingRequest(requestId: prepareId, clientId: clientId, phoneBondState: NativeBondState.notBonded);
  Uint8List bytes(Object? json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));
  Map<String, dynamic> prepared({bool reset = false}) => {
    'type': 'pairing_preflight_result',
    'request_id': prepareId,
    'ok': true,
    'payload': <String, dynamic>{
      'action': reset ? 'reset_required' : 'none',
      'board_bond_before': {'paired': reset, 'bonded': reset},
      if (reset) ...{'reset_token': fakeToken, 'expires_in_ms': 15000},
    },
  };
  PairingPreflightResponse decode(Map<String, dynamic> json, {PairingPreflightRequest? request}) => codec.decodeResponse(bytes(json), request: request ?? prepare(), expectedDeviceId: deviceId, receivedAt: now);
  PairingPreflightResetRequired challenge() => decode(prepared(reset: true)) as PairingPreflightResetRequired;
  Map<String, dynamic> scheduled() => {
    'type': 'pairing_reset_scheduled',
    'request_id': confirmId,
    'ok': true,
    'payload': {
      'action': 'remove_scheduled',
      'prepare_request_id': prepareId,
      'board_bond_before': {'paired': true, 'bonded': true},
      'disconnect_expected': true,
      'remove_after_ms': 750,
    },
  };

  test('native state and preparation stages have exact protocol names', () {
    for (final state in NativeBondState.values) {
      expect(NativeBondState.fromPlatform(state.platformValue), state);
    }
    expect(NativeBondState.fromPlatform('not_bonded'), NativeBondState.notBonded);
    expect(NativeBondState.fromPlatform('bonding'), NativeBondState.bonding);
    expect(NativeBondState.fromPlatform('bonded'), NativeBondState.bonded);
    expect(() => NativeBondState.fromPlatform('unknown'), throwsA(isA<ProvisioningProtocolException>()));
    expect(PairingPreflightStage.values.map((stage) => stage.diagnosticValue), [
      'PAIRING_PREFLIGHT_PENDING',
      'STALE_BOND_RESET_CONFIRMING',
      'STALE_BOND_RESET_PENDING',
      'WAITING_FOR_FRESH_ADVERTISEMENT',
      'FRESH_GATT_RECONNECTING',
    ]);
  });

  test('prepare is restricted to native NONE and exact non-business payload', () {
    expect(jsonDecode(utf8.decode(codec.encodeRequest(prepare()))), {
      'protocol_version': '1.0-rc4',
      'type': 'prepare_system_pairing',
      'request_id': prepareId,
      'client_id': clientId,
      'payload': {'phone_bond_state': 'not_bonded'},
    });
    for (final state in [NativeBondState.bonding, NativeBondState.bonded]) {
      expect(() => PrepareSystemPairingRequest(requestId: prepareId, clientId: clientId, phoneBondState: state), throwsA(isA<ProvisioningProtocolException>()));
    }
    expect(() => PrepareSystemPairingRequest(requestId: 'bad', clientId: clientId, phoneBondState: NativeBondState.notBonded), throwsA(isA<ProvisioningProtocolException>()));
    expect(() => PrepareSystemPairingRequest(requestId: prepareId, clientId: 'bad', phoneBondState: NativeBondState.notBonded), throwsA(isA<ProvisioningProtocolException>()));
  });

  test('documented minimal none result and scoped rc4 envelope are supported', () {
    final result = decode(prepared()) as PairingPreflightNone;
    expect(result.action, 'none');
    expect(result.boardBondBefore.hasOldBond, isFalse);
    final envelope = prepared()..addAll({'protocol_version': '1.0-rc4', 'device_id': deviceId});
    expect(decode(envelope), isA<PairingPreflightNone>());
    for (final extra in [
      {'protocol_version': '1.0-rc3'},
      {'protocol_version': null},
      {'device_id': 'bbx-00000000000000000000000000000000'},
      {'device_id': null},
      {'request_id': confirmId},
      {'extra': true},
      {'ok': 'true'},
      {'ok': null},
    ]) {
      expect(() => decode(prepared()..addAll(extra)), throwsA(isA<ProvisioningProtocolException>()));
    }
  });

  test('reset token moves once into a new confirm request bound to the same client', () {
    final result = challenge();
    expect(result.expiresIn, const Duration(seconds: 15));
    expect(result.toString(), isNot(contains(fakeToken)));
    expect(() => result.confirm(requestId: prepareId, now: now), throwsA(isA<ProvisioningProtocolException>()));
    final request = result.confirm(requestId: confirmId, now: now);
    final wire = codec.encodeRequest(request);
    expect(jsonDecode(utf8.decode(wire)), {
      'protocol_version': '1.0-rc4',
      'type': 'confirm_pairing_reset',
      'request_id': confirmId,
      'client_id': clientId,
      'payload': {'prepare_request_id': prepareId, 'reset_token': fakeToken},
    });
    expect(codec.encodeRequest(request), orderedEquals(wire), reason: 'same confirm can be replayed idempotently');
    expect(request.toString(), isNot(contains(fakeToken)));
    expect(() => result.confirm(requestId: confirmId, now: now), throwsA(isA<ProvisioningProtocolException>()));
    request.clearSecret();
    request.clearSecret();
    expect(() => codec.encodeRequest(request), throwsA(isA<ProvisioningProtocolException>()));
  });

  test('expired or cleared challenges cannot create confirmations', () {
    final expired = challenge();
    expect(() => expired.confirm(requestId: confirmId, now: now.add(const Duration(seconds: 15))), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.pairingPreflightExpired)));
    final cleared = challenge()..clearSecret();
    expect(() => cleared.confirm(requestId: confirmId, now: now), throwsA(isA<ProvisioningProtocolException>()));
  });

  test('remove scheduled must acknowledge this exact confirmation and prepare', () {
    final request = challenge().confirm(requestId: confirmId, now: now);
    final result = decode(scheduled(), request: request) as PairingResetScheduled;
    expect(result.action, 'remove_scheduled');
    expect(result.disconnectExpected, isTrue);
    expect(result.removeAfter, const Duration(milliseconds: 750));
    for (final patch in [
      {'prepare_request_id': confirmId},
      {'disconnect_expected': false},
      {'disconnect_expected': 1},
      {'action': 'none'},
      {'remove_after_ms': -1},
      {'remove_after_ms': '750'},
      {
        'board_bond_before': {'paired': false, 'bonded': false},
      },
    ]) {
      final json = scheduled();
      (json['payload'] as Map).addAll(patch);
      expect(() => decode(json, request: request), throwsA(isA<ProvisioningProtocolException>()));
    }
    expect(() => decode(scheduled()), throwsA(isA<ProvisioningProtocolException>()));
    expect(() => decode(prepared(), request: request), throwsA(isA<ProvisioningProtocolException>()));
  });

  test('inconsistent or malformed prepare payloads terminate instead of guessing', () {
    for (final patch in [
      {'action': 'remove_scheduled'},
      {'reset_token': fakeToken},
      {
        'board_bond_before': {'paired': true, 'bonded': false},
      },
      {
        'board_bond_before': {'paired': false},
      },
      {
        'board_bond_before': {'paired': 'false', 'bonded': false},
      },
      {
        'board_bond_before': {'paired': false, 'bonded': false, 'extra': true},
      },
    ]) {
      final json = prepared();
      (json['payload'] as Map).addAll(patch);
      expect(() => decode(json), throwsA(isA<ProvisioningProtocolException>()));
    }
    for (final patch in [
      {'reset_token': ''},
      {'reset_token': null},
      {'reset_token': 42},
      {'expires_in_ms': 0},
      {'expires_in_ms': -1},
      {'expires_in_ms': 15001},
      {'expires_in_ms': '15000'},
      {
        'board_bond_before': {'paired': false, 'bonded': false},
      },
    ]) {
      final json = prepared(reset: true);
      (json['payload'] as Map).addAll(patch);
      expect(() => decode(json), throwsA(isA<ProvisioningProtocolException>()));
    }
  });

  for (final code in ProvisioningErrorCode.values.where((code) => code.pairingPreflightDisposition != null)) {
    test('${code.wireValue} has stable parsing and cannot bypass terminal policy', () {
      expect(ProvisioningErrorCodeWireValue.parse(code.wireValue), code);
      final result =
          decode({
                'type': 'error',
                'request_id': prepareId,
                'ok': false,
                'error': {'code': code.wireValue, 'message': fakeToken, 'retryable': true, 'retry_after_ms': 100},
              })
              as PairingPreflightFailure;
      expect(result.error.code, code);
      expect(result.error.retryable, code.pairingPreflightDisposition == PairingPreflightErrorDisposition.boundedRetryAfterRelease);
      expect(result.error.diagnosticMessage, isNull);
      expect(result.toString(), isNot(contains(fakeToken)));
    });
  }

  test('unknown error codes and malformed messages cannot leak their sources', () {
    final malformed = [
      Uint8List.fromList([0xc3, 0x28]),
      Uint8List.fromList(utf8.encode('{"reset_token":"$fakeToken",')),
      bytes({'type': fakeToken, 'request_id': prepareId, 'ok': true, 'payload': {}}),
      bytes(prepared()..[fakeToken] = fakeToken),
      bytes({
        'type': 'error',
        'request_id': prepareId,
        'ok': false,
        'error': {'code': fakeToken, 'message': fakeToken, 'retryable': true, 'retry_after_ms': 0},
      }),
      bytes(<Object>[]),
      Uint8List(4097),
    ];
    for (final message in malformed) {
      try {
        codec.decodeResponse(message, request: prepare(), expectedDeviceId: deviceId, receivedAt: now);
        fail('Malformed response accepted');
      } on ProvisioningProtocolException catch (error) {
        expect(error.toString(), isNot(contains(fakeToken)));
        expect(error.source, isNull);
      }
    }
    expect(() => codec.decodeResponse(bytes(prepared()), request: prepare(), expectedDeviceId: 'bad', receivedAt: now), throwsA(isA<ProvisioningProtocolException>()));
  });

  test('preflight messages reuse the existing rc4 fragmentation codec', () {
    final message = codec.encodeRequest(challenge().confirm(requestId: confirmId, now: now));
    final frames = const BleFragmentCodec().fragment(message, messageId: 12, maximumFragmentBytes: 20);
    final assembler = BleFragmentReassembler();
    Uint8List? result;
    for (final frame in frames) {
      result = assembler.add(frame) ?? result;
    }
    expect(frames.length, greaterThan(1));
    expect(result, message);
  });

  test('oversized confirmation and unrelated error codes fail closed', () {
    final result = PairingPreflightResetRequired(
      requestId: prepareId,
      boardBondBefore: const BoardBondBefore(paired: true, bonded: true),
      clientId: clientId,
      resetToken: List.filled(4096, 'x').join(),
      expiresIn: const Duration(seconds: 15),
      receivedAt: now,
    );
    expect(() => codec.encodeRequest(result.confirm(requestId: confirmId, now: now)), throwsA(isA<ProvisioningProtocolException>()));
    expect(
      () => decode({
        'type': 'error',
        'request_id': prepareId,
        'ok': false,
        'error': {'code': 'AUTHORIZATION_FAILED', 'message': 'unrelated', 'retryable': true, 'retry_after_ms': 0},
      }),
      throwsA(isA<ProvisioningProtocolException>()),
    );
  });

  test('retry eligibility does not override a board refusal to retry', () {
    final result =
        decode({
              'type': 'error',
              'request_id': prepareId,
              'ok': false,
              'error': {'code': 'PAIRING_PREFLIGHT_BUSY', 'message': 'busy', 'retryable': false, 'retry_after_ms': 500},
            })
            as PairingPreflightFailure;
    expect(result.error.retryable, isFalse);
    expect(result.error.retryAfter, const Duration(milliseconds: 500));
    expect(ProvisioningErrorCode.bleGattOperationFailed.pairingPreflightDisposition, isNull);
  });
}
