import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 仅在断线或候选不完整时提示缓存结果的限制。
class GalleryCandidateNotice extends StatelessWidget {
  const GalleryCandidateNotice({
    super.key,
    required this.loadedCount,
    this.totalCount,
    required this.resultComplete,
    required this.offline,
    this.onReconnect,
    this.onRefresh,
  });

  final int loadedCount;
  final int? totalCount;
  final bool resultComplete;
  final bool offline;
  final VoidCallback? onReconnect;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!offline && resultComplete) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: _warningNotice());
  }

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
