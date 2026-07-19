import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:flutter/material.dart';

class VersionHistoryPage extends StatelessWidget {
  const VersionHistoryPage({super.key, required this.items});
  final List<VersionHistory> items;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.brand,
    appBar: AppBar(title: const Text('版本历史')),
    body: BirdDarkTheme(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('版本历史', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          if (items.isEmpty)
            const Card(
              child: ListTile(leading: Icon(Icons.history_rounded), title: Text('暂无修改历史')),
            ),
          for (var index = 0; index < items.length; index++) _HistoryItem(index: index + 1, item: items[index]),
        ],
      ),
    ),
  );
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.index, required this.item});
  final int index;
  final VersionHistory item;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 44,
          child: Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.amber,
                child: Text(
                  '$index',
                  style: const TextStyle(color: AppColors.brandDark, fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(child: Container(width: 2, color: AppColors.amberSoft)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text('v${item.version} · ${item.source}', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${item.summary ?? '人工修改'}\n${_time(item.updatedAt)}'),
            ),
          ),
        ),
      ],
    ),
  );
  String _time(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}
