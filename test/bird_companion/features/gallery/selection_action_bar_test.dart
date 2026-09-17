import 'package:aves/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, {TextScaler? textScaler}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: textScaler ?? const TextScaler.linear(1)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SelectionActionBar(
              count: 4,
              busy: false,
              onAction: (_) {},
              onAddTags: () {},
              onRemoveTags: () {},
              onClear: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('批量操作栏在常规字体下完整展出全部操作按钮', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpBar(tester);

    final barRect = tester.getRect(find.byType(SelectionActionBar));
    // 抽屉高度随内容适配：常规字体下所有操作按钮完整落在抽屉视口内。
    for (final label in const ['确认保留', '确认弃选', '添加标签', '复制所选', '更多操作']) {
      final labelRect = tester.getRect(find.text(label));
      expect(
        labelRect.bottom <= barRect.bottom && labelRect.top >= barRect.top,
        isTrue,
        reason: '$label 应完整出现在抽屉视口内',
      );
    }
  });

  testWidgets('批量操作栏在大字体下不裁切按钮且允许滚动兜底', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpBar(tester, textScaler: const TextScaler.linear(1.6));

    // 大字体下超出自适应高度时允许滚动兜底，全部按钮可达。
    for (final label in const ['确认保留', '确认弃选', '添加标签', '复制所选', '更多操作']) {
      await tester.ensureVisible(find.text(label));
      expect(find.text(label), findsOneWidget, reason: '大字体下 $label 应滚动可达');
    }
    expect(
      find.descendant(
        of: find.byType(SelectionActionBar),
        matching: find.byType(Scrollable),
      ),
      findsWidgets,
      reason: '抽屉内容区应有可滚动兜底',
    );
  });
}
