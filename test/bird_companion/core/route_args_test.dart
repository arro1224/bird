import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('类型化路由参数保留业务编号', () {
    const gallery = GalleryArgs('batch-1', batchName: '崇明东滩', totalCount: 3672);
    expect(gallery.batchId, 'batch-1');
    expect(gallery.batchName, '崇明东滩');
    const detail = PhotoDetailArgs('photo-1', displayIndex: 12, totalCount: 3672, sequence: ['photo-1', 'photo-2']);
    expect(detail.fileId, 'photo-1');
    expect(detail.displayIndex, 12);
    expect(detail.sequence, ['photo-1', 'photo-2']);
    expect(const SceneListArgs('batch-1').batchId, 'batch-1');
    expect(const GroupReviewArgs('batch-1', sceneId: 'scene-1').sceneId, 'scene-1');
    expect(
      const ComparisonReviewArgs(
        groupId: 'group-1',
        fileIds: ['a', 'b'],
      ).fileIds.length,
      2,
    );
    expect(
      const ConnectionArgs(
        entryMode: ConnectionEntryMode.addOrSwitch,
      ).entryMode,
      ConnectionEntryMode.addOrSwitch,
    );
  });

  test('审片上下文完整保留批次、场景、连拍组和当前照片', () {
    const batch = ReviewContext(
      batchId: 'batch-1',
      batchName: '崇明东滩',
    );
    final scene = batch.enterScene('scene-1', name: '清晨芦苇荡');
    final group = scene.enterGroup(
      'group-1',
      name: 'Burst 012',
      photos: const ['p1', 'p2', 'p3'],
      initialIndex: 1,
    );
    final detail = PhotoDetailArgs.fromReview(group, totalCount: 3672);
    final comparison = ComparisonReviewArgs.fromReview(
      group.openPhotos(const ['p1', 'p2']),
    );

    expect(group.batchId, 'batch-1');
    expect(group.sceneId, 'scene-1');
    expect(group.groupId, 'group-1');
    expect(group.currentPhotoId, 'p2');
    expect(detail.fileId, 'p2');
    expect(detail.displayIndex, 2);
    expect(detail.totalCount, 3672);
    expect(detail.reviewContext?.sceneName, '清晨芦苇荡');
    expect(comparison.fileIds, ['p1', 'p2']);
    expect(comparison.reviewContext?.groupName, 'Burst 012');
  });

  test('审片上下文页内切换会限制在照片序列范围内', () {
    const context = ReviewContext(
      batchId: 'batch-1',
      photoIds: ['p1', 'p2'],
    );

    expect(context.moveTo(1).currentPhotoId, 'p2');
    expect(context.moveTo(99).currentPhotoId, 'p2');
    expect(context.moveTo(-5).currentPhotoId, 'p1');
  });
}
