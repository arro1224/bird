import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:flutter/material.dart';

class CurrentBatchCard extends StatelessWidget {
  const CurrentBatchCard({super.key, required this.batch, required this.onOpen});
  final BatchSummary batch;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DecoratedBox(
        decoration: const ShapeDecoration(color: AppColors.brandLight, shape: StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            _dateLabel(),
            style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Card(
        color: AppColors.brand,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(batch.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              const Text('导入与 AI 分析正在进行', style: TextStyle(color: Color(0xFFD9F0D8))),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Count(label: '总照片', value: batch.totalFiles),
                  _Count(label: '已分析', value: batch.analyzedCount),
                  _Count(label: '待复核', value: batch.reviewCount),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(onPressed: onOpen, child: const Text('进入图库开始审片')),
    ],
  );

  String _dateLabel() {
    final date = batch.createdAt;
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} · 当前批次';
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Color(0xFFD9F0D8))),
      const SizedBox(height: 4),
      Text(
        '$value',
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
      ),
    ],
  );
}
