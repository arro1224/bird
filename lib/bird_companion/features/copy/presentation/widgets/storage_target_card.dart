import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:flutter/material.dart';

class StorageTargetCard extends StatelessWidget {
  const StorageTargetCard({super.key, required this.target, required this.selected, required this.onTap});
  final StorageTarget target;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => Card(
    child: RadioListTile(
      value: target.id,
      groupValue: selected ? target.id : null,
      onChanged: target.online ? (_) => onTap() : null,
      title: Text(target.name),
      subtitle: Text(target.online ? '可用空间 ${(target.freeBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB' : '未连接'),
    ),
  );
}
