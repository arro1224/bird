import 'package:aves/bird_companion/core/storage/cache_schema_migrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v1 cache migration is additive and preserves pending conflicts', () {
    final pending = [
      {
        'id': 'review-1',
        'type': 'updateReview',
        'payload': {'file_id': 'photo-1', 'keep_state': 'keep'},
        'created_at': '2026-07-29T08:00:00Z',
        'device_id': 'box-a',
        'status': 'conflict',
      },
      {'unknown': 'legacy-shape'},
    ];
    final source = <String, Object?>{
      'pending_operations': pending,
      'album:view:project-1': {'sort': 'newest'},
    };

    final writes = CacheSchemaMigrator.writesFor(source);
    final upgraded = {...source, ...writes};

    expect(
      upgraded[CacheSchemaMigrator.schemaVersionKey],
      CacheSchemaMigrator.currentSchemaVersion,
    );
    expect(
      upgraded[CacheSchemaMigrator.pendingBackupKey],
      same(pending),
    );
    final migrated = upgraded[CacheSchemaMigrator.pendingOperationsKey] as List;
    expect(migrated, hasLength(1));
    expect((migrated.single as Map)['status'], 'conflict');
    expect((migrated.single as Map)['device_id'], 'box-a');
    expect(
      upgraded[CacheSchemaMigrator.pendingQuarantineKey],
      hasLength(1),
    );
    expect(upgraded['pending_operations'], same(pending));
    expect(
      upgraded['quarantine:v1:album:view:project-1'],
      {'sort': 'newest'},
    );
  });

  test('current schema migration is idempotent', () {
    expect(
      CacheSchemaMigrator.writesFor({
        CacheSchemaMigrator.schemaVersionKey: CacheSchemaMigrator.currentSchemaVersion,
      }),
      isEmpty,
    );
  });

  test('migrated batch review replaces legacy batch_id with project_id', () {
    final pending = [
      {
        'id': 'batch-1',
        'type': 'batchReview',
        'payload': {
          'file_ids': ['photo-1'],
          'operation': 'mark_keep',
          'batch_id': 'project-1',
        },
        'created_at': '2026-07-29T08:00:00Z',
      },
    ];

    final writes = CacheSchemaMigrator.writesFor({
      CacheSchemaMigrator.legacyPendingOperationsKey: pending,
    });

    final backup = writes[CacheSchemaMigrator.pendingBackupKey] as List;
    expect((backup.single as Map)['payload'], containsPair('batch_id', 'project-1'));

    final migrated = writes[CacheSchemaMigrator.pendingOperationsKey] as List;
    final operation = migrated.single as Map;
    final payload = operation['payload'] as Map;
    expect(operation['project_id'], 'project-1');
    expect(payload['project_id'], 'project-1');
    expect(payload, isNot(contains('batch_id')));
  });

  test('legacy device addresses become v3 hints with rc4 modes', () {
    final legacyActive = {
      'device_id': 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
      'device_name': 'BirdBox-82F41C9E',
      'base_uri': 'http://192.168.4.1:8080',
      'network_mode': 'hotspot',
      'is_paired': true,
    };
    final legacyRecent = [
      legacyActive,
      {
        'device_id': 'bbx-11111111111111111111111111111111',
        'ip_address': 'http://192.168.1.17:8080',
        'network_mode': 'qr',
      },
    ];

    final writes = CacheSchemaMigrator.writesFor({
      CacheSchemaMigrator.schemaVersionKey: 2,
      CacheSchemaMigrator.legacyActiveDeviceKey: legacyActive,
      CacheSchemaMigrator.legacyRecentDevicesKey: legacyRecent,
    });

    expect(
      writes[CacheSchemaMigrator.activeDeviceBackupKey],
      same(legacyActive),
    );
    final active = writes[CacheSchemaMigrator.activeDeviceKey] as Map;
    expect(active['address_hint'], 'http://192.168.4.1:8080');
    expect(active['network_mode'], 'direct_ap');
    expect(active, isNot(contains('base_uri')));

    final recent = writes[CacheSchemaMigrator.recentDevicesKey] as List;
    expect((recent.last as Map)['network_mode'], 'infrastructure_sta');
    expect((recent.last as Map), isNot(contains('ip_address')));
    expect(
      writes[CacheSchemaMigrator.legacyActiveDeviceKey],
      isNull,
      reason: 'Migration must leave legacy keys untouched.',
    );
  });
}
