import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 修复 3 走查（2026-10-14）：复制任务列表「加载更多」失败手动重试 footer。
///
/// 实机走查补充：`BIRD_USE_MOCK_COPY=true` 时 listJobs 走 App 内置内存 mock，
/// pageSize=20 且永不抛错，单会话造不出 hasMore+失败组合——footer 行为
/// （copy_job_list_page.dart `_loadMore` 失败置 `_loadMoreFailed` 不自动重试、
/// 重试 footer 按钮手动触发）在此用注入分页失败的 fake 仓储验证。
void main() {
  testWidgets('加载更多失败 → footer 显示「加载失败，点击重试」，点重试成功后追加下一页', (tester) async {
    final repository = _PagingFakeRepository();
    await tester.pumpWidget(
      MaterialApp(home: CopyJobListPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    // 首页 20 条已渲染（多于屏幕，footer 不可见也无所谓，先滚到底）。
    expect(find.text('照片复制'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-job-list-load-more-retry')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 自动加载更多失败 → 错误 footer 出现，且不再自动重试（防死循环）。
    expect(repository.loadMoreCalls, 1);
    expect(find.text('加载失败，点击重试'), findsOneWidget);

    // 手动点重试：仓储恢复后成功追加第二页。
    repository.failLoadMore = false;
    await tester.tap(find.byKey(const Key('copy-job-list-load-more-retry')));
    await tester.pumpAndSettle();

    expect(repository.loadMoreCalls, 2);
    // 重试成功后 hasMore=false、错误 footer 消失（列表懒加载，视口内只渲染部分卡片）。
    expect(find.text('加载失败，点击重试'), findsNothing);
    expect(find.byKey(const Key('copy-job-list-load-more-retry')), findsNothing);
  });
}

class _PagingFakeRepository implements CopyJobRepository {
  bool failLoadMore = true;
  int loadMoreCalls = 0;

  CopyJobListItem _item(String id) => CopyJobListItem(
    copyJobId: id,
    state: CopyJobState.completed,
    scopeWire: 'batch_all_assets',
    stats: const CopyJobStats(
      totalFiles: 2,
      copiedFiles: 1,
      failedFiles: 1,
      skippedFiles: 0,
      notApplicableFiles: 0,
      totalBytes: 1024,
      copiedBytes: 512,
      elapsedSeconds: 1,
    ),
    createdAt: DateTime.parse('2026-10-14T08:00:00Z'),
  );

  @override
  Future<CopyJobPage> listJobs({String? cursor}) async {
    if (cursor == null) {
      return CopyJobPage(
        items: [for (var i = 20; i >= 1; i--) _item('copy_job_page1_$i')],
        hasMore: true,
        nextCursor: '20',
      );
    }
    loadMoreCalls++;
    if (failLoadMore) {
      throw StateError('load more failed');
    }
    return CopyJobPage(
      items: [for (var i = 10; i >= 1; i--) _item('copy_job_page2_$i')],
      hasMore: false,
      nextCursor: null,
    );
  }

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [CopyScope.batchAllAssets],
    recognitionPolicyVersion: 'recognized-assets-v1',
  );

  @override
  Future<CopyJobDetail> getJob(String copyJobId) => throw UnimplementedError();

  @override
  Future<CopyJobItemPage> jobItems(String copyJobId, {String? cursor, String? state}) => throw UnimplementedError();

  @override
  Future<CopyJobEventPage> jobEvents(String copyJobId, {int? afterSeq}) => throw UnimplementedError();

  @override
  Future<CopyReport> jobReport(String copyJobId) => throw UnimplementedError();

  @override
  Future<CopyJobDetail?> jobAction(
    String copyJobId,
    String actionWire, {
    required int expectedStateVersion,
  }) => throw UnimplementedError();

  @override
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) => throw UnimplementedError();

  @override
  Future<SafeRemoveResult> safeRemoveDevice(
    String mediaId, {
    required String role,
    String? expectedCopyJobId,
  }) => throw UnimplementedError();
}
