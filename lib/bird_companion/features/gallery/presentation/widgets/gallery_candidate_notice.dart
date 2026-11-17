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
    this.album = false,
    this.fromCache = true,
    this.reconnecting = false,
    this.pendingSyncCount = 0,
  });

  final int loadedCount;
  final int? totalCount;
  final bool resultComplete;
  final bool offline;
  final VoidCallback? onReconnect;
  final VoidCallback? onRefresh;
  final bool album;
  final bool fromCache;
  final bool reconnecting;
  final int pendingSyncCount;

  @override
  Widget build(BuildContext context) {
    if (!offline && resultComplete) return const SizedBox.shrink();
    return Padding(padding: EdgeInsets.only(bottom: album ? 0 : 12), child: _warningNotice());
  }

  /// 断线或候选不完整：单行短警示，动作内联，避免额外一行按钮。
  Widget _warningNotice() {
    final action = offline ? reconnecting ? null : onReconnect : onRefresh;
    final count = totalCount == null ? '$loadedCount' : '$loadedCount/$totalCount';
    final message = album
        ? _albumMessage()
        : offline
        ? (resultComplete ? '设备未连接，当前为本机完整候选' : '设备未连接，仅本机 $count 张照片')
        : '候选不完整：仅本机 $count 张照片';
    return Container(
      key: const Key('gallery-candidate-notice'),
      margin: EdgeInsets.only(bottom: album ? 0 : 8),
      padding: album ? const EdgeInsets.fromLTRB(8, 0, 4, 0) : const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        border: Border.all(color: AppColors.danger.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            reconnecting ? Icons.sync_rounded : offline ? Icons.link_off_rounded : Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              key: const Key('gallery-candidate-notice-text'),
              maxLines: album ? null : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
          if (action != null)
            TextButton(
              key: const Key('gallery-candidate-notice-action'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: album ? MaterialTapTargetSize.padded : MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              onPressed: action,
              child: Text(offline ? '重新连接' : fromCache ? '刷新' : '重新筛选', style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  String _albumMessage() {
    if (!offline) return fromCache ? '缓存结果不完整，仅显示 $loadedCount 张照片' : '照片结果不完整';
    final connection = reconnecting ? '正在恢复盒子连接' : '盒子未连接';
    final photos = resultComplete
        ? fromCache ? '正在浏览手机缓存' : '正在浏览已加载照片'
        : fromCache
        ? '仅显示手机缓存的 $loadedCount 张照片'
        : '仅显示已加载的 $loadedCount 张照片';
    final pending = pendingSyncCount > 0 ? ' · $pendingSyncCount 项待同步' : '';
    return '$connection · $photos$pending';
  }
}

class AlbumOfflineEmptyState extends StatelessWidget {
  const AlbumOfflineEmptyState({
    super.key,
    required this.reconnecting,
    required this.onReconnect,
    this.onClearFilters,
  });

  final bool reconnecting;
  final VoidCallback onReconnect;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(reconnecting ? Icons.sync_rounded : Icons.link_off_rounded, size: 38, color: AppColors.inkMuted),
          const SizedBox(height: 8),
          Text(
            reconnecting
                ? '正在恢复盒子连接'
                : onClearFilters == null
                ? '盒子未连接，手机上暂无可浏览的照片'
                : '离线时没有符合当前条件的照片',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (!reconnecting) OutlinedButton(onPressed: onReconnect, child: const Text('重新连接')),
              if (onClearFilters != null) TextButton(onPressed: onClearFilters, child: const Text('清除筛选')),
            ],
          ),
        ],
      ),
    ),
  );
}
