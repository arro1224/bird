import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_confirm_dialog.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_mode_card.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_target_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CopyConfirmationPage extends StatelessWidget {
  const CopyConfirmationPage({super.key, required this.batchId});
  final String batchId;
  @override
  Widget build(BuildContext c) => BlocProvider(
    create: (_) => CopyConfirmationCubit(BirdCompanionScope.of(c).copyRepository, batchId, BirdCompanionScope.of(c).dataChangeBus)..load(),
    child: _View(batchId: batchId),
  );
}

class _View extends StatelessWidget {
  const _View({required this.batchId});
  final String batchId;
  @override
  Widget build(BuildContext c) => BlocConsumer<CopyConfirmationCubit, CopyConfirmationState>(
    listener: (c, s) {
      if (s.submitted && s.jobId != null) Navigator.of(c).pushReplacementNamed(BirdRoutes.jobDetail, arguments: JobDetailArgs(s.jobId!, sourceBatchId: batchId));
    },
    builder: (c, s) {
      final e = s.estimate;
      return Scaffold(
        appBar: AppBar(leading: const BirdPageBackButton(), title: const Text('复制确认')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('确认范围、目标存储与 XMP 策略', style: Theme.of(c).textTheme.bodyLarge?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            Text('复制模式', style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: 14),
            for (final m in ['keep', 'all', 'dual']) CopyModeCard(mode: m, selected: s.mode == m, estimate: s.mode == m ? e : null, onTap: () => c.read<CopyConfirmationCubit>().load(m)),
            if (e != null) ...[
              const SizedBox(height: 18),
              Text('目标存储', style: Theme.of(c).textTheme.headlineSmall),
              const SizedBox(height: 14),
              for (final t in e.targets) StorageTargetCard(target: t, selected: s.targetId == t.id, onTap: () => c.read<CopyConfirmationCubit>().selectTarget(t.id)),
              const SizedBox(height: 16),
              const Text(
                '生成同名 XMP',
                style: TextStyle(color: Color(0xFF175642), fontWeight: FontWeight.w800),
              ),
            ],
            if (s.submissionBlockReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.submissionBlockReason!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
              ),
            FilledButton(
              onPressed: s.loading || s.submissionBlockReason != null
                  ? null
                  : () => showDialog(
                      context: c,
                      builder: (_) => CopyConfirmDialog(onConfirm: () => c.read<CopyConfirmationCubit>().submit()),
                    ),
              child: Text(s.loading ? '处理中…' : '创建复制任务'),
            ),
          ],
        ),
      );
    },
  );
}
