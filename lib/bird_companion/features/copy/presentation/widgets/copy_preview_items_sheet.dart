import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:flutter/material.dart';

/// 预检文件明细底部弹层（§10.2）。
///
/// 核心验收点：明细为空但预检统计有文件数时，必须渲染
/// Key `copy-preview-items-unavailable` 的琥珀色警告（预检明细暂不可用），
/// **不得**渲染成「暂无文件」的正常空态（联调 01 §三/审计 P0-3 预检明细防护）。
class CopyPreviewItemsSheet extends StatefulWidget {
  const CopyPreviewItemsSheet({
    super.key,
    required this.repository,
    required this.previewToken,
    required this.summaryFileCount,
  });

  final CopyJobRepository repository;
  final String previewToken;

  /// 预检统计中的实际文件数（CopyPreview.actualFileCount）。
  final int summaryFileCount;

  @override
  State<CopyPreviewItemsSheet> createState() => _CopyPreviewItemsSheetState();
}

class _CopyPreviewItemsSheetState extends State<CopyPreviewItemsSheet> {
  final List<CopyJobItem> _items = [];
  bool _loading = true;
  bool _hasMore = false;
  String? _cursor;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.previewItems(
        widget.previewToken,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailUnavailable = !_loading && _items.isEmpty && widget.summaryFileCount > 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '预检明细（${widget.summaryFileCount} 个文件）',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (detailUnavailable)
              // 验收 Key：明细不可用警告，不得显示成正常空态。
              Container(
                key: const Key('copy-preview-items-unavailable'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amberLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: .4)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '预检明细暂不可用，盒子未返回文件清单。这不影响任务创建，'
                        '复制结果以任务报告为准。',
                        style: TextStyle(color: AppColors.ink, fontSize: 13, height: 1.35),
                      ),
                    ),
                  ],
                ),
              )
            else if (!_loading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('暂无文件', style: TextStyle(color: AppColors.inkMuted))),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length + (_hasMore || _loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      if (_error != null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: TextButton(
                              onPressed: _loadPage,
                              child: const Text('加载失败，点击重试'),
                            ),
                          ),
                        );
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _hasMore) _loadPage();
                      });
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _ItemRow(item: _items[index]);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final CopyJobItem item;

  @override
  Widget build(BuildContext context) {
    final conflict = item.conflictDecision;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.sourceRelativePath ?? item.copyItemId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '→ ${item.targetPath ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.sourceSize != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatBytes(item.sourceSize!),
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ),
          if (conflict != null && conflict.isNotEmpty) ...[
            const SizedBox(width: 8),
            _ConflictBadge(decision: conflict),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge({required this.decision});

  final String decision;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (decision) {
      'skip' => ('跳过', AppColors.warning, AppColors.amberLight),
      'overwrite' => ('覆盖', AppColors.danger, AppColors.dangerSoft),
      'keep_both' => ('两份保留', AppColors.forestPrimary, AppColors.forestSoft),
      _ => (decision, AppColors.inkMuted, AppColors.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

Future<void> showCopyPreviewItemsSheet(
  BuildContext context, {
  required CopyJobRepository repository,
  required String previewToken,
  required int summaryFileCount,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
  ),
  builder: (_) => CopyPreviewItemsSheet(
    repository: repository,
    previewToken: previewToken,
    summaryFileCount: summaryFileCount,
  ),
);
