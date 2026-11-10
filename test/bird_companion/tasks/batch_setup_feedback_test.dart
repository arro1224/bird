import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/batch_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('space is formatted and configuration rebuild retains the batch name without focusing it', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    controller.sdCard = controller.sdCard.copyWith(requiredSpaceGb: 0.7233238220214844);
    final ready = ValueNotifier(true);
    addTearDown(ready.dispose);
    await tester.pumpWidget(MaterialApp(home: ValueListenableBuilder<bool>(
      valueListenable: ready,
      builder: (_, value, _) => BatchSetupPage(controller: controller, canStartImport: value),
    )));
    final field = find.byKey(const Key('batch-name-field'));
    await tester.enterText(field, 'Keep this batch');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    ready.value = false;
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Keep this batch');
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('0.72 GB'), findsOneWidget);
    expect(find.text('0.7233238220214844 GB'), findsNothing);
  });
}
