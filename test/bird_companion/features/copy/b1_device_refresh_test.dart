import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_device_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

CopyJobDetail job(CopyJobState state) => CopyJobDetail(
  copyJobId: 'job',
  state: state,
  stateVersion: 1,
  eventSeq: 0,
  allowedActions: state.isTerminal ? const [] : const [CopyAllowedAction.pause],
  stats: const CopyJobStats(totalFiles: 10, copiedFiles: 5, skippedFiles: 0, failedFiles: 0, notApplicableFiles: 0, totalBytes: 1000, copiedBytes: 500),
  targetDevice: const CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee'),
);

class _Repository implements CopyJobRepository {
  _Repository(this.current);

  CopyJobDetail current;

  @override
  Future<CopyJobDetail> getJob(String id) async => current;

  @override
  Future<CopyJobItemPage> jobItems(String id, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);

  @override
  Future<CopyReport> jobReport(String id) async => const CopyReport(copyJobId: 'job');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('v10-5 任务终态会通知设备/任务数据刷新，运行中不打扰', () async {
    final bus = AppDataChangeBus();
    addTearDown(bus.dispose);
    final events = <AppDataChange>[];
    final subscription = bus.changes.listen(events.add);
    addTearDown(subscription.cancel);
    final repository = _Repository(job(CopyJobState.running));
    final cubit = CopyJobDetailCubit(repository, copyJobId: 'job', dataChanges: bus);
    await cubit.load();
    expect(events, isEmpty);

    repository.current = job(CopyJobState.completed);
    await cubit.load();
    expect(events, isNotEmpty);
    expect(events.last.affects(AppDataResource.jobs), isTrue);
    expect(events.last.affects(AppDataResource.device), isTrue);
    expect(events.last.reason, 'copy_job_terminal');
    await cubit.close();
  });

  test('v10-5 设备名按节流自动刷新，可强制刷新拿到重新插入的设备', () async {
    var online = false;
    var reads = 0;
    final cubit = CopyJobDetailCubit(
      _Repository(job(CopyJobState.paused)),
      copyJobId: 'job',
      deviceNamesInterval: const Duration(hours: 1),
      deviceReader: () async {
        reads++;
        return CopyDeviceList(devices: [b3Device('disk', online: online, name: 'U 盘 Ee')]);
      },
    );
    await cubit.load();
    await cubit.load();
    expect(reads, 1, reason: '同一节流窗口内轮询不重复打存储接口');
    expect(cubit.state.devices.single.online, isFalse);

    online = true;
    await cubit.refreshDeviceNames(force: true);
    expect(reads, 2);
    expect(cubit.state.devices.single.online, isTrue);
    await cubit.close();
  });

  testWidgets('v10-5 容量未就绪不显示 0 MB，改为正在读取设备容量', (tester) async {
    StorageDeviceSummary device({required int capacity, required int free}) => StorageDeviceSummary(
      mediaId: 'disk',
      displayName: 'U 盘 Ee',
      kind: 'usb_flash',
      kindConfidence: 'high',
      detail: '测试设备',
      capacityBytes: capacity,
      freeBytes: free,
      filesystem: 'exfat',
      label: 'disk',
      roleState: 'available',
      canBeSource: false,
      canBeTarget: true,
      targetBlockReasons: const [],
      identityConfidence: 'stable_uuid',
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StorageDeviceCard(device: device(capacity: 0, free: 0), role: '目标设备', selected: false, onTap: () {}))));
    expect(find.textContaining('正在读取设备容量'), findsOneWidget);
    expect(find.textContaining('0 MB'), findsNothing);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StorageDeviceCard(device: device(capacity: 2 * 1024 * 1024 * 1024, free: 1024 * 1024 * 1024), role: '目标设备', selected: false, onTap: () {}))));
    expect(find.textContaining('1.0 GB 可用 / 2.0 GB'), findsOneWidget);
    expect(find.textContaining('正在读取设备容量'), findsNothing);
  });
}
