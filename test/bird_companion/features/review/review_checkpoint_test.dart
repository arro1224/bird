import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:aves/bird_companion/features/review/domain/review_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('审阅断点完整序列化并按设备和批次隔离', () async {
    final store = ReviewCheckpointStore.memory();
    final updatedAt = DateTime.utc(2026, 7, 28, 8, 30);
    final deviceA = ReviewCheckpoint.fromContext(
      deviceId: 'device-a',
      context: const ReviewContext(
        batchId: 'batch-1',
        batchName: '崇明东滩',
        sceneId: 'scene-2',
        sceneName: '潮滩',
        groupId: 'group-8',
        groupName: '连拍第 8 组',
        photoIds: ['p1', 'p2', 'p3'],
        currentIndex: 1,
      ),
      query: const PhotoQuery(
        sort: 'score_desc',
        keepState: 'pending',
        minScore: 4,
      ),
      updatedAt: updatedAt,
    );
    final deviceB = ReviewCheckpoint.fromContext(
      deviceId: 'device-b',
      context: const ReviewContext(
        batchId: 'batch-1',
        groupId: 'group-2',
        photoIds: ['other'],
      ),
      updatedAt: updatedAt,
    );

    await store.save(deviceA);
    await store.save(deviceB);

    final restoredA = store.read(deviceId: 'device-a', batchId: 'batch-1');
    final restoredB = store.read(deviceId: 'device-b', batchId: 'batch-1');

    expect(restoredA?.groupId, 'group-8');
    expect(restoredA?.fileId, 'p2');
    expect(restoredA?.currentIndex, 1);
    expect(restoredA?.query.sort, 'score_desc');
    expect(restoredA?.query.minScore, 4);
    expect(restoredA?.updatedAt, updatedAt);
    expect(restoredB?.groupId, 'group-2');
    expect(
      store.read(deviceId: 'device-a', batchId: 'other-batch'),
      isNull,
    );

    await store.clear(deviceId: 'device-a', batchId: 'batch-1');
    expect(
      store.read(deviceId: 'device-a', batchId: 'batch-1'),
      isNull,
    );
    expect(
      store.read(deviceId: 'device-b', batchId: 'batch-1'),
      isNotNull,
    );
  });

  test('更新相册筛选和排序时保留已有连拍位置', () async {
    final store = ReviewCheckpointStore.memory();
    await store.save(
      ReviewCheckpoint.fromContext(
        deviceId: 'device-a',
        context: const ReviewContext(
          batchId: 'batch-1',
          groupId: 'group-8',
          photoIds: ['p1', 'p2'],
          currentIndex: 1,
        ),
      ),
    );

    await store.updateQuery(
      deviceId: 'device-a',
      batchId: 'batch-1',
      query: const PhotoQuery(
        sort: 'score_desc',
        clarityState: 'clear',
      ),
    );
    final restored = store.read(
      deviceId: 'device-a',
      batchId: 'batch-1',
    );

    expect(restored?.groupId, 'group-8');
    expect(restored?.fileId, 'p2');
    expect(restored?.query.sort, 'score_desc');
    expect(restored?.query.clarityState, 'clear');
  });
}
