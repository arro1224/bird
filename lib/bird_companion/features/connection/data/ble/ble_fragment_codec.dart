import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

final class BleFragment {
  BleFragment({required this.messageId, required this.fragmentIndex, required this.fragmentCount, required this.first, required this.last, required List<int> payload}) : payload = Uint8List.fromList(payload);

  final int messageId;
  final int fragmentIndex;
  final int fragmentCount;
  final bool first;
  final bool last;
  final Uint8List payload;
}

/// Encodes and validates the frozen rc4 12-byte little-endian BLE frame.
final class BleFragmentCodec {
  const BleFragmentCodec();

  List<Uint8List> fragment(Uint8List message, {required int messageId, required int maximumFragmentBytes}) {
    if (messageId < 0 || messageId > 0xFFFF) {
      _invalid('message_id is outside uint16');
    }
    if (message.length > BleProtocolConstants.maximumMessageBytes) {
      _invalid('message exceeds ${BleProtocolConstants.maximumMessageBytes} bytes');
    }
    if (maximumFragmentBytes <= BleProtocolConstants.fragmentHeaderLength) {
      _invalid('negotiated payload cannot contain the rc4 header and data');
    }

    final maximumPayloadBytes = maximumFragmentBytes - BleProtocolConstants.fragmentHeaderLength;
    final fragmentCount = message.isEmpty ? 1 : (message.length + maximumPayloadBytes - 1) ~/ maximumPayloadBytes;
    if (fragmentCount > BleProtocolConstants.maximumFragmentCount) {
      _invalid('message requires more than ${BleProtocolConstants.maximumFragmentCount} fragments');
    }

    return List<Uint8List>.generate(fragmentCount, (index) {
      final start = index * maximumPayloadBytes;
      final end = message.isEmpty ? 0 : (start + maximumPayloadBytes).clamp(0, message.length);
      final payload = message.sublist(start, end);
      final packet = Uint8List(BleProtocolConstants.fragmentHeaderLength + payload.length);
      final data = ByteData.view(packet.buffer);
      packet.setRange(0, 2, BleProtocolConstants.fragmentMagic);
      data.setUint8(2, BleProtocolConstants.fragmentProtocolVersion);
      data.setUint8(3, (index == 0 ? 0x01 : 0) | (index == fragmentCount - 1 ? 0x02 : 0));
      data.setUint16(4, messageId, Endian.little);
      data.setUint16(6, index, Endian.little);
      data.setUint16(8, fragmentCount, Endian.little);
      data.setUint16(10, payload.length, Endian.little);
      packet.setRange(BleProtocolConstants.fragmentHeaderLength, packet.length, payload);
      return packet;
    }, growable: false);
  }

  BleFragment decode(Uint8List packet) {
    if (packet.length < BleProtocolConstants.fragmentHeaderLength) {
      _invalid('fragment is shorter than the rc4 header');
    }
    if (packet[0] != BleProtocolConstants.fragmentMagic[0] || packet[1] != BleProtocolConstants.fragmentMagic[1]) {
      _invalid('fragment magic does not match');
    }
    final data = ByteData.view(packet.buffer, packet.offsetInBytes, packet.lengthInBytes);
    if (data.getUint8(2) != BleProtocolConstants.fragmentProtocolVersion) {
      _invalid('fragment protocol version is unsupported');
    }
    final flags = data.getUint8(3);
    if (flags & ~0x03 != 0) {
      _invalid('fragment contains unsupported flags');
    }
    final messageId = data.getUint16(4, Endian.little);
    final fragmentIndex = data.getUint16(6, Endian.little);
    final fragmentCount = data.getUint16(8, Endian.little);
    final payloadLength = data.getUint16(10, Endian.little);
    if (fragmentCount < 1 || fragmentCount > BleProtocolConstants.maximumFragmentCount) {
      _invalid('fragment_count is outside the rc4 range');
    }
    if (fragmentIndex >= fragmentCount) {
      _invalid('fragment_index is outside fragment_count');
    }
    if (payloadLength != packet.length - BleProtocolConstants.fragmentHeaderLength) {
      _invalid('payload length does not match the packet');
    }

    final first = flags & 0x01 != 0;
    final last = flags & 0x02 != 0;
    if (first != (fragmentIndex == 0) || last != (fragmentIndex == fragmentCount - 1)) {
      _invalid('first/last flags do not match the fragment index');
    }
    return BleFragment(
      messageId: messageId,
      fragmentIndex: fragmentIndex,
      fragmentCount: fragmentCount,
      first: first,
      last: last,
      payload: packet.sublist(BleProtocolConstants.fragmentHeaderLength),
    );
  }
}

/// Reassembles interleaved and out-of-order rc4 messages.
final class BleFragmentReassembler {
  BleFragmentReassembler({this.timeout = BleProtocolConstants.fragmentReassemblyTimeout});

  final Duration timeout;
  final BleFragmentCodec _codec = const BleFragmentCodec();
  final Map<int, _PendingMessage> _pending = {};

  int get pendingMessageCount => _pending.length;

  Uint8List? add(Uint8List packet, {DateTime? receivedAt}) {
    final now = receivedAt ?? DateTime.now();
    _rejectAndDiscardExpired(now);
    final fragment = _codec.decode(packet);
    final pending = _pending.putIfAbsent(fragment.messageId, () => _PendingMessage(fragment.fragmentCount, now));
    if (pending.fragmentCount != fragment.fragmentCount) {
      _pending.remove(fragment.messageId)?.clear();
      _invalid('fragment_count changed within a message');
    }

    final existing = pending.fragments[fragment.fragmentIndex];
    if (existing != null) {
      if (_bytesEqual(existing, fragment.payload)) return null;
      _pending.remove(fragment.messageId)?.clear();
      _invalid('duplicate fragment payload conflicts with the original');
    }

    pending.fragments[fragment.fragmentIndex] = Uint8List.fromList(fragment.payload);
    pending.totalBytes += fragment.payload.length;
    if (pending.totalBytes > BleProtocolConstants.maximumMessageBytes) {
      _pending.remove(fragment.messageId)?.clear();
      _invalid('reassembled message exceeds ${BleProtocolConstants.maximumMessageBytes} bytes');
    }
    if (pending.fragments.length != pending.fragmentCount) return null;

    final message = Uint8List(pending.totalBytes);
    var offset = 0;
    for (var index = 0; index < pending.fragmentCount; index++) {
      final payload = pending.fragments[index];
      if (payload == null) {
        _pending.remove(fragment.messageId)?.clear();
        _invalid('message completed with a missing fragment');
      }
      message.setRange(offset, offset + payload.length, payload);
      offset += payload.length;
    }
    _pending.remove(fragment.messageId)?.clear();
    return message;
  }

  void rejectExpired({DateTime? now}) => _rejectAndDiscardExpired(now ?? DateTime.now());

  void reset() {
    for (final message in _pending.values) {
      message.clear();
    }
    _pending.clear();
  }

  void _rejectAndDiscardExpired(DateTime now) {
    final expired = _pending.entries.where((entry) => now.difference(entry.value.startedAt) >= timeout).map((entry) => entry.key).toList(growable: false);
    if (expired.isEmpty) return;
    for (final id in expired) {
      _pending.remove(id)?.clear();
    }
    _invalid('fragment reassembly timed out');
  }
}

final class _PendingMessage {
  _PendingMessage(this.fragmentCount, this.startedAt);

  final int fragmentCount;
  final DateTime startedAt;
  final Map<int, Uint8List> fragments = {};
  int totalBytes = 0;

  void clear() {
    for (final payload in fragments.values) {
      payload.fillRange(0, payload.length, 0);
    }
    fragments.clear();
    totalBytes = 0;
  }
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Never _invalid(String diagnostic) {
  throw ProvisioningException(code: ProvisioningErrorCode.bleFragmentInvalid, retryable: false, diagnosticMessage: diagnostic);
}
