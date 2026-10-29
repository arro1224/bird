import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_task_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const startRequest = SmartFollowStartRequest(targetMediaId: 'media_usb_fake', reviewExportEnabled: true);

void main() {
  late FakeSmartFollowBackend backend;
  late SmartFollowRepository repository;

  setUp(() {
    backend = FakeSmartFollowBackend(batchSize: 8);
    repository = SmartFollowRepository(backend);
  });

  tearDown(() => repository.dispose());

  Widget host({ValueChanged<String>? onOpen, String jobId = 'rec_fake'}) => MaterialApp(
    home: Scaffold(
      body: SmartFollowTaskTile(
        repository: repository,
        recognitionJobId: jobId,
        recognitionProcessed: 3,
        recognitionTotal: 14,
        onOpenRun: onOpen ?? (_) {},
      ),
    ),
  );

  testWidgets('没有跟随会话的识别任务：任务详情不多出一块空卡', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smart-follow-task-tile')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有会话时显示阶段与三项计数，点击带着会话 ID 进运行页', (tester) async {
    await repository.startOnRecognitionJob('rec_fake', startRequest);
    backend.commitPhoto();
    backend.commitPhoto();
    // 真实路径里由 WS 事件唤醒重读；测试里显式刷新一次，等价。
    await repository.refreshForJob('rec_fake');
    String? opened;
    await tester.pumpWidget(host(onOpen: (id) => opened = id));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('smart-follow-task-tile')), findsOneWidget);
    expect(find.text('边识别边复制'), findsOneWidget);
    expect(find.text('识别与复制中'), findsOneWidget);
    expect(find.text('已识别 2 张 · 待复制 2 张 · 已复制 0 张'), findsNothing);
    expect(find.text('识别 3/14 · 已识别 2 张 · 待复制 2 张 · 已复制 0 张'), findsOneWidget);

    await tester.tap(find.byKey(const Key('smart-follow-task-tile')));
    await tester.pumpAndSettle();
    expect(opened, backend.sessionId);
  });

  testWidgets('会话完成后卡片仍在（可回看结果），阶段变成已完成', (tester) async {
    await repository.startOnRecognitionJob('rec_fake', startRequest);
    backend.commitPhoto();
    backend.finishRecognition();
    backend.completeChildJobs();
    await repository.refreshForJob('rec_fake');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('读会话失败时静默隐藏，不打断任务详情其它内容', (tester) async {
    final failing = _FailingTileRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartFollowTaskTile(repository: failing, recognitionJobId: 'rec_fake', onOpenRun: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smart-follow-task-tile')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FailingTileRepository extends SmartFollowRepository {
  _FailingTileRepository() : super(FakeSmartFollowBackend());

  @override
  Future<SmartFollowSession?> refreshForJob(String recognitionJobId) async => throw StateError('盒子暂时没有返回跟随会话');
}
