abstract final class CacheSchemaMigrator {
  static const schemaVersionKey = 'bird_companion_cache_schema_version';
  static const currentSchemaVersion = 2;
  static const legacyPendingOperationsKey = 'pending_operations';
  static const pendingOperationsKey = 'pending_operations:v2';
  static const pendingBackupKey = 'migration_backup:v2:pending_operations';
  static const pendingQuarantineKey = 'quarantine:v2:pending_operations';

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
    writes[schemaVersionKey] = currentSchemaVersion;
    return writes;
  }

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
