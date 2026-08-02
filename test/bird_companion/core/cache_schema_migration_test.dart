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
}
