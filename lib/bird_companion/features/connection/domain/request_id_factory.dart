import 'dart:math';

abstract interface class RequestIdFactory {
  String create();
}

final class SecureRequestIdFactory implements RequestIdFactory {
  SecureRequestIdFactory({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String create() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256), growable: false);
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

bool isUuidV4(String value) => RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(value);
