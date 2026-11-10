import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 候选筛选来源提示（v10 返修问题 13）。
///
/// 在线且结果完整时只是"用完整候选数据在本机筛选"，不是离线缓存；
/// 只有真断线或结果不完整才用红色警示。在线时不再提供语义不符的
/// "重新连接"，改为"刷新候选数据"。
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
  Widget build(BuildContext context) {
    final savedAt = cachedAt == null ? '' : ' · 保存于 ${_time(cachedAt!)}';
    final message = offline
        ? '设备暂时无法连接；${_completeness()}$savedAt'
        : resultComplete
        ? '已使用完整候选数据在本机筛选$savedAt'
        : '${_completeness()}$savedAt';
    final color = _warning ? AppColors.danger : AppColors.brand;
    final background = _warning ? AppColors.dangerSoft : AppColors.brandSoft;
    final action = offline ? onReconnect : onRefresh;
    return Container(
      key: const Key('gallery-candidate-notice'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(_icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  key: const Key('gallery-candidate-notice-text'),
                  style: TextStyle(color: color),
                ),
              ),
            ],
          ),
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('gallery-candidate-notice-action'),
                onPressed: action,
                child: Text(offline ? '重新连接' : '刷新候选数据'),
              ),
            ),
        ],
      ),
    );
  }

  IconData get _icon {
    if (offline) return Icons.link_off_rounded;
    if (!resultComplete) return Icons.warning_amber_rounded;
    return Icons.filter_alt_outlined;
  }

  String _completeness() {
    if (resultComplete) return '已使用完整候选缓存筛选';
    if (totalCount == null) return '仅在已缓存照片中查找，结果可能不完整';
    return '仅在已缓存的 $loadedCount / $totalCount 张照片中查找，结果可能不完整';
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
