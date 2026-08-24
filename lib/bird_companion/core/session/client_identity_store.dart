import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:flutter/services.dart';

abstract interface class ClientIdentityStore {
  Future<String> readOrCreate();
  Future<void> clear();
}

/// Stores the installation-scoped UUID through the Android Keystore bridge.
///
/// The identifier is generated independently from every device, address,
/// SSID and Bluetooth handle. Reinstalling the app creates a new identity.
final class AndroidKeystoreClientIdentityStore implements ClientIdentityStore {
  factory AndroidKeystoreClientIdentityStore({
    MethodChannel channel = const MethodChannel('bird_companion/client_identity'),
    RequestIdFactory? idFactory,
  }) => AndroidKeystoreClientIdentityStore._(
    channel,
    idFactory ?? SecureRequestIdFactory(),
  );

  AndroidKeystoreClientIdentityStore._(this._channel, this._idFactory);

  final MethodChannel _channel;
  final RequestIdFactory _idFactory;

  @override
  Future<String> readOrCreate() async {
    final stored = await _channel.invokeMethod<String>('read');
    if (stored != null && isUuidV4(stored)) return stored;
    final created = _idFactory.create();
    await _channel.invokeMethod<void>('write', {'clientId': created});
    return created;
  }

  @override
  Future<void> clear() => _channel.invokeMethod<void>('delete');
}

final class MemoryClientIdentityStore implements ClientIdentityStore {
  MemoryClientIdentityStore({String? initialValue, RequestIdFactory? idFactory}) : _value = initialValue, _idFactory = idFactory ?? SecureRequestIdFactory();

  final RequestIdFactory _idFactory;
  String? _value;

  @override
  Future<String> readOrCreate() async {
    final value = _value;
    if (value != null && isUuidV4(value)) return value;
    return _value = _idFactory.create();
  }

  @override
  Future<void> clear() async => _value = null;
}
