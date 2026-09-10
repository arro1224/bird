import 'dart:convert';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = BleFragmentCodec();

  test('encodes the frozen 12-byte little-endian header', () {
    final packets = codec.fragment(Uint8List.fromList(utf8.encode('123456789')), messageId: 0x1234, maximumFragmentBytes: 20);

    expect(packets, hasLength(2));
    expect(packets.first.sublist(0, 12), [0x42, 0x42, 1, 1, 0x34, 0x12, 0, 0, 2, 0, 8, 0]);
    expect(packets.last.sublist(0, 12), [0x42, 0x42, 1, 2, 0x34, 0x12, 1, 0, 2, 0, 1, 0]);
  });

  test('reassembles out-of-order fragments and ignores identical duplicates', () {
    final message = Uint8List.fromList(List<int>.generate(97, (index) => index));
    final packets = codec.fragment(message, messageId: 7, maximumFragmentBytes: 28);
    final reassembler = BleFragmentReassembler();

    expect(reassembler.add(packets[2]), isNull);
    expect(reassembler.add(packets[0]), isNull);
    expect(reassembler.add(Uint8List.fromList(packets[0])), isNull);
    Uint8List? result;
    for (final packet in [packets[4], packets[1], packets[3], ...packets.skip(5)]) {
      result = reassembler.add(packet) ?? result;
    }

    expect(result, message);
    expect(reassembler.pendingMessageCount, 0);
  });

  test('splits two concatenated rc4 frames returned by one characteristic read', () {
    final message = Uint8List.fromList(List<int>.filled(622, 7));
    final frames = codec.fragment(message, messageId: 82, maximumFragmentBytes: 412);
    final concatenated = Uint8List.fromList(<int>[...frames[0], ...frames[1]]);

    expect(frames, hasLength(2));
    expect(frames[0], hasLength(412));
    expect(frames[1], hasLength(234));

    final split = codec.splitPackets(concatenated);
    expect(split, hasLength(2));
    expect(split[0], frames[0]);
    expect(split[1], frames[1]);

    final reassembler = BleFragmentReassembler();
    expect(reassembler.add(split[0]), isNull);
    expect(reassembler.add(split[1]), message);
  });

  test('rejects an incomplete concatenated frame', () {
    final frame = codec.fragment(Uint8List.fromList([1, 2, 3]), messageId: 1, maximumFragmentBytes: 20).single;

    expect(() => codec.splitPackets(Uint8List.fromList(frame.sublist(0, frame.length - 1))), throwsA(_fragmentError));
  });

  test('rejects conflicting duplicates, invalid indexes and inconsistent flags', () {
    final packets = codec.fragment(Uint8List.fromList(List<int>.filled(20, 1)), messageId: 9, maximumFragmentBytes: 20);
    final conflicting = Uint8List.fromList(packets.first)..[12] = 2;
    final invalidIndex = Uint8List.fromList(packets.first)..[6] = 9;
    final invalidFlags = Uint8List.fromList(packets.first)..[3] = 0;

    final reassembler = BleFragmentReassembler();
    expect(reassembler.add(packets.first), isNull);
    expect(() => reassembler.add(conflicting), throwsA(_fragmentError));
    expect(() => codec.decode(invalidIndex), throwsA(_fragmentError));
    expect(() => codec.decode(invalidFlags), throwsA(_fragmentError));
  });

  test('rejects timed out, oversized and over-fragmented messages', () {
    final startedAt = DateTime.utc(2026, 8, 23);
    final packets = codec.fragment(Uint8List.fromList(List<int>.filled(20, 1)), messageId: 10, maximumFragmentBytes: 20);
    final reassembler = BleFragmentReassembler();
    expect(reassembler.add(packets.first, receivedAt: startedAt), isNull);
    expect(() => reassembler.rejectExpired(now: startedAt.add(BleProtocolConstants.fragmentReassemblyTimeout)), throwsA(_fragmentError));

    expect(
      () => codec.fragment(Uint8List(BleProtocolConstants.maximumMessageBytes + 1), messageId: 1, maximumFragmentBytes: 20),
      throwsA(_fragmentError),
    );
    expect(
      () => codec.fragment(Uint8List(BleProtocolConstants.maximumMessageBytes), messageId: 1, maximumFragmentBytes: 13),
      throwsA(_fragmentError),
    );
  });

  test('accepts the exact 4096-byte and 256-fragment limits', () {
    final packets = codec.fragment(Uint8List(BleProtocolConstants.maximumMessageBytes), messageId: 0xFFFF, maximumFragmentBytes: 28);

    expect(packets, hasLength(BleProtocolConstants.maximumFragmentCount));
    final reassembler = BleFragmentReassembler();
    Uint8List? result;
    for (final packet in packets.reversed) {
      result = reassembler.add(packet) ?? result;
    }
    expect(result, hasLength(BleProtocolConstants.maximumMessageBytes));
  });
}

final _fragmentError = isA<ProvisioningException>().having((error) => error.code, 'code', ProvisioningErrorCode.bleFragmentInvalid);
