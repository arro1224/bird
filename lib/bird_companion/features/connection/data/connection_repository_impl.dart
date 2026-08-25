import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/cache_schema_migrator.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';

class ConnectionRepositoryImpl implements ConnectionRepository {
  ConnectionRepositoryImpl(this._api, this._cache, this._discoverySource);

  final ConnectionApi _api;
  final LocalCache _cache;
  final DeviceDiscoverySource _discoverySource;

  @override
  Future<List<DeviceConnection>> discover() async {
    final discovered = await _discoverySource.discover();
    return _unique([...discovered, ...await recentDevices()]);
  }

  @override
  Future<List<DeviceConnection>> recentDevices() async {
    final raw =
        _cache.read<List<dynamic>>(CacheSchemaMigrator.recentDevicesKey) ??
        _cache.read<List<dynamic>>(
          CacheSchemaMigrator.legacyRecentDevicesKey,
        ) ??
        const [];
    return raw.whereType<Map>().map((value) => DeviceConnection.fromJson(Map<String, dynamic>.from(value))).where((device) => device.baseUri.host.isNotEmpty).toList();
  }

  @override
  Future<DeviceConnection?> savedDevice() async {
    final raw = _cache.read<Map>(CacheSchemaMigrator.activeDeviceKey) ?? _cache.read<Map>(CacheSchemaMigrator.legacyActiveDeviceKey);
    if (raw == null) return null;
    final device = DeviceConnection.fromJson(Map<String, dynamic>.from(raw));
    return device.baseUri.host.isEmpty ? null : device;
  }

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) async {
    final status = await _api.handshake(baseUri, networkMode, cancelToken: cancelToken);
    await _save(status, cancelToken);
    return status;
  }

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) async {
    final status = await _api.pair(
      baseUri,
      networkMode,
      pairingCode: pairingCode,
      cancelToken: cancelToken,
    );
    await _save(status, cancelToken);
    return status;
  }

  Future<void> _save(
    DeviceStatus status,
    CancelToken? cancelToken,
  ) async {
    if (cancelToken?.isCancelled == true) {
      throw StateError('Connection cancelled before the device was saved.');
    }
    final device = status.connection;
    final recent = _unique([device, ...await recentDevices()]).take(10).toList();
    await _cache.write(
      CacheSchemaMigrator.recentDevicesKey,
      recent.map((item) => item.toJson()).toList(),
    );
    await _cache.write(
      CacheSchemaMigrator.activeDeviceKey,
      device.toJson(),
    );
  }

  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async {
    final device = await savedDevice();
    if (device == null) throw StateError('没有可重连的盒子设备。');
    List<DeviceConnection> discovered;
    try {
      discovered = await _discoverySource.discover();
    } catch (_) {
      // Discovery is only the preferred fresh-address source. A saved
      // address hint is still worth trying when mDNS is temporarily absent.
      discovered = const [];
    }
    final candidates = _unique([
      ...discovered.where((candidate) => candidate.id == device.id),
      device,
    ]);
    Object? lastError;
    for (final candidate in candidates) {
      if (cancelToken?.isCancelled == true) {
        throw StateError('Connection cancelled while resolving the device.');
      }
      try {
        final status = await _api.handshake(
          candidate.baseUri,
          candidate.networkMode,
          cancelToken: cancelToken,
        );
        if (status.connection.id != device.id) {
          continue;
        }
        await _save(status, cancelToken);
        return status;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    throw StateError('没有可用的盒子地址。');
  }

  Future<void> rememberDynamicAddress({
    required String deviceId,
    required Uri baseUri,
    required NetworkMode networkMode,
  }) async {
    final saved = await savedDevice();
    final recent = await recentDevices();
    DeviceConnection? previous = saved?.id == deviceId ? saved : null;
    if (previous == null) {
      for (final device in recent) {
        if (device.id == deviceId) {
          previous = device;
          break;
        }
      }
    }
    final updated = DeviceConnection(
      id: deviceId,
      name: previous?.name ?? '拍鸟盒子',
      baseUri: baseUri,
      networkMode: networkMode,
      apiVersion: previous?.apiVersion,
      signalStrength: previous?.signalStrength,
      isPaired: previous?.isPaired ?? true,
    );
    final nextRecent = _unique([
      updated,
      ...recent,
    ]).take(10).toList();
    await _cache.write(
      CacheSchemaMigrator.recentDevicesKey,
      nextRecent.map((item) => item.toJson()).toList(),
    );
    await _cache.write(
      CacheSchemaMigrator.activeDeviceKey,
      updated.toJson(),
    );
  }

  @override
  Future<void> disconnect() => _api.disconnect();

  @override
  Future<void> forgetDevice() async {
    final device = await savedDevice();
    if (device == null) {
      await _api.disconnect();
    } else {
      await _api.forget(device.id);
    }
    await _cache.remove(CacheSchemaMigrator.activeDeviceKey);
    await _cache.remove(CacheSchemaMigrator.recentDevicesKey);
    await _cache.remove(CacheSchemaMigrator.legacyActiveDeviceKey);
    await _cache.remove(CacheSchemaMigrator.legacyRecentDevicesKey);
  }

  List<DeviceConnection> _unique(List<DeviceConnection> devices) {
    final ids = <String>{};
    return devices.where((device) => ids.add(device.id.isEmpty ? device.baseUri.toString() : device.id)).toList();
  }
}
