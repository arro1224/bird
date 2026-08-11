import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_home_capability_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B1 task-home capability resolver', () {
    test('keeps all writes closed before connected authority is ready', () {
      expect(
        _resolve(connected: false, authorityReady: true),
        isEmpty,
      );
      expect(
        _resolve(connected: true, authorityReady: false),
        isEmpty,
      );
    });

    test('uses status, current project and scan to expose valid entries', () {
      expect(
        _resolve(),
        [TaskType.importIndex, TaskType.aiAnalysis, TaskType.copy],
      );
      expect(
        _resolve(hasPendingOperations: true),
        [
          TaskType.importIndex,
          TaskType.aiAnalysis,
          TaskType.copy,
          TaskType.sync,
        ],
      );
    });

    test('active project pipeline prevents duplicate analysis and copy jobs', () {
      final analysis = BirdJobStatus(
        id: 'job-analysis-1',
        type: BirdJobType.analysis,
        state: BirdJobState.running,
        sourceProjectId: _project.id,
        availableActions: const ['pause', 'cancel'],
      );

      expect(
        _resolve(jobs: [analysis], hasPendingOperations: true),
        [TaskType.importIndex, TaskType.sync],
      );
    });

    test('retryable failure remains authoritative instead of creating a duplicate', () {
      final failed = BirdJobStatus(
        id: 'job-analysis-failed',
        type: BirdJobType.analysis,
        state: BirdJobState.failed,
        sourceProjectId: _project.id,
        availableActions: const ['retry_failed', 'skip_failed'],
      );

      expect(_resolve(jobs: [failed]), [TaskType.importIndex]);
    });

    test('scan in progress temporarily closes only the SD-card entry', () {
      expect(
        _resolve(
          currentScan: const CardScanResult(state: CardScanState.scanning),
        ),
        [TaskType.aiAnalysis, TaskType.copy],
      );
    });
  });
}

List<TaskType> _resolve({
  bool connected = true,
  bool authorityReady = true,
  bool hasPendingOperations = false,
  Iterable<BirdJobStatus> jobs = const [],
  CardScanResult currentScan = const CardScanResult(
    state: CardScanState.detected,
    cardId: 'card-1',
    photoCount: 24,
  ),
}) => TaskHomeCapabilityResolver.resolve(
  connected: connected,
  authorityReady: authorityReady,
  deviceStatus: _status,
  currentProject: _project,
  currentScan: currentScan,
  jobs: jobs,
  hasPendingOperations: hasPendingOperations,
);

final _status = DeviceStatus(
  connection: DeviceConnection(
    id: 'box-b1',
    name: 'B1 box',
    baseUri: Uri.parse('http://192.168.4.1:8080'),
    networkMode: NetworkMode.manual,
    apiVersion: 'v1',
    isPaired: true,
  ),
  card: const CardStatus(inserted: true, readable: true),
);

final _project = BatchSummary(
  id: 'project-b1',
  name: 'B1 project',
  createdAt: DateTime.utc(2026, 8, 10),
  totalFiles: 24,
  analyzedCount: 24,
  reviewCount: 3,
  keepCount: 12,
  discardCount: 9,
  pendingCopyCount: 12,
  copyState: 'pending',
);
