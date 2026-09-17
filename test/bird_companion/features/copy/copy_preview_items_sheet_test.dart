import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_preview_items_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 预检文件明细弹层（§10.2）：
/// 核心验收——空明细 + 文件数>0 → Key copy-preview-items-unavailable 琥珀警告，
/// 不得渲染「暂无文件」正常空态。
void main() {
  testWidgets('空明细 + 文件数>0 → 明细不可用警告而非正常空态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CopyPreviewItemsSheet(
          repository: _SheetFakeRepository(items: const []),
          previewToken: 'preview_empty',
          summaryFileCount: 64,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('copy-preview-items-unavailable')), findsOneWidget);
    expect(find.text('暂无文件'), findsNothing);
    expect(find.textContaining('预检明细暂不可用'), findsOneWidget);
  });

  testWidgets('明细为空且文件数为 0 → 正常空态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CopyPreviewItemsSheet(
          repository: _SheetFakeRepository(items: const []),
          previewToken: 'preview_truly_empty',
          summaryFileCount: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('copy-preview-items-unavailable')), findsNothing);
    expect(find.text('暂无文件'), findsOneWidget);
  });

  testWidgets('行渲染：源路径→目标路径 + 冲突徽标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CopyPreviewItemsSheet(
          repository: _SheetFakeRepository(
            items: [
              const CopyJobItem(
                copyItemId: 'item_0001',
                sourceRelativePath: 'DCIM/100MSDCF/DSC05000',
                targetRelativeDirectory: '20260901',
                targetFilename: 'DSC05000.ARW',
                conflictDecision: 'skip',
              ),
              const CopyJobItem(
                copyItemId: 'item_0002',
                sourceRelativePath: 'DCIM/100MSDCF/DSC05001',
                targetRelativeDirectory: '20260901',
                targetFilename: 'DSC05001.JPG',
              ),
            ],
          ),
          previewToken: 'preview_rows',
          summaryFileCount: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DCIM/100MSDCF/DSC05000'), findsOneWidget);
    expect(find.text('→ 20260901/DSC05000.ARW'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('DCIM/100MSDCF/DSC05001'), findsOneWidget);
    expect(find.byKey(const Key('copy-preview-items-unavailable')), findsNothing);
  });

  testWidgets('hasMore → 自动加载下一页（分页不去重）', (tester) async {
    final pages = [
      List.generate(20, (i) => CopyJobItem(copyItemId: 'p1_${i.toString().padLeft(2, '0')}')),
      List.generate(20, (i) => CopyJobItem(copyItemId: 'p2_${i.toString().padLeft(2, '0')}')),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: CopyPreviewItemsSheet(
          repository: _SheetFakeRepository(pages: pages),
          previewToken: 'preview_paged',
          summaryFileCount: 40,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('p1_00'), findsOneWidget);
    // 滚动到底触发末尾的加载锚点，自动拉第 2 页（锚点是常驻 spinner，不能 pumpAndSettle）。
    await tester.dragUntilVisible(
      find.text('p2_00'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('p2_00'), findsOneWidget);
  });
}

class _SheetFakeRepository implements CopyJobRepository {
  _SheetFakeRepository({this.items = const [], this.pages});

  final List<CopyJobItem> items;
  final List<List<CopyJobItem>>? pages;

  @override
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) async {
    final source = pages;
    if (source == null) {
      return CopyJobItemPage(items: items, hasMore: false);
    }
    final index = int.tryParse(cursor ?? '') ?? 0;
    final page = source[index];
    final hasMore = index + 1 < source.length;
    return CopyJobItemPage(
      items: page,
      hasMore: hasMore,
      nextCursor: hasMore ? '${index + 1}' : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
