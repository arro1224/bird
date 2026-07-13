import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:flutter/material.dart';

class BatchListTile extends StatelessWidget {
  const BatchListTile({super.key, required this.batch, required this.onOpen, required this.onResume});
  final BatchSummary batch;
  final VoidCallback onOpen;
  final VoidCallback onResume;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onOpen,
      leading: const Icon(Icons.folder_copy_outlined),
      title: Text(batch.name),
      subtitle: Text('${batch.totalFiles} 张 · 已分析 ${batch.analyzedCount} · 待复核 ${batch.reviewCount}'),
      trailing: batch.copyState == 'incomplete' ? TextButton(onPressed: onResume, child: const Text('恢复')) : const Icon(Icons.chevron_right_rounded),
    ),
  );
}
