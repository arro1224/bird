import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <({BatchSummary batch, String label, IconData icon, Color color})>[
    (
      batch: _batch(state: 'processing', pending: 8),
      label: '进行中',
      icon: Icons.sync_rounded,
      color: AppColors.brandMid,
    ),
    (
      batch: _batch(state: 'ready_to_review', pending: 8),
      label: '待挑选',
      icon: Icons.fact_check_outlined,
      color: AppColors.pending,
    ),
    (
      batch: _batch(state: 'failed'),
      label: '异常',
      icon: Icons.error_outline_rounded,
      color: AppColors.danger,
    ),
    (
      batch: _batch(state: 'completed'),
      label: '已完成',
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.success,
    ),
    (
      batch: _batch(),
      label: '状态待确认',
      icon: Icons.help_outline_rounded,
      color: AppColors.inkMuted,
    ),
  ];

  for (final testCase in cases) {
    testWidgets('history tile displays ${testCase.label}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BatchListTile(
              batch: testCase.batch,
              onOpen: () {},
              onResume: () {},
            ),
          ),
        ),
      );

      expect(find.text(testCase.label), findsOneWidget);
      expect(find.byIcon(testCase.icon), findsOneWidget);
      final label = tester.widget<Text>(find.text(testCase.label));
      expect(label.style?.color, testCase.color);
      expect(label.style?.fontWeight, FontWeight.w800);
    });
  }
}

BatchSummary _batch({
  String? state,
  String copyState = 'unknown',
  int pending = 0,
}) => BatchSummary(
  id: 'project-${state ?? copyState}-$pending',
  name: '测试拍摄记录',
  createdAt: DateTime.utc(2026, 9, 14),
  totalFiles: 20,
  analyzedCount: 20,
  reviewCount: pending,
  keepCount: 20 - pending,
  discardCount: 0,
  pendingCopyCount: 0,
  copyState: copyState,
  state: state,
);
