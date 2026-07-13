import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:flutter/material.dart';

class VersionHistoryPanel extends StatelessWidget {
  const VersionHistoryPanel({super.key, required this.items});
  final List<VersionHistory> items;
  @override
  Widget build(BuildContext c) => ExpansionTile(
    title: const Text('版本历史'),
    children: items.isEmpty ? [const ListTile(title: Text('暂无修改历史'))] : items.map((x) => ListTile(title: Text('v${x.version} · ${x.source}'), subtitle: Text(x.summary ?? ''))).toList(),
  );
}
