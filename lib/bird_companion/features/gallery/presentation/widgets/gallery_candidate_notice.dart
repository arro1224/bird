import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 候选筛选来源提示（v10 返修问题 13）。
///
/// 「识别结果/评分/标签」这类条件由 App 在本机对候选集合筛选，因此只要该
/// 筛选生效，就会走本机候选（`GalleryState.fromCache`）。这是正常路径，
/// 不是断线：
/// - 在线且候选完整：只留一行低对比度说明，不占版面、不显示"重新连接"；
/// - 在线但候选不完整：短警示 + "刷新"，避免把缓存结果当完整结果；
/// - 真断线：短警示 + "重新连接"（此时该操作才有意义）。
class GalleryCandidateNotice extends StatelessWidget {
  const GalleryCandidateNotice({
    super.key,
    this.cachedAt,
    required this.loadedCount,
    this.totalCount,
    required this.resultComplete,
    required this.offline,
    this.onReconnect,
    this.onRefresh,
  });

  final DateTime? cachedAt;
  final int loadedCount;
  final int? totalCount;
  final bool resultComplete;
  final bool offline;
  final VoidCallback? onReconnect;
  final VoidCallback? onRefresh;

  bool get _warning => offline || !resultComplete;

  @override
  Widget build(BuildContext context) => _warning ? _warningNotice() : _inlineHint();

  /// 在线完整候选：一行灰字，不再用大色块占界面。
  Widget _inlineHint() => const Padding(
    key: Key('gallery-candidate-notice'),
    padding: EdgeInsets.fromLTRB(16, 2, 16, 2),
    child: Row(
      children: [
        Icon(Icons.filter_alt_outlined, size: 14, color: AppColors.inkMuted),
        SizedBox(width: 5),
        Expanded(
          child: Text(
            '已使用完整候选数据在本机筛选',
            key: Key('gallery-candidate-notice-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
          ),
        ),
      ],
    ),
  );

  /// 断线或候选不完整：单行短警示，动作内联，避免额外一行按钮。
  Widget _warningNotice() {
    final action = offline ? onReconnect : onRefresh;
    final count = totalCount == null ? '$loadedCount' : '$loadedCount/$totalCount';
    final message = offline
        ? (resultComplete ? '设备未连接，当前为本机完整候选' : '设备未连接，仅本机 $count 张照片')
        : '候选不完整：仅本机 $count 张照片';
    return Container(
      key: const Key('gallery-candidate-notice'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        border: Border.all(color: AppColors.danger.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(offline ? Icons.link_off_rounded : Icons.warning_amber_rounded, size: 18, color: AppColors.danger),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              key: const Key('gallery-candidate-notice-text'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
          if (action != null)
            TextButton(
              key: const Key('gallery-candidate-notice-action'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              onPressed: action,
              child: Text(offline ? '重新连接' : '刷新', style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
