import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('类型化路由参数保留业务编号', () {
    expect(GalleryArgs('batch-1').batchId, 'batch-1');
    expect(PhotoDetailArgs('photo-1').fileId, 'photo-1');
    expect(ComparisonReviewArgs(groupId: 'group-1', fileIds: const ['a', 'b']).fileIds.length, 2);
  });
}
