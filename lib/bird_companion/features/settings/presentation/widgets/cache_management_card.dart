import 'package:flutter/material.dart';

class CacheManagementCard extends StatelessWidget {
  const CacheManagementCard({super.key, required this.onClear, required this.bytes});
  final VoidCallback onClear;
  final int bytes;
  @override
  Widget build(BuildContext c) => Card(
    child: ListTile(
      title: const Text('缩略图缓存'),
      subtitle: Text('当前本地缓存约 ${(bytes / 1024).toStringAsFixed(1)} KB；清理缩略图不会删除待同步的人工修改。'),
      trailing: TextButton(onPressed: onClear, child: const Text('清理')),
    ),
  );
}
