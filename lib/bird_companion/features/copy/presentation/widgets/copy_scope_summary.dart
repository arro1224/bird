import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:flutter/material.dart';

class CopyScopeSummary extends StatelessWidget {
  const CopyScopeSummary({super.key, required this.value});
  final CopyEstimate value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('复制范围：${value.fileCount} 张', style: Theme.of(context).textTheme.titleMedium),
          Text('需要 ${(value.requiredBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB · 待确认 ${value.pendingCount} 张'),
          const SizedBox(height: 6),
          const Text('保留、淘汰、待确认和精选照片由盒子端按复制模式结算；人工标签以 XMP 旁车文件保留。'),
        ],
      ),
    ),
  );
}
