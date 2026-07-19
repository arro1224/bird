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
}
