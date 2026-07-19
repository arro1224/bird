import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_filter_bar.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_list_tile.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/current_batch_card.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_resume_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum BatchOpenMode { gallery, review }

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
      appBar: AppBar(
        leading: const BirdPageBackButton(),
        centerTitle: true,
        title: Text(openMode == BatchOpenMode.gallery ? '批次' : '智能审阅'),
        actions: [
          IconButton(
            tooltip: '批次说明',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('什么是批次？'),
                content: Text('盒子会按一次存储卡导入或拍摄行程建立批次，批次内继续按场景和连拍组整理照片。'),
              ),
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
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

  @override
  Widget build(BuildContext context) => BlocBuilder<BatchListCubit, BatchListState>(
    builder: (context, state) {
      if (state.loading && state.items.isEmpty) return const Center(child: CircularProgressIndicator());
      if (state.error != null) return ErrorNotice(title: '批次加载失败', message: '请检查盒子连接后重试。', onRetry: () => context.read<BatchListCubit>().load());
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
                Text('智能审阅', style: Theme.of(context).textTheme.displaySmall),
                const SizedBox(height: 8),
                Text(
                  '按批次继续连拍分组与照片复核',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (widget.openMode != BatchOpenMode.gallery) const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('当前')),
                  ButtonSegment(value: false, label: Text('历史')),
                ],
                selected: {_showCurrent},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() => _showCurrent = selection.first),
              ),
              const SizedBox(height: 24),
              if (_showCurrent) ...[
                Text('当前批次', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (state.current == null)
                  const EmptyState(title: '暂无当前批次', message: '插入存储卡并开始导入后，当前批次会显示在这里。')
                else
                  CurrentBatchCard(
                    batch: state.current!,
                    actionLabel: widget.openMode == BatchOpenMode.gallery ? '进入当前批次' : '继续审阅',
                    onOpen: () => _openBatch(context, state.current!),
                  ),
              ] else ...[
                BatchFilterBar(
                  value: state.filter,
                  onChanged: (value) => context.read<BatchListCubit>().load(filter: value),
                ),
                const SizedBox(height: 18),
                if (state.items.isEmpty)
                  const EmptyState(title: '暂无历史批次', message: '已结束的拍摄批次会显示在这里。')
                else
                  for (final item in state.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BatchListTile(
                        batch: item,
                        actionLabel: widget.openMode == BatchOpenMode.gallery ? '查看图库' : '打开审阅',
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

  void _openBatch(BuildContext context, BatchSummary batch) {
    Navigator.of(context).pushNamed(
      widget.openMode == BatchOpenMode.gallery ? BirdRoutes.gallery : BirdRoutes.groupReview,
      arguments: widget.openMode == BatchOpenMode.gallery ? GalleryArgs(batch.id, batchName: batch.name, totalCount: batch.totalFiles) : GroupReviewArgs(batch.id),
    );
  }
}
