import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('审片面包屑在 320dp 宽度可横向滚动且层级可点击', (tester) async {
    var batchTapped = false;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirdReviewBreadcrumb(
            current: BirdReviewLevel.scene,
            onBatch: () => batchTapped = true,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('review-breadcrumb-scroll')), findsOneWidget);
    await tester.tap(find.text('拍摄记录'));
    expect(batchTapped, isTrue);
    expect(find.text('单张照片'), findsOneWidget);
  });

  testWidgets('统一二级标题栏保留返回、标题、副标题和帮助入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: BirdSecondaryAppBar(
            title: '连拍照片挑选',
            subtitle: '清晨芦苇荡',
            onHelp: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.text('连拍照片挑选'), findsOneWidget);
    expect(find.text('清晨芦苇荡'), findsOneWidget);
    expect(find.byTooltip('页面说明'), findsOneWidget);
  });
}
