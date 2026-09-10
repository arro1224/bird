import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_entry_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('album copy entry guard', () {
    test('blocks a retained album after the current project changes', () {
      final decision = resolveCurrentCopyEntry(
        displayedBatchId: 'project-old',
        currentProject: _batch('project-new', totalFiles: 0),
        jobs: const [],
      );

      expect(decision.enabled, isFalse);
      expect(decision.reason, contains('当前批次已更新'));
    });

    test('blocks a zero-photo current project', () {
      final decision = resolveCurrentCopyEntry(
        displayedBatchId: 'project-new',
        currentProject: _batch('project-new', totalFiles: 0),
        jobs: const [],
      );

      expect(decision.enabled, isFalse);
      expect(decision.reason, '当前批次没有可复制的照片');
    });

    test('allows copy while the current project import or analysis is running', () {
      final decision = resolveCurrentCopyEntry(
        displayedBatchId: 'project-new',
        currentProject: _batch('project-new', totalFiles: 60),
        jobs: const [
          BirdJobStatus(
            id: 'job-import-1',
            type: BirdJobType.import,
            state: BirdJobState.running,
            sourceProjectId: 'project-new',
          ),
          BirdJobStatus(
            id: 'job-analysis-1',
            type: BirdJobType.analysis,
            state: BirdJobState.running,
            sourceProjectId: 'project-new',
          ),
        ],
      );

      // 分析/导入不阻止复制（迁移对照文档 §3.1）。
      expect(decision.enabled, isTrue);
      expect(decision.batchId, 'project-new');
    });

    test('blocks copy while another target-write job is using the target device', () {
      final decision = resolveCurrentCopyEntry(
        displayedBatchId: 'project-new',
        currentProject: _batch('project-new', totalFiles: 60),
        jobs: const [
          BirdJobStatus(
            id: 'job-copy-1',
            type: BirdJobType.copy,
            state: BirdJobState.running,
            sourceProjectId: 'project-new',
          ),
        ],
      );

      expect(decision.enabled, isFalse);
      expect(decision.reason, '已有复制/备份任务正在使用目标设备');
    });

    test('allows the authoritative idle project with photos', () {
      final decision = resolveCurrentCopyEntry(
        displayedBatchId: 'project-new',
        currentProject: _batch('project-new', totalFiles: 60),
        jobs: const [
          BirdJobStatus(
            id: 'job-import-1',
            type: BirdJobType.import,
            state: BirdJobState.completed,
            sourceProjectId: 'project-new',
          ),
        ],
      );

      expect(decision.enabled, isTrue);
      expect(decision.batchId, 'project-new');
    });
  });
}

BatchSummary _batch(String id, {required int totalFiles}) => BatchSummary(
  id: id,
  name: id,
  createdAt: DateTime.utc(2026, 8, 10),
  totalFiles: totalFiles,
  analyzedCount: 0,
  reviewCount: 0,
  keepCount: 0,
  discardCount: 0,
  pendingCopyCount: 0,
  copyState: 'idle',
);
