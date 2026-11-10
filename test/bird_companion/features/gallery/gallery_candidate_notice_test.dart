import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/gallery_candidate_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

Color? _textColor(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('gallery-candidate-notice-text'))).style?.color;

void main() {
  testWidgets('在线完整候选：提示本机筛选，不显示重新连接，可刷新候选数据', (tester) async {
    var refreshed = 0;
    await _pump(
      tester,
      GalleryCandidateNotice(
        cachedAt: DateTime(2026, 11, 9, 12, 30),
        loadedCount: 40,
        totalCount: 40,
        resultComplete: true,
        offline: false,
        onRefresh: () => refreshed++,
      ),
    );
    expect(find.textContaining('已使用完整候选数据在本机筛选'), findsOneWidget);
    expect(find.text('重新连接'), findsNothing);
    expect(find.text('刷新候选数据'), findsOneWidget);
    expect(_textColor(tester), AppColors.brand);
    await tester.tap(find.text('刷新候选数据'));
    expect(refreshed, 1);
  });

  testWidgets('真断线：红色警示并保留下重新连接入口', (tester) async {
    var reconnected = 0;
    await _pump(
      tester,
      GalleryCandidateNotice(
        loadedCount: 20,
        totalCount: 40,
        resultComplete: false,
        offline: true,
        onReconnect: () => reconnected++,
      ),
    );
    expect(find.textContaining('设备暂时无法连接'), findsOneWidget);
    expect(find.textContaining('仅在已缓存的 20 / 40 张照片中查找'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
    expect(find.text('刷新候选数据'), findsNothing);
    expect(_textColor(tester), AppColors.danger);
    await tester.tap(find.text('重新连接'));
    expect(reconnected, 1);
  });

  testWidgets('在线但结果不完整：标记不完整且为红色，不暗示完整候选', (tester) async {
    await _pump(
      tester,
      const GalleryCandidateNotice(loadedCount: 8, totalCount: null, resultComplete: false, offline: false, onRefresh: _noop),
    );
    expect(find.textContaining('结果可能不完整'), findsOneWidget);
    expect(find.textContaining('完整候选数据'), findsNothing);
    expect(_textColor(tester), AppColors.danger);
    expect(find.text('刷新候选数据'), findsOneWidget);
  });
}

void _noop() {}
