import 'package:aves/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('批量操作面板在 360dp 和 1.0/1.3/1.5 倍字体下不溢出', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 720));

    for (final scale in [1.0, 1.3, 1.5]) {
      await tester.pumpWidget(_app(textScale: scale));
      await tester.pump();

      expect(find.text('批量操作'), findsOneWidget);
      expect(find.text('确认保留'), findsOneWidget);
      expect(find.text('确认弃选'), findsOneWidget);
      expect(find.text('添加标签'), findsOneWidget);
      expect(find.text('复制所选'), findsOneWidget);
      expect(find.text('更多操作'), findsOneWidget);
      expect(find.text('确认操作'), findsOneWidget);
      expect(tester.getBottomLeft(find.byType(SelectionActionBar)).dy, 720);
      expect(tester.takeException(), isNull, reason: 'text scale $scale');
    }
  });

  testWidgets('部分失败后保留原操作并可直接重试', (tester) async {
    await _setViewport(tester, const Size(360, 720));
    final actions = <String>[];

    await tester.pumpWidget(
      _app(textScale: 1.3, onAction: actions.add),
    );
    await tester.tap(find.text('确认保留'));
    await tester.pump();
    await tester.tap(find.text('确认操作'));
    expect(actions, ['keep']);

    await tester.pumpWidget(
      _app(
        textScale: 1.3,
        count: 1,
        failedCount: 1,
        onAction: actions.add,
      ),
    );
    await tester.pump();

    expect(find.textContaining('有 1 张操作失败'), findsOneWidget);
    expect(find.text('重新尝试'), findsOneWidget);
    await tester.tap(find.text('重新尝试'));
    expect(actions, ['keep', 'keep']);
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required double textScale,
  int count = 2,
  int failedCount = 0,
  ValueChanged<String>? onAction,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: SelectionActionBar(
        count: count,
        busy: false,
        failedCount: failedCount,
        onAction: onAction ?? (_) {},
        onAddTags: () {},
        onRemoveTags: () {},
        onClear: () {},
        onCopy: () {},
      ),
    ),
  ),
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
