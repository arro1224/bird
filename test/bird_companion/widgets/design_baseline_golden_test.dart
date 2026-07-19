import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/current_batch_card.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(390, 844), Size(360, 800)]) {
    testWidgets('设计系统视觉基线 ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const _BaselineScreen()));
      await tester.pump();

      await expectLater(
        find.byType(_BaselineScreen),
        matchesGoldenFile('goldens/design_baseline_${size.width.toInt()}x${size.height.toInt()}.png'),
      );
    });
  }
}

class _BaselineScreen extends StatelessWidget {
  const _BaselineScreen();

  static final batch = BatchSummary(
    id: 'batch-baseline',
    name: '崇明东滩 · 清晨',
    createdAt: DateTime.utc(2026, 7, 12),
    totalFiles: 3672,
    analyzedCount: 1284,
    reviewCount: 326,
    keepCount: 218,
    discardCount: 18,
    pendingCopyCount: 218,
    copyState: 'pending',
  );

  static const photos = [
    PhotoSummary(
      id: 'photo-1',
      filename: 'DSC_4821.NEF',
      format: 'NEF',
      preview: PreviewRef(width: 6000, height: 4000),
      analysisState: AnalysisState.completed,
      rating: RatingResult(totalScore: 4.8),
      keepState: 'keep',
    ),
    PhotoSummary(
      id: 'photo-2',
      filename: 'DSC_4822.NEF',
      format: 'NEF',
      preview: PreviewRef(width: 6000, height: 4000),
      analysisState: AnalysisState.lowConfidence,
      rating: RatingResult(totalScore: 4.3),
      keepState: 'pending',
    ),
    PhotoSummary(
      id: 'photo-3',
      filename: 'DSC_4823.NEF',
      format: 'NEF',
      preview: PreviewRef(width: 6000, height: 4000),
      analysisState: AnalysisState.completed,
      rating: RatingResult(totalScore: 5),
      keepState: 'featured',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text('照片批次', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 6),
          const Text('设计系统回归基线', style: TextStyle(color: AppColors.inkMuted)),
          const SizedBox(height: 20),
          CurrentBatchCard(batch: batch, onOpen: _noop, actionLabel: '进入当前批次'),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('图库状态', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ),
              FilterChip(label: const Text('AI 推荐'), selected: true, onSelected: (_) {}),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: Row(
              children: [
                for (var index = 0; index < photos.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: PhotoTile(photo: photos[index], selected: index == 0, onTap: _noop, onLongPress: _noop),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  static void _noop() {}
}
