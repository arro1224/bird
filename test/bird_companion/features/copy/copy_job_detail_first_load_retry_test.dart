import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/pages/copy_job_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 返修 P0-2（2026-10-22 现场反馈）：复制运行期间首次任务详情反复超时。
///
/// 现场：12 文件任务运行 47.74s，App 首次详情连续三次「连接超时」，手动
/// 重试也不进运行态详情，任务完成后首次成功直接 100%。根因：detail==null
/// （首载失败）时 `_pollEnabled ?? true` 让轮询定时器根本不启动，页面只剩
/// 手动重试。
///
/// 修复：首载失败页自动退避轮询同一 job_id（2s 起、倍增、上限 15s），
/// 「重试」只 GET 原任务不重新提交。实机造不出瞬时失败组合
/// （负向路径只能注入 fake，见 10-14 走查教训），在此用注入失败的
/// fake 仓储验证。
void main() {
  testWidgets('明确 404 停止自动轮询，保留列表入口及手动 GET 重试', (tester) async {
    final repository = _MissingJobRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(copyJobId: 'job-1', repository: repository),
      ),
    );
    await tester.pump();
    expect(find.text('任务已不存在或已被清理'), findsOneWidget);
    expect(find.text('查看复制任务列表'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(repository.getJobCalls, 1);
    repository.missing = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repository.getJobCalls, 2);
    expect(find.text('任务已不存在或已被清理'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('每次失败经历 loading 重建后退避仍累积，并在后台停止', (tester) async {
    final repository = _DelayedFailureRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: CopyJobDetailPage(copyJobId: 'job-1', repository: repository),
      ),
    );
    expect(repository.getJobCalls, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    expect(repository.getJobCalls, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    expect(repository.getJobCalls, 2, reason: '组件重建后第二次仍等待完整 4 秒');
    await tester.pump(const Duration(seconds: 2));
    expect(repository.getJobCalls, 3);
    await tester.pump(const Duration(milliseconds: 500));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(repository.getJobCalls, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repository.getJobCalls, 4);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 14));
    expect(repository.getJobCalls, 4);
    await tester.pump(const Duration(seconds: 1));
    expect(repository.getJobCalls, 5);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首载失败后自动退避轮询；任务可读时自动进入详情页', (tester) async {
    final repository = _FirstLoadFakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CopyJobDetailPage(
            copyJobId: 'job-1',
            repository: repository,
            createdJob: const CopyJobSummary(copyJobId: 'job-1', state: 'queued', eventSeq: 0),
          ),
        ),
      ),
    );
    await tester.pump();

    // 首载失败：错误页出现（StateError 不含内部细节映射，走通用文案）。
    expect(find.text('任务不存在'), findsNothing); // error 非 null，不走「任务不存在」
    expect(find.textContaining('任务已创建；创建时状态：'), findsOneWidget);
    expect(find.text('盒子上的任务可能仍在继续，将自动重试读取进度；也可手动重试。'), findsOneWidget);
    expect(repository.getJobCalls, 1);

    // 退避 2s 第一跳：仍失败。
    await tester.pump(const Duration(seconds: 2));
    expect(repository.getJobCalls, 2);

    // 退避倍增：4s 后第二跳（中间 2~4s 不应多跳）。
    await tester.pump(const Duration(seconds: 2));
    expect(repository.getJobCalls, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(repository.getJobCalls, 3);

    // 恢复可读：下一跳成功 → 自动进入详情页，不再停留错误页。
    repository.fail = false;
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(repository.getJobCalls, 4);
    expect(find.text('复制任务详情'), findsOneWidget);
    expect(find.text('盒子上的任务可能仍在继续，将自动重试读取进度；也可手动重试。'), findsNothing);
    // 运行态任务的动作区按 allowed_actions 渲染（fake 返回空，仅验证进入详情）。
  });

  testWidgets('瞬时不可读保留自动重试，随后可读时自动恢复', (tester) async {
    final repository = _NotFoundFakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CopyJobDetailPage(copyJobId: 'job-1', repository: repository),
        ),
      ),
    );
    await tester.pump();

    // error 非空（fake 抛 StateError）→ 用户消息映射后的标题 + 自动轮询提示。
    expect(find.text('操作未完成'), findsOneWidget);
    expect(find.text('盒子上的任务可能仍在继续，将自动重试读取进度；也可手动重试。'), findsOneWidget);
    expect(repository.getJobCalls, 1);

    // 任务后续在盒子上出现（如创建请求实际已送达）→ 自动恢复。
    repository.appear = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('操作未完成'), findsNothing);
    expect(find.text('复制任务详情'), findsOneWidget);
  });
}

class _FirstLoadFakeRepository implements CopyJobRepository {
  bool fail = true;
  int getJobCalls = 0;

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [CopyScope.batchAllAssets],
    recognitionPolicyVersion: 'recognized-assets-v1',
  );

  @override
  Future<CopyJobPage> listJobs({String? cursor}) async => const CopyJobPage(items: [], hasMore: false);

  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    getJobCalls++;
    if (fail) {
      throw StateError('first load timed out');
    }
    return _runningDetail();
  }

  @override
  Future<CopyJobEventPage> jobEvents(String copyJobId, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);

  @override
  Future<CopyReport> jobReport(String copyJobId) async => const CopyReport();

  @override
  Future<CopyJobItemPage> jobItems(String copyJobId, {String? cursor, String? state}) async => const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<CopyJobDetail?> jobAction(
    String copyJobId,
    String actionWire, {
    required int expectedStateVersion,
  }) async => null;

  @override
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) async => const CopyJobItemPage(items: [], hasMore: false);

  @override
  Future<SafeRemoveResult> safeRemoveDevice(
    String mediaId, {
    required String role,
    String? expectedCopyJobId,
  }) async => const SafeRemoveResult(safeToRemove: true);
}

class _NotFoundFakeRepository extends _FirstLoadFakeRepository {
  bool appear = false;

  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    getJobCalls++;
    if (!appear) {
      throw StateError('job not found');
    }
    return _runningDetail();
  }
}

class _DelayedFailureRepository extends _FirstLoadFakeRepository {
  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    getJobCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    throw StateError('delayed failure');
  }
}

class _MissingJobRepository extends _FirstLoadFakeRepository {
  bool missing = true;
  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    getJobCalls++;
    if (missing) throw const ApiException(message: 'not found', statusCode: 404);
    return _runningDetail();
  }
}

CopyJobDetail _runningDetail() => const CopyJobDetail(
  copyJobId: 'job-1',
  state: CopyJobState.running,
  stateVersion: 1,
  eventSeq: 0,
  allowedActions: [],
  stats: CopyJobStats(
    totalFiles: 12,
    copiedFiles: 3,
    failedFiles: 0,
    skippedFiles: 0,
    notApplicableFiles: 0,
    totalBytes: 663470080,
    copiedBytes: 0,
    elapsedSeconds: 10,
  ),
);
