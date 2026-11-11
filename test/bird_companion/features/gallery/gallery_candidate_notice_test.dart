import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/gallery_candidate_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

Color? _textColor(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('gallery-candidate-notice-text'))).style?.color;

void main() {
  testWidgets('在线完整候选：不显示提示且不占高度', (tester) async {
    await _pump(
      tester,
      GalleryCandidateNotice(
        loadedCount: 40,
        totalCount: 40,
        resultComplete: true,
        offline: false,
        onRefresh: () {},
      ),
    );
    expect(find.byKey(const Key('gallery-candidate-notice')), findsNothing);
    expect(tester.getSize(find.byType(GalleryCandidateNotice)).height, 0);
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
