import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/gallery_candidate_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

Color? _textColor(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('gallery-candidate-notice-text'))).style?.color;

void main() {
  testWidgets('在线完整候选：只留一行本机筛选说明，不显示重新连接', (tester) async {
    await _pump(
      tester,
      GalleryCandidateNotice(
        cachedAt: DateTime(2026, 11, 9, 12, 30),
        loadedCount: 40,
        totalCount: 40,
        resultComplete: true,
        offline: false,
        onRefresh: () {},
      ),
    );
    expect(find.text('已使用完整候选数据在本机筛选'), findsOneWidget);
    expect(find.text('重新连接'), findsNothing);
    expect(find.byKey(const Key('gallery-candidate-notice-action')), findsNothing);
    expect(_textColor(tester), AppColors.inkMuted);
    // 单行提示不应再占一大块版面。
    expect(tester.getSize(find.byKey(const Key('gallery-candidate-notice'))).height, lessThan(30));
  });

  testWidgets('真断线：短警示 + 重连入口，红色', (tester) async {
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
    expect(find.textContaining('设备未连接'), findsOneWidget);
    expect(find.textContaining('20/40'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
    expect(find.byKey(const Key('gallery-candidate-notice-action')), findsOneWidget);
    expect(_textColor(tester), AppColors.danger);
    await tester.tap(find.text('重新连接'));
    expect(reconnected, 1);
    expect(tester.getSize(find.byKey(const Key('gallery-candidate-notice'))).height, lessThan(60));
  });

  testWidgets('在线但候选不完整：短警示 + 刷新，不暗示完整', (tester) async {
    var refreshed = 0;
    await _pump(
      tester,
      GalleryCandidateNotice(loadedCount: 8, resultComplete: false, offline: false, onRefresh: () => refreshed++),
    );
    expect(find.textContaining('候选不完整'), findsOneWidget);
    expect(find.textContaining('8'), findsOneWidget);
    expect(find.textContaining('完整候选数据'), findsNothing);
    expect(find.text('刷新'), findsOneWidget);
    expect(_textColor(tester), AppColors.danger);
    await tester.tap(find.text('刷新'));
    expect(refreshed, 1);
  });
}
