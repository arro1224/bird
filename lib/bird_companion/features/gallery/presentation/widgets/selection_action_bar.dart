import 'package:flutter/material.dart';

class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({super.key, required this.count, required this.busy, required this.onAction, required this.onTags, required this.onClear});
  final int count;
  final bool busy;
  final ValueChanged<String> onAction;
  final VoidCallback onTags;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext c) => Material(
    color: Theme.of(c).colorScheme.primaryContainer,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(busy ? '正在处理 $count 张…' : '已选 $count 张'),
            TextButton(onPressed: busy ? null : () => onAction('keep'), child: const Text('保留')),
            TextButton(onPressed: busy ? null : () => onAction('discard'), child: const Text('弃用')),
            TextButton(onPressed: busy ? null : () => onAction('pending'), child: const Text('待确认')),
            TextButton(onPressed: busy ? null : () => onAction('featured'), child: const Text('精选')),
            IconButton(tooltip: '批量标签', onPressed: busy ? null : onTags, icon: const Icon(Icons.sell_outlined)),
            IconButton(onPressed: busy ? null : onClear, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    ),
  );
}
