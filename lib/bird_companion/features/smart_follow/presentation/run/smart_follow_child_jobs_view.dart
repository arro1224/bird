import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter/material.dart';

/// 子复制任务列表（分工任务书 R2）。
///
/// child CopyJob 清单创建后不可变（联合 §1/§6.6），所以这里只做"分页浏览 +
/// 跳 RC3 详情"，**不提供任何修改清单的操作**。
class SmartFollowChildJobsView extends StatefulWidget {
  const SmartFollowChildJobsView({
    super.key,
    required this.repository,
    required this.sessionId,
    this.pageSize = 20,
    this.onOpenCopyJob,
  });

  final SmartFollowRepository repository;
  final String sessionId;
  final int pageSize;
  final ValueChanged<String>? onOpenCopyJob;

  @override
  State<SmartFollowChildJobsView> createState() => _SmartFollowChildJobsViewState();
}

class _SmartFollowChildJobsViewState extends State<SmartFollowChildJobsView> {
  final List<SmartFollowChildJob> _items = [];
  final Set<String> _seen = {};
  String? _nextCursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.childJobs(widget.sessionId, pageSize: widget.pageSize);
      if (!mounted) return;
      setState(() {
        _append(page);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.childJobs(widget.sessionId, cursor: cursor, pageSize: widget.pageSize);
      if (!mounted) return;
      setState(() {
        _append(page);
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = error;
      });
    }
  }

  /// 分页重叠时按 `copy_job_id` 去重：重复追加会让用户以为多了一批。
  void _append(SmartFollowChildJobPage page) {
    for (final job in page.items) {
      if (_seen.add(job.copyJobId)) _items.add(job);
    }
    _hasMore = page.hasMore && page.nextCursor != null && page.nextCursor != _nextCursor;
    _nextCursor = page.nextCursor;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final error = _error;
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error == null ? '还没有创建复制批次' : UserMessageMapper.fromError(error).message, textAlign: TextAlign.center),
            if (error != null) TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('已加载 ${_items.length} 批 · 每批清单创建后不再变化', style: const TextStyle(color: AppColors.mutedInk)),
        ),
        for (final job in _items) _ChildJobTile(job: job, onOpen: widget.onOpenCopyJob),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton(
              key: const Key('smart-follow-child-jobs-more'),
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(_loadingMore ? '加载中…' : '加载更多'),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(UserMessageMapper.fromError(error).message, textAlign: TextAlign.center),
          ),
      ],
    );
  }
}

class _ChildJobTile extends StatelessWidget {
  const _ChildJobTile({required this.job, this.onOpen});

  final SmartFollowChildJob job;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final done = job.state.isTerminal;
    return ListTile(
      key: Key('smart-follow-child-job-${job.copyJobId}'),
      leading: Icon(done ? Icons.check_circle_outline : Icons.sync, color: done ? AppColors.forestDeep : AppColors.mutedInk),
      title: Text(job.index > 0 ? '第 ${job.index} 批' : '复制批次'),
      subtitle: Text('${job.assetCount} 张照片 · ${job.fileCount} 个文件 · ${job.state.label}'),
      trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
      onTap: onOpen == null ? null : () => onOpen!(job.copyJobId),
    );
  }
}

/// 底部弹层形式（运行页"复制批次"卡片的默认落地方式）。
Future<void> showSmartFollowChildJobsSheet(
  BuildContext context, {
  required SmartFollowRepository repository,
  required String sessionId,
  ValueChanged<String>? onOpenCopyJob,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => SafeArea(
    child: SmartFollowChildJobsView(
      repository: repository,
      sessionId: sessionId,
      onOpenCopyJob: (copyJobId) {
        Navigator.pop(context);
        onOpenCopyJob?.call(copyJobId);
      },
    ),
  ),
);

/// 完成页/运行页共用的"批次状态"文案（避免各处自造说法）。
String describeChildJobState(CopyJobState state) => state.label;
