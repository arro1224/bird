import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CacheManagementCard extends StatelessWidget {
  const CacheManagementCard({
    super.key,
    required this.onClearImages,
    required this.onClearAlbumData,
    required this.imageBytes,
    required this.albumBytes,
  });
  final VoidCallback? onClearImages;
  final VoidCallback? onClearAlbumData;
  final int imageBytes;
  final int albumBytes;

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        children: [
          _CacheRow(
            icon: Icons.image_outlined,
            title: '照片预览缓存',
            subtitle: '${_size(imageBytes)} · 清理后会在浏览时重新加载图片',
            onClear: onClearImages,
          ),
          const Divider(height: 18),
          _CacheRow(
            icon: Icons.dataset_outlined,
            title: '相册离线信息',
            subtitle: '${_size(albumBytes)} · 已访问分页、筛选和详情摘要',
            onClear: onClearAlbumData,
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '待同步修改单独保存，不会被以上清理操作删除。',
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: AppColors.brand),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      TextButton(onPressed: onClear, child: const Text('清理')),
    ],
  );
}
