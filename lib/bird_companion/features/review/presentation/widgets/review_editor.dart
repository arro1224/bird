import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:flutter/material.dart';

class ReviewEditor extends StatelessWidget {
  const ReviewEditor({super.key, required this.keepState, required this.speciesController, required this.scoreController, required this.tagsController, required this.onKeepChanged});
  final KeepState keepState;
  final TextEditingController speciesController, scoreController, tagsController;
  final ValueChanged<KeepState> onKeepChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('人工复核', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.7,
        crossAxisSpacing: 14,
        mainAxisSpacing: 12,
        children: [
          _Choice(label: '保留', value: KeepState.keep, current: keepState, color: AppColors.brand, onTap: onKeepChanged),
          _Choice(label: '弃用', value: KeepState.discard, current: keepState, color: Colors.white, onTap: onKeepChanged),
          _Choice(label: '待确认', value: KeepState.pending, current: keepState, color: AppColors.amberLight, onTap: onKeepChanged),
          _Choice(label: '精选', value: KeepState.featured, current: keepState, color: AppColors.brandLight, onTap: onKeepChanged),
        ],
      ),
      const SizedBox(height: 10),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('高级编辑（鸟种、评分、标签）'),
        children: [
          TextField(
            controller: speciesController,
            decoration: const InputDecoration(labelText: '确认鸟种'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: scoreController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '人工评分（0-10）'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: tagsController,
            decoration: const InputDecoration(labelText: '自定义标签（用逗号分隔）'),
          ),
        ],
      ),
    ],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.value, required this.current, required this.color, required this.onTap});
  final String label;
  final KeepState value, current;
  final Color color;
  final ValueChanged<KeepState> onTap;
  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    final dark = color == AppColors.brand;
    return Material(
      color: selected ? color : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(value),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w900, color: selected && dark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}
