import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_presentation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

CopyJobDetail jobDetail({
  CopyJobState state = CopyJobState.paused,
  CopyJobDeviceSnapshot? source,
  CopyJobDeviceSnapshot? target,
  List<CopyAllowedAction> actions = const [CopyAllowedAction.resume],
}) => CopyJobDetail(
  copyJobId: 'job',
  state: state,
  stateVersion: 1,
  eventSeq: 0,
  allowedActions: actions,
  stats: const CopyJobStats(totalFiles: 20, copiedFiles: 5, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0, totalBytes: 2000, copiedBytes: 500),
  sourceDevice: source,
  targetDevice: target,
);

class _Repository implements CopyJobRepository {
  _Repository(this.current);

  CopyJobDetail current;
  Object? actionError;

  @override
  Future<CopyJobDetail> getJob(String id) async => current;

  @override
  Future<CopyJobDetail?> jobAction(String id, String action, {required int expectedStateVersion}) async {
    if (actionError != null) throw actionError!;
    return current;
  }

  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);

  @override
  Future<CopyReport> jobReport(String id) async => const CopyReport(copyJobId: 'job');

  @override
  Future<CopyJobPage> listJobs({String? cursor}) async => const CopyJobPage(items: [], hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('v10-12 目标盘拔出保留任务快照名并标注已拔出；列表不可读时不误报', () {
    const frozen = CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee');
    expect(copyTaskDeviceName(source: false, snapshot: frozen, devices: [b3Device('disk', online: false)]), 'U 盘 Ee（已拔出）');
    // 设备列表为空 = 本次没读到，不能据此说"已拔出"。
    expect(copyTaskDeviceName(source: false, snapshot: frozen), 'U 盘 Ee');
    expect(copyTaskDeviceName(source: false, snapshot: frozen, devices: [b3Device('disk')]), 'U 盘 Ee');
    expect(copyTaskDeviceName(source: true, snapshot: const CopyJobDeviceSnapshot(mediaId: 'card', displayName: '相机卡'), devices: [b3Device('card', source: true, target: false, online: false)]), '相机卡（已拔出）');
  });

  testWidgets('v10-12 暂停任务的离线目标显示快照名，继续按钮禁用并提示等待原目标盘', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(
      jobDetail(
        source: const CopyJobDeviceSnapshot(mediaId: 'card', displayName: '相机卡'),
        target: const CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(
          copyJobId: 'job',
          repository: repository,
          deviceReader: () async => CopyDeviceList(devices: [b3Device('card', source: true, target: false), b3Device('disk', online: false)]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('U 盘 Ee（已拔出）'), findsOneWidget);
    final resume = tester.widget<OutlinedButton>(find.byKey(const Key('copy-job-action-resume')));
    expect(resume.onPressed, isNull, reason: '原目标盘缺失时不得发起继续');
    expect(find.byKey(const Key('copy-job-missing-device-hint')), findsOneWidget);
    expect(find.textContaining('等待原目标盘'), findsOneWidget);
    expect(find.textContaining('选择其他'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('v10-12 目标盘在线时继续按钮可用', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _Repository(
      jobDetail(
        source: const CopyJobDeviceSnapshot(mediaId: 'card', displayName: '相机卡'),
        target: const CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(
          copyJobId: 'job',
          repository: repository,
          deviceReader: () async => CopyDeviceList(devices: [b3Device('card', source: true, target: false), b3Device('disk')]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-job-missing-device-hint')), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('copy-job-action-resume'))).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('v10-12 继续失败不再提示可选择其他目标盘', () async {
    final repository = _Repository(
      jobDetail(
        target: const CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
      ),
    )..actionError = const ApiException(code: 'COPY_TARGET_NOT_PRESENT', message: 'target missing', statusCode: 409);
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job');
    await cubit.load();
    await cubit.act(CopyAllowedAction.resume);
    expect(cubit.state.notice, contains('插回同一目标设备'));
    expect(cubit.state.notice, isNot(contains('选择其他目标设备')));
    await cubit.close();
  });
}
