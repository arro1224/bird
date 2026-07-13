import 'package:flutter/material.dart';

class BatchResumeDialog extends StatelessWidget {
  const BatchResumeDialog({super.key, required this.onConfirm});
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('恢复未完成批次？'),
    content: const Text('盒子会从上一个安全检查点继续导入、分析或复制。'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: () {
          Navigator.pop(context);
          onConfirm();
        },
        child: const Text('恢复'),
      ),
    ],
  );
}
