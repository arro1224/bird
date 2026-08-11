import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';

typedef JobFailurePageLoader = Future<JobFailurePage> Function(String? cursor);

class ProductionTaskResultPage extends StatelessWidget {
  const ProductionTaskResultPage({
    super.key,
    required this.report,
    this.failures = const [],
    this.initialFailurePage = const JobFailurePage.empty(),
    this.initialFailureError,
    this.loadFailurePage,
    this.onOpenAlbum,
  });

  final JobReport report;
  final List<JobFailure> failures;
  final JobFailurePage initialFailurePage;
  final Object? initialFailureError;
  final JobFailurePageLoader? loadFailurePage;
  final VoidCallback? onOpenAlbum;

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance(report.result);
    return TaskPageFrame(
      title: appearance.title,
      child: Column(
        children: [
          Icon(appearance.icon, size: 88, color: appearance.color),
          const SizedBox(height: 14),
          Text(
            appearance.headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.forestDeep,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            appearance.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 18),
          TaskSurface(
            child: Column(
              children: [
                _metric('复制照片', '${report.successCount} 张'),
                _metric('数据大小', _bytes(report.copiedBytes)),
                _metric('XMP 文件', '盒子未提供权威数量'),
                _metric('耗时', _duration(report), divider: false),
              ],
            ),
          ),
          if (report.skippedCount > 0) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.amberLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '有 ${report.skippedCount} 个文件待人工确认，请在报告中查看详情。',
                style: const TextStyle(color: AppColors.ink),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TaskActionButton(
            '查看复制报告',
            key: const Key('production-task-open-report'),
            onPressed: () => _showReport(context),
          ),
          if (onOpenAlbum != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onOpenAlbum,
                child: const Text('进入相册'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showReport(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (_) => ProductionTaskReportSheet(
      report: report,
      initialFailureError: initialFailureError,
      initialFailurePage: failures.isEmpty
          ? initialFailurePage
          : JobFailurePage(
              items: failures,
              hasMore: initialFailurePage.hasMore,
              nextCursor: initialFailurePage.nextCursor,
            ),
      loadFailurePage: loadFailurePage,
    ),
  );

  static Widget _metric(String label, String value, {bool divider = true}) => TaskMetricRow(
    label: label,
    value: value,
    divider: divider,
  );
}

class ProductionTaskReportSheet extends StatefulWidget {
  const ProductionTaskReportSheet({
    super.key,
    required this.report,
    this.initialFailurePage = const JobFailurePage.empty(),
    this.initialFailureError,
    this.loadFailurePage,
  });

  final JobReport report;
  final JobFailurePage initialFailurePage;
  final Object? initialFailureError;
  final JobFailurePageLoader? loadFailurePage;

  @override
  State<ProductionTaskReportSheet> createState() => _ProductionTaskReportSheetState();
}

class _ProductionTaskReportSheetState extends State<ProductionTaskReportSheet> {
  late final List<JobFailure> _failures = [
    ...widget.initialFailurePage.items,
  ];
  late bool _hasMore = widget.initialFailurePage.hasMore;
  late String? _nextCursor = widget.initialFailurePage.nextCursor;
  bool _loadingMore = false;
  late Object? _error = widget.initialFailureError;

  @override
  void initState() {
    super.initState();
    if (_error != null && widget.report.failedCount > 0 && widget.loadFailurePage != null) {
      _hasMore = true;
      _nextCursor = null;
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: ListView(
        key: const Key('production-task-report-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Text(
            '复制报告',
            style: TextStyle(
              color: AppColors.forestDeep,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.report.successCount} 个文件已复制，${widget.report.failedCount} 个失败',
            style: const TextStyle(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 14),
          TaskSurface(
            child: Column(
              children: [
                _sheetRow('总计', '${widget.report.totalCount}'),
                _sheetRow('成功', '${widget.report.successCount}'),
                _sheetRow('失败', '${widget.report.failedCount}'),
                _sheetRow('跳过', '${widget.report.skippedCount}'),
                _sheetRow('复制容量', _bytes(widget.report.copiedBytes)),
                _sheetRow('耗时', _duration(widget.report)),
                _sheetRow(
                  '清单 ID',
                  widget.report.manifestId?.trim().isNotEmpty == true ? widget.report.manifestId! : '盒子未提供',
                  divider: false,
                ),
              ],
            ),
          ),
          if (widget.report.failedCount > 0 || _failures.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              '失败文件',
              style: TextStyle(
                color: AppColors.forestDeep,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (_failures.isEmpty && !_hasMore)
              const Text('盒子未返回失败明细。')
            else
              for (final failure in _failures)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.danger,
                    ),
                    title: Text(failure.filename ?? failure.fileId),
                    subtitle: Text(
                      failure.filename == null ? failure.reason : '${failure.fileId}\n${failure.reason}',
                    ),
                  ),
                ),
            if (_error != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '失败明细加载失败，请重试。',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            if (_hasMore)
              Center(
                child: _loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      )
                    : TextButton.icon(
                        key: const Key('report-load-more-failures'),
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('加载更多失败项'),
                      ),
              ),
          ],
        ],
      ),
    ),
  );

  Future<void> _loadMore() async {
    final loader = widget.loadFailurePage;
    if (loader == null || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final requestedCursor = _nextCursor;
      final page = await loader(requestedCursor);
      if (!mounted) return;
      final known = _failures.map((failure) => failure.fileId).toSet();
      setState(() {
        _failures.addAll(page.items.where((item) => known.add(item.fileId)));
        _hasMore = page.hasMore && page.nextCursor != null && page.nextCursor != requestedCursor;
        _nextCursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Widget _sheetRow(String label, String value, {bool divider = true}) => TaskMetricRow(
    label: label,
    value: value,
    divider: divider,
  );
}

({String title, String headline, String subtitle, IconData icon, Color color}) _appearance(JobReportResult result) => switch (result) {
  JobReportResult.success => (
    title: '任务完成',
    headline: '照片复制完成',
    subtitle: '所有文件已校验通过',
    icon: Icons.check_circle_rounded,
    color: AppColors.success,
  ),
  JobReportResult.partialSuccess => (
    title: '任务完成',
    headline: '照片部分复制完成',
    subtitle: '部分文件需要处理',
    icon: Icons.warning_amber_rounded,
    color: AppColors.warning,
  ),
  JobReportResult.failed => (
    title: '任务失败',
    headline: '照片复制失败',
    subtitle: '请查看报告中的失败原因',
    icon: Icons.error_rounded,
    color: AppColors.danger,
  ),
  JobReportResult.cancelled => (
    title: '任务已取消',
    headline: '复制任务已取消',
    subtitle: '已复制的文件不会被删除',
    icon: Icons.block_rounded,
    color: AppColors.mutedInk,
  ),
  JobReportResult.unknown => (
    title: '任务结果',
    headline: '复制结果待确认',
    subtitle: '请查看盒子返回的复制报告',
    icon: Icons.info_rounded,
    color: AppColors.forestPrimary,
  ),
};

String _bytes(int? value) {
  if (value == null) return '盒子未提供';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var amount = value.toDouble();
  var unit = 0;
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024;
    unit++;
  }
  return '${amount.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _duration(JobReport report) {
  final started = report.startedAt;
  final finished = report.finishedAt;
  if (started == null || finished == null || finished.isBefore(started)) {
    return '盒子未提供';
  }
  final duration = finished.difference(started);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes == 0 ? '$seconds 秒' : '$minutes 分 $seconds 秒';
}
