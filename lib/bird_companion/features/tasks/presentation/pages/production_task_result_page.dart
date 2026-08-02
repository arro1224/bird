import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';

class ProductionTaskResultPage extends StatelessWidget {
  const ProductionTaskResultPage({
    super.key,
    required this.report,
    this.failures = const [],
    this.onOpenAlbum,
  });

  final JobReport report;
  final List<JobFailure> failures;
  final VoidCallback? onOpenAlbum;

  @override
  Widget build(BuildContext context) => TaskPageFrame(
    title: '任务报告',
    child: Column(
      children: [
        Icon(
          report.failedCount == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          size: 88,
          color: report.failedCount == 0 ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(height: 14),
        Text(
          _resultLabel(report.result),
          style: const TextStyle(
            color: AppColors.forestDeep,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        TaskSurface(
          child: Column(
            children: [
              _row('总计', report.totalCount),
              _row('成功', report.successCount),
              _row('失败', report.failedCount),
              _row('跳过', report.skippedCount, divider: false),
            ],
          ),
        ),
        if (failures.isNotEmpty) ...[
          const SizedBox(height: 16),
          TaskSurface(
            child: ExpansionTile(
              key: const Key('task-report-failures'),
              title: Text('失败项 ${failures.length}'),
              children: [
                for (final failure in failures)
                  ListTile(
                    title: Text(failure.fileId),
                    subtitle: Text(failure.reason),
                  ),
              ],
            ),
          ),
        ],
        if (onOpenAlbum != null) ...[
          const SizedBox(height: 16),
          TaskActionButton('进入相册', onPressed: onOpenAlbum!),
        ],
      ],
    ),
  );

  Widget _row(String label, int value, {bool divider = true}) => Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Text(
          '$value',
          style: const TextStyle(
            color: AppColors.forestPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );

  String _resultLabel(JobReportResult result) => switch (result) {
    JobReportResult.success => '任务已完成',
    JobReportResult.partialSuccess => '任务部分完成',
    JobReportResult.failed => '任务失败',
    JobReportResult.cancelled => '任务已取消',
    JobReportResult.unknown => '任务结果',
  };
}
