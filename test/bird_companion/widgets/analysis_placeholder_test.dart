import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/analysis_placeholder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('低置信度状态会显示专用提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnalysisPlaceholder(state: AnalysisState.lowConfidence)),
      ),
    );
    expect(find.text('低置信度'), findsOneWidget);
  });
}
