import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/presentation/widgets/job_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('已取消任务的“继续处理”发送 resume，而不是协议不支持的 restore', (tester) async {
    final actions = <String>[];
    const job = BirdJobStatus(
      id: 'job-cancelled',
      type: BirdJobType.copy,
      state: BirdJobState.cancelled,
      availableActions: ['resume'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobCard(job: job, onTap: () {}, onControl: actions.add),
        ),
      ),
    );

    expect(find.text('继续处理'), findsOneWidget);
    await tester.tap(find.text('继续处理'));

    expect(actions, ['resume']);
  });
}
