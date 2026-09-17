import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/data/mock_copy_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// MockCopyRepository RC3 状态机冻结测试（阶段 D 批次 3）。
///
/// 注入可变 clock 做确定性断言；惰性时间推进由仓库读写驱动。
void main() {
  const draft = CopyRequestDraft(
    batchId: 'batch-1',
    scope: CopyScope.keptAssets,
    sourceMediaId: 'media_2d6dee77bb5ecc73e3d34787',
    targetMediaId: 'media_7f9a76e6c97690b61aedf6fd',
    reviewExport: ReviewExportConfig.disabled(),
    conflictStrategy: ConflictStrategy.skip,
  );

  test('全状态序列：queued→acquiring_target→running→completed_with_errors', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job = await repo.createJob(draft, preview.previewToken);

    final states = <String>[];
    CopyJobDetail detail;
    while (true) {
      detail = await repo.getJob(job.copyJobId);
      if (states.isEmpty || states.last != detail.state.wire) {
        states.add(detail.state.wire);
      }
      if (detail.state.isTerminal) break;
      now = now.add(const Duration(milliseconds: 500));
      if (now.isAfter(DateTime(2026, 9, 17, 10, 1))) {
        fail('任务未在预期时间内到达终态');
      }
    }
    expect(states, [
      'queued',
      'acquiring_target',
      'running',
      'completed_with_errors',
    ]);
    // 固定 2 项：1 成功 1 校验失败。
    expect(detail.stats!.totalFiles, 2);
    expect(detail.stats!.copiedFiles, 1);
    expect(detail.stats!.failedFiles, 1);
    // 终态报告可取且部分成功。
    final report = await repo.jobReport(job.copyJobId);
    expect(report.isPartialSuccess, isTrue);
    expect(report.failedFiles, 1);
  });

  test('pause→paused→resume 后任务继续推进', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job = await repo.createJob(draft, preview.previewToken);

    now = now.add(const Duration(seconds: 3)); // → running
    var detail = await repo.getJob(job.copyJobId);
    expect(detail.state, CopyJobState.running);
    expect(
      detail.allowedActions.map((action) => action.wire),
      containsAll(['pause', 'cancel']),
    );

    // 版本不匹配 → 409 COPY_STATE_VERSION_CONFLICT。
    await expectLater(
      repo.jobAction(job.copyJobId, 'pause', expectedStateVersion: detail.stateVersion + 5),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'COPY_STATE_VERSION_CONFLICT',
        ),
      ),
    );

    await repo.jobAction(job.copyJobId, 'pause', expectedStateVersion: detail.stateVersion);
    now = now.add(const Duration(milliseconds: 900));
    detail = await repo.getJob(job.copyJobId);
    expect(detail.state, CopyJobState.paused);
    expect(
      detail.allowedActions.map((action) => action.wire),
      containsAll(['resume', 'cancel']),
    );

    // 暂停期间时间推进不产生文件进度。
    final pausedCopied = detail.stats!.copiedFiles;
    now = now.add(const Duration(seconds: 10));
    detail = await repo.getJob(job.copyJobId);
    expect(detail.state, CopyJobState.paused);
    expect(detail.stats!.copiedFiles, pausedCopied);

    await repo.jobAction(job.copyJobId, 'resume', expectedStateVersion: detail.stateVersion);
    now = now.add(const Duration(seconds: 30));
    detail = await repo.getJob(job.copyJobId);
    expect(detail.state.isTerminal, isTrue);
  });

  test('cancel → cancelled 终态，报告不可取之外状态 409', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job = await repo.createJob(draft, preview.previewToken);

    // 非终态报告 → 409。
    await expectLater(
      repo.jobReport(job.copyJobId),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 409),
      ),
    );

    now = now.add(const Duration(seconds: 3));
    final detail = await repo.getJob(job.copyJobId);
    await repo.jobAction(job.copyJobId, 'cancel', expectedStateVersion: detail.stateVersion);
    now = now.add(const Duration(seconds: 1));
    final cancelled = await repo.getJob(job.copyJobId);
    expect(cancelled.state, CopyJobState.cancelled);
    expect(
      cancelled.allowedActions.map((action) => action.wire),
      ['safe_remove_target'],
    );
  });

  test('retry_failed 重置失败项并继续到再次部分完成', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job = await repo.createJob(draft, preview.previewToken);

    now = now.add(const Duration(seconds: 10));
    var detail = await repo.getJob(job.copyJobId);
    expect(detail.state, CopyJobState.completedWithErrors);
    expect(
      detail.allowedActions.map((action) => action.wire),
      ['retry_failed'],
    );

    await repo.jobAction(job.copyJobId, 'retry_failed', expectedStateVersion: detail.stateVersion);
    now = now.add(const Duration(seconds: 10));
    detail = await repo.getJob(job.copyJobId);
    // mock 固定失败语义：重试后第 2 项再次校验失败。
    expect(detail.state, CopyJobState.completedWithErrors);
    expect(detail.stats!.failedFiles, 1);
  });

  test('items failed 过滤 + cursor 分页不去重', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job = await repo.createJob(draft, preview.previewToken);
    now = now.add(const Duration(seconds: 10));
    await repo.getJob(job.copyJobId);

    final failed = await repo.jobItems(job.copyJobId, state: 'failed');
    expect(failed.items, hasLength(1));
    expect(failed.items.single.state, CopyItemState.failed);
    expect(failed.hasMore, isFalse);

    final allPage1 = await repo.jobItems(job.copyJobId);
    expect(allPage1.items, hasLength(2));
    expect(allPage1.hasMore, isFalse);

    // 预检明细分页：67 文件 → 第 1 页 20 条，cursor 推进不去重、不重叠。
    final previewPage1 = await repo.previewItems(preview.previewToken);
    expect(previewPage1.items, hasLength(20));
    expect(previewPage1.hasMore, isTrue);
    final previewPage2 = await repo.previewItems(preview.previewToken, cursor: previewPage1.nextCursor);
    expect(previewPage2.items, hasLength(20));
    expect(previewPage2.items.first.copyItemId, isNot(previewPage1.items.first.copyItemId));
    final previewPage4 = await repo.previewItems(preview.previewToken, cursor: '60');
    expect(previewPage4.items, hasLength(7));
    expect(previewPage4.hasMore, isFalse);
    // 冲突项带 skip 决策（§10.2 预检明细）。
    expect(
      previewPage1.items.map((item) => item.conflictDecision),
      contains('skip'),
    );
  });

  test('events 增量拉取（after_seq）', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job = await repo.createJob(draft, preview.previewToken);

    final all = await repo.jobEvents(job.copyJobId);
    expect(all.events, isNotEmpty);
    expect(all.events.first.seq, 1);

    now = now.add(const Duration(seconds: 10));
    await repo.getJob(job.copyJobId);
    final finalAll = await repo.jobEvents(job.copyJobId);
    final incremental = await repo.jobEvents(job.copyJobId, afterSeq: all.events.last.seq);
    expect(incremental.events, finalAll.events.where((e) => e.seq! > all.events.last.seq!));
  });

  test('safeRemoveDevice：任务占用时拒绝，空闲时放行（保持期 60s）', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job = await repo.createJob(draft, preview.previewToken);

    // 源设备被进行中的任务占用。
    now = now.add(const Duration(seconds: 3));
    await repo.getJob(job.copyJobId);
    final busy = await repo.safeRemoveDevice(
      'media_2d6dee77bb5ecc73e3d34787',
      role: 'source',
    );
    expect(busy.safeToRemove, isFalse);
    expect(busy.reason, isNotNull);

    // 终态后空闲。
    now = now.add(const Duration(seconds: 30));
    await repo.getJob(job.copyJobId);
    final free = await repo.safeRemoveDevice(
      'media_7f9a76e6c97690b61aedf6fd',
      role: 'target',
      expectedCopyJobId: job.copyJobId,
    );
    expect(free.safeToRemove, isTrue);
    expect(free.keepUntil, isNotNull);
  });

  test('listJobs 按 createdAt 倒序分页', () async {
    var now = DateTime(2026, 9, 17, 10);
    final repo = MockCopyRepository(clock: () => now);
    final preview = await repo.preview(draft);
    final job1 = await repo.createJob(draft, preview.previewToken);
    now = now.add(const Duration(seconds: 1));
    final preview2 = await repo.preview(draft);
    final job2 = await repo.createJob(draft, preview2.previewToken);

    final page = await repo.listJobs();
    expect(page.hasMore, isFalse);
    expect(page.items.map((item) => item.copyJobId), [job2.copyJobId, job1.copyJobId]);
    expect(page.items.first.state.isTerminal, isFalse);
  });

  test('fullBackupAvailable=false：预检 COPY_SCOPE_UNSUPPORTED（镜像真实后端）', () async {
    final repo = MockCopyRepository(fullBackupAvailable: false);
    const backupDraft = CopyRequestDraft(
      batchId: 'batch-1',
      scope: CopyScope.mediaFullBackup,
      sourceMediaId: 'media_2d6dee77bb5ecc73e3d34787',
      targetMediaId: 'media_7f9a76e6c97690b61aedf6fd',
      reviewExport: ReviewExportConfig.disabled(),
      conflictStrategy: ConflictStrategy.skip,
    );
    await expectLater(
      repo.preview(backupDraft),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'COPY_SCOPE_UNSUPPORTED')
            .having((error) => error.statusCode, 'status', 422),
      ),
    );
  });
}
