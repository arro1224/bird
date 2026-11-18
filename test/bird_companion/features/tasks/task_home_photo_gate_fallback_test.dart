import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_home_capability_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：批次摘要 `total_files` 滞后时，「复制照片 / AI 分析」不能被误判成
/// 「当前批次没有可处理照片」。
///
/// 2026-11-18 真机：导入任务 60/60 完成，但 `/projects/current` 摘要的
/// total_files 仍为 0，任务首页两个入口被置灰，演示卡死。
void main() {
  DeviceStatus status() => DeviceStatus(
    connection: DeviceConnection(
      id: 'bbx-b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7',
      name: 'K7 mock',
      baseUri: Uri.parse('http://127.0.0.1:8787'),
      networkMode: NetworkMode.directAp,
      apiVersion: 'v1',
      isPaired: true,
    ),
    card: const CardStatus(inserted: true, readable: true),
  );

  BatchSummary project({required int totalFiles}) => BatchSummary(
    id: 'project-0001',
    name: '2026.11.18 拍摄批次',
    createdAt: DateTime.utc(2026, 11, 18),
    totalFiles: totalFiles,
    analyzedCount: totalFiles,
    reviewCount: 0,
    keepCount: 0,
    discardCount: 0,
    pendingCopyCount: 0,
    copyState: 'idle',
  );

  BirdJobStatus completedImport({required int totalCount}) => BirdJobStatus(
    id: 'job-import-0001',
    type: BirdJobType.import,
    state: BirdJobState.completed,
    totalCount: totalCount,
    finishedCount: totalCount,
    sourceProjectId: 'project-0001',
  );

  TaskHomeActionCapability capability(List<TaskHomeActionCapability> all, TaskType type) =>
      all.firstWhere((capability) => capability.type == type);

  List<TaskHomeActionCapability> resolve(BatchSummary batch, Iterable<BirdJobStatus> jobs) =>
      TaskHomeCapabilityResolver.resolveCapabilities(
        connected: true,
        authorityReady: true,
        deviceStatus: status(),
        currentProject: batch,
        currentScan: const CardScanResult(state: CardScanState.detected, cardId: 'card-mock-001', photoCount: 60),
        jobs: jobs,
        hasPendingOperations: false,
      );

  test('摘要 total_files=0 但导入已完成 60 张时，复制与分析入口都可用', () {
    final caps = resolve(project(totalFiles: 0), [completedImport(totalCount: 60)]);
    expect(capability(caps, TaskType.copy).enabled, isTrue);
    expect(capability(caps, TaskType.aiAnalysis).enabled, isTrue);
  });

  test('摘要与导入任务都无照片时，入口保持置灰并给出原因', () {
    final caps = resolve(project(totalFiles: 0), const []);
    expect(capability(caps, TaskType.copy).enabled, isFalse);
    expect(capability(caps, TaskType.copy).disabledReason, '当前批次没有可处理照片');
  });

  test('摘要正常回填 60 张时入口可用（不受兜底逻辑影响）', () {
    final caps = resolve(project(totalFiles: 60), const []);
    expect(capability(caps, TaskType.copy).enabled, isTrue);
    expect(capability(caps, TaskType.aiAnalysis).enabled, isTrue);
  });
}
