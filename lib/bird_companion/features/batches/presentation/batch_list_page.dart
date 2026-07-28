import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_filter_bar.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_list_tile.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/current_batch_card.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_resume_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum BatchOpenMode { gallery, review }

/// “继续挑选”始终从当前批次的照片主页开始，不携带上次连拍位置。
GalleryArgs currentBatchGalleryArgs(BatchSummary batch) => GalleryArgs(
  batch.id,
  batchName: batch.name,
  createdAt: batch.createdAt,
  totalCount: batch.totalFiles,
  pendingCount: batch.pendingReviewCount,
  keepCount: batch.keepCount,
  discardCount: batch.discardCount,
  restoreSavedView: false,
  reviewContext: ReviewContext(
    batchId: batch.id,
    batchName: batch.name,
  ),
);

class BatchListPage extends StatelessWidget {
  const BatchListPage({super.key, this.openMode = BatchOpenMode.gallery});

  final BatchOpenMode openMode;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => BatchListCubit(
          BirdCompanionScope.of(context).batchRepository,
          BirdCompanionScope.of(context).refreshCoordinator,
          BirdCompanionScope.of(context).dataChangeBus,
        )..load(),
      ),
    ],
    child: Scaffold(
      appBar: BirdSecondaryAppBar(
        title: openMode == BatchOpenMode.gallery ? '拍摄记录' : '照片挑选',
        helpTooltip: '拍摄记录说明',
        onHelp: () => showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('什么是拍摄记录？'),
            content: Text('每次导入存储卡或完成一次拍摄行程，盒子都会建立一条拍摄记录，方便你查找这次拍摄的照片。'),
          ),
        ),
      ),
      body: NaturalBackdrop(dense: true, child: _View(openMode: openMode)),
    ),
  );
}

class _View extends StatefulWidget {
  const _View({required this.openMode});

  final BatchOpenMode openMode;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  var _showCurrent = true;
  String? _resolvingBatchId;

  @override
  Widget build(BuildContext context) => BlocBuilder<BatchListCubit, BatchListState>(
    builder: (context, state) {
      if (state.loading && state.items.isEmpty) return const Center(child: CircularProgressIndicator());
      if (state.error != null) return ErrorNotice(title: '暂时无法加载拍摄记录', message: '请检查盒子连接后重试。', onRetry: () => context.read<BatchListCubit>().load());
      return RefreshIndicator(
        onRefresh: () => context.read<BatchListCubit>().load(filter: state.filter),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 240) context.read<BatchListCubit>().loadMore();
            return false;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              if (widget.openMode != BatchOpenMode.gallery) ...[
                Text('照片挑选', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 8),
                Text(
                  '按每次拍摄记录继续挑选照片',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (widget.openMode != BatchOpenMode.gallery) const SizedBox(height: 24),
              _BatchModeSwitch(
                showCurrent: _showCurrent,
                onChanged: (value) => setState(() => _showCurrent = value),
              ),
              const SizedBox(height: 24),
              if (_showCurrent) ...[
                if (state.current == null)
                  const EmptyState(title: '暂无正在处理的拍摄记录', message: '插入存储卡并开始导入后，这次拍摄会显示在这里。')
                else
                  CurrentBatchCard(
                    batch: state.current!,
                    actionLabel: '继续挑选',
                    loading: _resolvingBatchId == state.current!.id,
                    onOpen: () => _continueReview(context, state.current!),
                  ),
                const SizedBox(height: 28),
                const _HistoryHeading(),
                const SizedBox(height: 12),
                if (_historyItems(state).isEmpty)
                  const EmptyState(title: '暂无过去的拍摄记录', message: '已完成的拍摄会显示在这里。')
                else
                  for (final item in _historyItems(state))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BatchListTile(
                        batch: item,
                        actionLabel: widget.openMode == BatchOpenMode.gallery ? '查看图库' : '选择场景',
                        onOpen: () => _openBatch(context, item),
                        onResume: () => showDialog(
                          context: context,
                          builder: (_) => BatchResumeDialog(onConfirm: () => context.read<BatchListCubit>().resume(item.id)),
                        ),
                      ),
                    ),
              ] else ...[
                BatchFilterBar(
                  value: state.filter,
                  onChanged: (value) => context.read<BatchListCubit>().load(filter: value),
                ),
                const SizedBox(height: 18),
                if (state.items.isEmpty)
                  const EmptyState(title: '暂无过去的拍摄记录', message: '已完成的拍摄会显示在这里。')
                else
                  for (final item in state.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BatchListTile(
                        batch: item,
                        actionLabel: widget.openMode == BatchOpenMode.gallery ? '查看图库' : '选择场景',
                        onOpen: () => _openBatch(context, item),
                        onResume: () => showDialog(
                          context: context,
                          builder: (_) => BatchResumeDialog(onConfirm: () => context.read<BatchListCubit>().resume(item.id)),
                        ),
                      ),
                    ),
              ],
              if (state.loadingMore)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      );
    },
  );

  List<BatchSummary> _historyItems(BatchListState state) => state.items.where((item) => item.id != state.current?.id).toList(growable: false);

  Future<void> _openBatch(BuildContext context, BatchSummary batch) async {
    final reviewContext = ReviewContext(
      batchId: batch.id,
      batchName: batch.name,
    );
    await Navigator.of(context).pushNamed(
      widget.openMode == BatchOpenMode.gallery ? BirdRoutes.gallery : BirdRoutes.scenes,
      arguments: widget.openMode == BatchOpenMode.gallery
          ? GalleryArgs(
              batch.id,
              batchName: batch.name,
              createdAt: batch.createdAt,
              totalCount: batch.totalFiles,
              pendingCount: batch.pendingReviewCount,
              keepCount: batch.keepCount,
              discardCount: batch.discardCount,
              reviewContext: reviewContext,
            )
          : SceneListArgs(
              batch.id,
              batchName: batch.name,
              totalCount: batch.totalFiles,
              reviewContext: reviewContext,
            ),
    );
    if (context.mounted) {
      final cubit = context.read<BatchListCubit>();
      await cubit.load(filter: cubit.state.filter);
    }
  }

  Future<void> _continueReview(
    BuildContext context,
    BatchSummary batch,
  ) async {
    if (_resolvingBatchId != null) return;
    setState(() => _resolvingBatchId = batch.id);
    await Navigator.of(context).pushNamed(
      BirdRoutes.gallery,
      arguments: currentBatchGalleryArgs(batch),
    );
    if (!mounted || !context.mounted) return;
    setState(() => _resolvingBatchId = null);
    if (context.mounted) {
      final cubit = context.read<BatchListCubit>();
      await cubit.load(filter: cubit.state.filter);
    }
  }
}

class _BatchModeSwitch extends StatelessWidget {
  const _BatchModeSwitch({required this.showCurrent, required this.onChanged});

  final bool showCurrent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .58),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .35)),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ModeButton(
            label: '本次拍摄',
            selected: showCurrent,
            onTap: () => onChanged(true),
          ),
        ),
        Expanded(
          child: _ModeButton(
            label: '过去拍摄',
            selected: !showCurrent,
            onTap: () => onChanged(false),
          ),
        ),
      ],
    ),
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 16,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _HistoryHeading extends StatelessWidget {
  const _HistoryHeading();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        '过去的拍摄',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(width: 8),
      Icon(Icons.grass_rounded, size: 20, color: Theme.of(context).colorScheme.primary.withValues(alpha: .5)),
    ],
  );
}
