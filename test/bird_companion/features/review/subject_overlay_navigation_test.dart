import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/subject_overlay_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('首张只显示下一张箭头并触发回调', (tester) async {
    var nextCount = 0;
    await tester.pumpWidget(_preview(onNext: () => nextCount++));

    expect(find.byKey(const ValueKey('photo-previous-button')), findsNothing);
    expect(find.byKey(const ValueKey('photo-next-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo-next-button')));
    expect(nextCount, 1);
  });

  testWidgets('中间照片同时显示上一张和下一张箭头', (tester) async {
    var previousCount = 0;
    var nextCount = 0;
    await tester.pumpWidget(
      _preview(
        onPrevious: () => previousCount++,
        onNext: () => nextCount++,
      ),
    );

    expect(find.byKey(const ValueKey('photo-previous-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-next-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo-previous-button')));
    await tester.tap(find.byKey(const ValueKey('photo-next-button')));
    expect(previousCount, 1);
    expect(nextCount, 1);
  });

  testWidgets('末张只显示上一张箭头', (tester) async {
    await tester.pumpWidget(_preview(onPrevious: () {}));

    expect(find.byKey(const ValueKey('photo-previous-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-next-button')), findsNothing);
  });

  testWidgets('单张照片不显示翻页箭头', (tester) async {
    await tester.pumpWidget(_preview());

    expect(find.byKey(const ValueKey('photo-previous-button')), findsNothing);
    expect(find.byKey(const ValueKey('photo-next-button')), findsNothing);
  });

  testWidgets('加载或保存期间保留箭头但禁用点击', (tester) async {
    var nextCount = 0;
    await tester.pumpWidget(
      _preview(
        onNext: () => nextCount++,
        navigationEnabled: false,
      ),
    );

    expect(find.byKey(const ValueKey('photo-next-button')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('photo-next-button')));
    expect(nextCount, 0);
  });

  testWidgets('箭头使用详情页深灰色并具有可访问提示', (tester) async {
    await tester.pumpWidget(_preview(onNext: () {}));

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.color, AppColors.inkMuted);
    expect(button.tooltip, '下一张');
    expect(button.constraints, const BoxConstraints.tightFor(width: 52, height: 52));
  });
}

Widget _preview({
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  bool navigationEnabled = true,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 390,
        child: SubjectOverlayView(
          photo: _photo,
          subjects: const [],
          onPrevious: onPrevious,
          onNext: onNext,
          navigationEnabled: navigationEnabled,
        ),
      ),
    ),
  ),
);

const _photo = PhotoDetail(
  summary: PhotoSummary(
    id: 'photo-1',
    filename: 'photo-1.jpg',
    format: 'JPEG',
    preview: PreviewRef(),
    analysisState: AnalysisState.completed,
  ),
);
