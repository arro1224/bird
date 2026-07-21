import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CacheManagementCard extends StatelessWidget {
  const CacheManagementCard({super.key, required this.onClear, required this.bytes});
  final VoidCallback? onClear;
  final int bytes;
  String get _size {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext c) => Card(
    child: ListTile(
      leading: const Icon(Icons.photo_library_outlined, color: AppColors.brand),
      title: const Text('手机上保存的照片'),
      subtitle: Text('当前约占用 $_size；清理后，设备断开时可能无法查看部分照片，但不会删除你做过的修改。'),
      trailing: TextButton(onPressed: onClear, child: const Text('清理')),
    ),
  );
}
