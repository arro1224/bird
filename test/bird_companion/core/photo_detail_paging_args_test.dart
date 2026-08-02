import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('详情路由保留分页加载器和当前照片位置', () async {
    const context = ReviewContext(batchId: 'batch-1', photoIds: ['p1', 'p2'], currentIndex: 1);
    final args = PhotoDetailArgs.fromReview(
      context,
      totalCount: 3,
      hasMoreSequence: true,
      loadMoreSequence: () async => const PhotoSequencePage(ids: ['p1', 'p2', 'p3'], hasMore: false),
    );

    expect(args.fileId, 'p2');
    expect(args.displayIndex, 2);
    expect(args.totalCount, 3);
    expect(args.hasMoreSequence, isTrue);
    final nextPage = await args.loadMoreSequence!();
    expect(nextPage.ids, ['p1', 'p2', 'p3']);
    expect(nextPage.hasMore, isFalse);
  });

  test('对比路由保留连续连拍组和当前组位置', () {
    const groups = [
      ReviewContext(
        batchId: 'batch-1',
        groupId: 'group-1',
        photoIds: ['p1', 'p2'],
      ),
      ReviewContext(
        batchId: 'batch-1',
        groupId: 'group-2',
        photoIds: ['p3', 'p4', 'p5'],
      ),
    ];

    final args = ComparisonReviewArgs.fromReview(
      groups[1],
      groups: groups,
      initialGroupIndex: 1,
    );

    expect(args.groupId, 'group-2');
    expect(args.fileIds, ['p3', 'p4', 'p5']);
    expect(args.groups, groups);
    expect(args.initialGroupIndex, 1);
  });
}
