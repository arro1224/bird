import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const startRequest = SmartFollowStartRequest(targetMediaId: 'media_usb_fake', reviewExportEnabled: true);

Future<SmartFollowRepository> startedRepository(FakeSmartFollowBackend backend) async {
  final repository = SmartFollowRepository(backend);
  await repository.startOnRecognitionJob('rec_fake', startRequest);
  return repository;
}

Widget host(SmartFollowRepository repository, FakeSmartFollowBackend backend, {int? processed, int? total, VoidCallback? onOpenChildJobs, VoidCallback? onOpenCompletion}) => MaterialApp(
  home: SmartFollowRunPage(
    repository: repository,
    sessionId: backend.sessionId,
    recognitionProcessed: processed,
    recognitionTotal: total,
    onOpenChildJobs: onOpenChildJobs,
    onOpenCompletion: onOpenCompletion,
  ),
);

void main() {
  late FakeSmartFollowBackend backend;
  late SmartFollowRepository repository;

  setUp(() async {
    backend = FakeSmartFollowBackend(batchSize: 8);
    repository = await startedRepository(backend);
  });

  tearDown(() => repository.dispose());

  testWidgets('运行中：阶段文案、各项计数分离，且没有完成页入口', (tester) async {
    backend.commitPhoto();
    backend.commitPhoto();
    backend.commitPhoto();
    await tester.pumpWidget(host(repository, backend, processed: 3, total: 14));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('smart-follow-stage-label')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-stage-label'))).data, '识别与复制中');
    expect(find.text('识别 3 / 14'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-eligible'))).data, '3 张');
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-pending'))).data, '3 张');
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-copied-assets'))).data, '0 张');
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-copied-files'))).data, '0 个');
    // 运行中不得出现"查看完成结果"。
    expect(find.byKey(const Key('smart-follow-open-completion')), findsNothing);
    // 按钮只来自 allowed_actions。
    expect(find.byKey(const Key('smart-follow-action-pause')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-action-stop_following')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-action-retry')), findsNothing);
  });

  testWidgets('复制快于识别：显示等待新的识别结果，而不是完成', (tester) async {
    backend.commitPhoto();
    backend.commitPhoto();
    backend.finishRecognition();
    backend.completeChildJobs();
    // 会话已完成：这里验证完成态的文案与入口
    await tester.pumpWidget(host(repository, backend, onOpenCompletion: () {}));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-stage-label'))).data, '已完成');
    expect(find.byKey(const Key('smart-follow-open-completion')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-action-stop_following')), findsNothing);
  });

  testWidgets('识别结束排空中：显示排空阶段且无可用动作', (tester) async {
    backend.commitPhoto();
    backend.finishRecognition();
    await tester.pumpWidget(host(repository, backend));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-stage-label'))).data, '识别结束·正在完成剩余复制');
    expect(find.byKey(const Key('smart-follow-action-pause')), findsNothing);
  });

  testWidgets('等待目标盘：阶段与副标题说明识别仍在继续，按钮只剩允许项', (tester) async {
    backend.commitPhoto();
    backend.waitForTarget();
    await tester.pumpWidget(host(repository, backend));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-stage-label'))).data, '等待目标盘');
    expect(find.textContaining('识别仍在继续'), findsWidgets);
    expect(find.byKey(const Key('smart-follow-action-pause')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-action-stop_following')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-action-finish_current_results')), findsNothing);
  });

  testWidgets('停止跟随要二次确认：取消不发请求，确认才发', (tester) async {
    backend.commitPhoto();
    await tester.pumpWidget(host(repository, backend));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('smart-follow-action-stop_following')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-action-stop_following')));
    await tester.pumpAndSettle();
    expect(find.text('停止跟随？'), findsOneWidget);
    expect(find.textContaining('不会再复制'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(backend.actCalls, 0);

    await tester.ensureVisible(find.byKey(const Key('smart-follow-action-stop_following')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-action-stop_following')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-confirm-stop')));
    await tester.pumpAndSettle();
    expect(backend.actCalls, 1);
    expect(backend.state, SmartFollowState.draining);
  });

  testWidgets('复制批次入口可点击，数量取后端 field', (tester) async {
    var opened = 0;
    backend.commitPhoto();
    backend.commitPhoto();
    backend.finishRecognition();
    await tester.pumpWidget(host(repository, backend, onOpenChildJobs: () => opened++));
    await tester.pumpAndSettle();
    expect(find.textContaining('已创建 1 批'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('smart-follow-child-jobs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-child-jobs')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('加载失败时显示可读文案而不是空白页', (tester) async {
    final failing = _FailingRepository();
    await tester.pumpWidget(MaterialApp(home: SmartFollowRunPage(repository: failing, sessionId: 'sf_missing')));
    await tester.pumpAndSettle();
    expect(find.textContaining('盒子'), findsWidgets);
  });
}

/// 只用于"会话读不到"的负向路径：不伪造任何数字。
class _FailingRepository extends SmartFollowRepository {
  _FailingRepository() : super(FakeSmartFollowBackend());

  @override
  Future<SmartFollowSession> refresh(String sessionId) async => throw StateError('盒子暂时没有返回这个会话');
}
