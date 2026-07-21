import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/analysis_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('识别结果不确定时会显示普通用户提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnalysisPlaceholder(state: AnalysisState.lowConfidence)),
      ),
    );
    expect(find.text('识别结果不确定'), findsOneWidget);
  });
}
