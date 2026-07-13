import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:flutter/material.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, required this.onOpen});
  final BirdGroup group;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext c) => Card(
    child: ListTile(
      onTap: onOpen,
      leading: const Icon(Icons.collections_outlined),
      title: Text('${group.type} 组'),
      subtitle: Text('${group.memberFileIds.length} 张 · 推荐 ${group.rankOrder.length} 张'),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}
