import 'package:flutter/material.dart';

enum ConflictChoice { remote, local, cancel }

class ConflictDialog extends StatelessWidget {
  const ConflictDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('检测到版本冲突'),
    content: const Text('盒子端已有较新的修改。你可以采用盒子端结果，或以当前本地修改再次提交。'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, ConflictChoice.cancel), child: const Text('取消')),
      TextButton(onPressed: () => Navigator.pop(context, ConflictChoice.remote), child: const Text('采用盒子结果')),
      FilledButton(onPressed: () => Navigator.pop(context, ConflictChoice.local), child: const Text('保留本地修改')),
    ],
  );
}
