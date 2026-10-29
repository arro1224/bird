import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_child_jobs_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const startRequest = SmartFollowStartRequest(targetMediaId: 'media_usb_fake', reviewExportEnabled: true);

void main() {
  late FakeSmartFollowBackend backend;
  late SmartFollowRepository repository;

  setUp(() async {
    // batchSize=1：每张已识别照片封一批，方便造多批数据。
    backend = FakeSmartFollowBackend(batchSize: 1);
    repository = SmartFollowRepository(backend);
    await repository.startOnRecognitionJob('rec_fake', startRequest);
  });

  tearDown(() => repository.dispose());

  Widget host({int pageSize = 2, ValueChanged<String>? onOpenCopyJob}) => MaterialApp(
    home: Scaffold(
      body: SmartFollowChildJobsView(
        repository: repository,
        sessionId: backend.sessionId,
        pageSize: pageSize,
        onOpenCopyJob: onOpenCopyJob,
      ),
    ),
  );

  testWidgets('首屏只取一页，点"加载更多"再追下一页且不重复', (tester) async {
    for (var i = 0; i < 3; i++) {
      backend.commitPhoto();
    }
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('smart-follow-child-job-cj_fake_1')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-child-job-cj_fake_2')), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-child-job-cj_fake_3')), findsNothing);
    expect(find.textContaining('已加载 2 批'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('smart-follow-child-jobs-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-child-jobs-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('smart-follow-child-job-cj_fake_3')), findsOneWidget);
    expect(find.textContaining('已加载 3 批'), findsOneWidget);
    // 没有更多时不再显示按钮，也不会重复追加同一批。
    expect(find.byKey(const Key('smart-follow-child-jobs-more')), findsNothing);
  });

  testWidgets('批次行显示后端的状态与数量，点击交给上层跳 RC3 详情', (tester) async {
    String? opened;
    backend.commitPhoto();
    backend.finishRecognition();
    await tester.pumpWidget(host(onOpenCopyJob: (id) => opened = id));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 张照片 · 1 个文件'), findsOneWidget);
    expect(find.textContaining('复制中'), findsWidgets);

    await tester.tap(find.byKey(const Key('smart-follow-child-job-cj_fake_1')));
    await tester.pumpAndSettle();
    expect(opened, 'cj_fake_1');
  });

  testWidgets('还没有批次时给出空态而不是空白', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('还没有创建复制批次'), findsOneWidget);
  });
}
