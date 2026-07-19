import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_mode_card.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_target_card.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:aves/bird_companion/features/jobs/presentation/widgets/job_card.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/comparison_photo_pane.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/recognition_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const summary = PhotoSummary(
    id: 'photo-1',
    filename: 'DSC_4821_WITH_A_VERY_LONG_FILENAME.NEF',
    format: 'NEF',
    preview: PreviewRef(width: 6000, height: 4000),
    analysisState: AnalysisState.completed,
    recognition: RecognitionResult(
      candidates: [
        SpeciesCandidate(name: '东方大苇莺', confidence: .87),
        SpeciesCandidate(name: '大苇莺', confidence: .08),
        SpeciesCandidate(name: '芦苇莺', confidence: .03),
      ],
    ),
    rating: RatingResult(totalScore: 4.8, reasonTags: ['鸟眼清晰', '主体完整', '背景干净']),
    keepState: 'keep',
  );

  testWidgets('图库照片卡在窄网格中不溢出', (tester) async {
    await _pumpNarrow(
      tester,
      PhotoTile(photo: summary, selected: false, onTap: () {}, onLongPress: () {}),
      width: 94,
      height: 94,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('任务卡在 320dp 宽度中不溢出', (tester) async {
    await _pumpNarrow(
      tester,
      JobCard(
        job: const BirdJobStatus(
          id: 'job-1',
          type: BirdJobType.copy,
          state: BirdJobState.running,
          totalCount: 3672,
          finishedCount: 1284,
          currentFile: 'DSC_4821_WITH_A_VERY_LONG_FILENAME.NEF',
          speedBytesPerSecond: 84 * 1024 * 1024,
        ),
        onTap: () {},
        onControl: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('复制模式和目标盘在 320dp 宽度中不溢出', (tester) async {
    const estimate = CopyEstimate(
      mode: 'keep',
      fileCount: 3672,
      requiredBytes: 20 * 1024 * 1024 * 1024,
      pendingCount: 12,
      targets: [],
    );
    await _pumpNarrow(
      tester,
      ListView(
        children: [
          CopyModeCard(mode: 'keep', selected: true, estimate: estimate, onTap: () {}),
          StorageTargetCard(
            target: const StorageTarget(
              id: 'target-1',
              name: 'Samsung T7 Shield Portable SSD',
              freeBytes: 1200 * 1024 * 1024 * 1024,
              totalBytes: 2000 * 1024 * 1024 * 1024,
              online: true,
            ),
            selected: true,
            onTap: () {},
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 识别和三图对比卡在窄布局中不溢出', (tester) async {
    await _pumpNarrow(tester, RecognitionPanel(value: summary.recognition));
    expect(tester.takeException(), isNull);

    await _pumpNarrow(
      tester,
      ComparisonPhotoPane(
        detail: const ReviewDetail(photo: PhotoDetail(summary: summary)),
        rank: 0,
        saving: false,
        onMark: (_) {},
      ),
      width: 104,
      height: 520,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpNarrow(WidgetTester tester, Widget child, {double width = 320, double height = 640}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
