import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:flutter/material.dart';

class VersionHistoryPage extends StatelessWidget {
  const VersionHistoryPage({super.key, required this.items});
  final List<VersionHistory> items;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: BirdSecondaryAppBar(
      title: '修改记录',
      subtitle: items.isEmpty ? '这张照片还没有修改' : '共 ${items.length} 条记录',
    ),
    body: NaturalBackdrop(
      dense: true,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.brandLight,
                    child: Icon(Icons.history_rounded, color: AppColors.brand),
                  ),
                  title: Text('暂无修改记录', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('修改鸟种、评分、标签或照片状态后，会显示在这里。'),
                ),
              ),
            ),
          for (var index = 0; index < items.length; index++) _HistoryItem(index: index + 1, item: items[index], isLast: index == items.length - 1),
        ],
      ),
    ),
  );
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.index, required this.item, required this.isLast});
  final int index;
  final VersionHistory item;
  final bool isLast;
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
                radius: 16,
                backgroundColor: index == 1 ? AppColors.brand : AppColors.brandLight,
                child: Text(
                  '$index',
                  style: TextStyle(color: index == 1 ? Colors.white : AppColors.brandDark, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: AppColors.brandMid.withValues(alpha: .35))),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _source(item.source),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.brandDark),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(99)),
                        child: Text(
                          '第 ${item.version} 版',
                          style: const TextStyle(fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_summary(item.summary)),
                  const SizedBox(height: 8),
                  Text(_time(item.updatedAt), style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  String _time(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}年${two(local.month)}月${two(local.day)}日 ${two(local.hour)}:${two(local.minute)}';
  }

  String _source(String value) => switch (value.toLowerCase()) {
    'box' || 'device' || 'ai' => '盒子识别',
    'app' || 'mobile' || 'user' => '手机修改',
    _ => '照片信息更新',
  };

  String _summary(String? value) {
    final original = value?.trim() ?? '';
    if (original.isEmpty) return '更新了照片信息';
    final lower = original.toLowerCase();
    final action = switch (lower) {
      String text when text.contains('featured') => '设为精选',
      String text when text.contains('pending') => '标记为待确认',
      String text when text.contains('discard') => '标记为弃用',
      String text when text.contains('keep') => '标记为保留',
      _ => null,
    };
    if (action != null && (lower.contains('bulk') || original.contains('批量操作'))) return '批量$action';
    return original
        .replaceAll(RegExp(r'\bfeatured\b', caseSensitive: false), '精选')
        .replaceAll(RegExp(r'\bpending\b', caseSensitive: false), '待确认')
        .replaceAll(RegExp(r'\bdiscard\b', caseSensitive: false), '弃用')
        .replaceAll(RegExp(r'\bkeep\b', caseSensitive: false), '保留');
  }
}
