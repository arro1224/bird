abstract final class CacheSchemaMigrator {
  static const schemaVersionKey = 'bird_companion_cache_schema_version';
  static const currentSchemaVersion = 3;
  static const legacyPendingOperationsKey = 'pending_operations';
  static const pendingOperationsKey = 'pending_operations:v2';
  static const pendingBackupKey = 'migration_backup:v2:pending_operations';
  static const pendingQuarantineKey = 'quarantine:v2:pending_operations';
  static const legacyRecentDevicesKey = 'recent_devices';
  static const legacyActiveDeviceKey = 'active_device';
  static const recentDevicesKey = 'recent_devices:v3';
  static const activeDeviceKey = 'active_device:v3';
  static const recentDevicesBackupKey = 'migration_backup:v3:recent_devices';
  static const activeDeviceBackupKey = 'migration_backup:v3:active_device';

  /// Returns additive writes only. Existing legacy keys are never deleted or
  /// overwritten, so rolling back B2 can still read the v1 cache.
  static Map<String, Object?> writesFor(Map<dynamic, dynamic> source) {
    final version = (source[schemaVersionKey] as num?)?.toInt() ?? 0;
    if (version >= currentSchemaVersion) return const {};

    final writes = <String, Object?>{};
    final legacyPending = source[legacyPendingOperationsKey];
    if (legacyPending != null && !source.containsKey(pendingBackupKey)) {
      writes[pendingBackupKey] = legacyPending;
    }
    if (!source.containsKey(pendingOperationsKey)) {
      final valid = <Object?>[];
      final quarantine = <Object?>[];
      for (final value in legacyPending is List ? legacyPending : const []) {
        if (_validPendingOperation(value)) {
          valid.add(_normalizePendingOperation(value));
        } else {
          quarantine.add(value);
        }
      }
      writes[pendingOperationsKey] = valid;
      if (quarantine.isNotEmpty) {
        writes[pendingQuarantineKey] = quarantine;
      }
    }

    for (final entry in source.entries) {
      final key = entry.key.toString();
      if (_isLegacyAlbumViewKey(key)) {
        writes.putIfAbsent('quarantine:v1:$key', () => entry.value);
      }
    }
    _migrateDeviceIdentity(source, writes);
    writes[schemaVersionKey] = currentSchemaVersion;
    return writes;
  }

  static void _migrateDeviceIdentity(
    Map<dynamic, dynamic> source,
    Map<String, Object?> writes,
  ) {
    final legacyActive = source[legacyActiveDeviceKey];
    if (legacyActive is Map && !source.containsKey(activeDeviceKey)) {
      writes.putIfAbsent(activeDeviceBackupKey, () => legacyActive);
      writes[activeDeviceKey] = _normalizeDevice(legacyActive);
    }

    final legacyRecent = source[legacyRecentDevicesKey];
    if (legacyRecent is List && !source.containsKey(recentDevicesKey)) {
      writes.putIfAbsent(recentDevicesBackupKey, () => legacyRecent);
      writes[recentDevicesKey] = legacyRecent.whereType<Map>().map(_normalizeDevice).toList(growable: false);
    }
  }

  static Map<String, Object?> _normalizeDevice(Map<dynamic, dynamic> value) {
    final normalized = <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
    final addressHint = _firstNonEmpty([
      normalized['address_hint'],
      normalized['base_uri'],
      normalized['ip_address'],
    ]);
    normalized
      ..remove('base_uri')
      ..remove('ip_address')
      ..['network_mode'] = _canonicalNetworkMode(
        normalized['network_mode']?.toString(),
      );
    if (addressHint == null) {
      normalized.remove('address_hint');
    } else {
      normalized['address_hint'] = addressHint;
    }
    return normalized;
  }

  static String _canonicalNetworkMode(String? value) => switch (value) {
    'direct_ap' || 'hotspot' => 'direct_ap',
    'infrastructure_sta' || 'lan' || 'manual' || 'qr' => 'infrastructure_sta',
    _ => 'none',
  };

  static bool _isLegacyAlbumViewKey(String key) {
    if (!key.startsWith('album:view:')) return false;
    final suffix = key.substring('album:view:'.length);
    return suffix.isNotEmpty && !suffix.contains(':');
  }

  static bool _validPendingOperation(Object? value) {
    if (value is! Map) return false;
    final id = value['id']?.toString().trim() ?? '';
    final type = value['type']?.toString() ?? '';
    final payload = value['payload'];
    final createdAt = DateTime.tryParse(
      value['created_at']?.toString() ?? '',
    );
    return id.isNotEmpty &&
        const {
          'updateReview',
          'batchReview',
          'controlJob',
          'createCopyJob',
        }.contains(type) &&
        payload is Map &&
        createdAt != null;
  }

  static Object? _normalizePendingOperation(Object? value) {
    if (value is! Map || value['type']?.toString() != 'batchReview') {
      return value;
    }
    final payloadValue = value['payload'];
    if (payloadValue is! Map) return value;

    final normalized = Map<Object?, Object?>.from(value);
    final payload = Map<Object?, Object?>.from(payloadValue);
    final projectId = _firstNonEmpty([
      value['project_id'],
      payload['project_id'],
      payload['batch_id'],
    ]);
    payload.remove('batch_id');
    if (projectId != null) {
      normalized['project_id'] = projectId;
      payload['project_id'] = projectId;
    }
    normalized['payload'] = payload;
    return normalized;
  }

  static String? _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
