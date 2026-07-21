import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('带撤销的提示在无障碍模式下也会自动消失', (tester) async {
    late BuildContext feedbackContext;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Builder(
            builder: (context) {
              feedbackContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );

    BirdFeedback.undo(feedbackContext, '已保留 12 张照片', onUndo: () {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已保留 12 张照片'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.pump(BirdFeedback.undoDuration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已保留 12 张照片'), findsNothing);
  });

  testWidgets('新提示会替换旧提示而不排队', (tester) async {
    late BuildContext feedbackContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            feedbackContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    BirdFeedback.undo(feedbackContext, '第一条', onUndo: () {});
    await tester.pump();
    BirdFeedback.success(feedbackContext, '第二条');
    await tester.pumpAndSettle();

    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
  });

  testWidgets('切换页面时会清除上一页反馈', (tester) async {
    late BuildContext feedbackContext;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: BirdFeedback.messengerKey,
        navigatorObservers: [BirdFeedbackNavigatorObserver()],
        home: Builder(
          builder: (context) {
            feedbackContext = context;
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('下一页')),
                  ),
                ),
                child: const Text('打开'),
              ),
            );
          },
        ),
      ),
    );

    BirdFeedback.undo(feedbackContext, '上一页反馈', onUndo: () {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('上一页反馈'), findsOneWidget);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('下一页'), findsOneWidget);
    expect(find.text('上一页反馈'), findsNothing);
  });
}
