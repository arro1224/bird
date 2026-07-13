import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_filter_bar.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_list_tile.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/current_batch_card.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_resume_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BatchListPage extends StatelessWidget {
  const BatchListPage({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocProvider(create: (_) => BatchListCubit(BirdCompanionScope.of(context).batchRepository, BirdCompanionScope.of(context).refreshCoordinator, BirdCompanionScope.of(context).dataChangeBus)..load(), child: const _View());
}

class _View extends StatelessWidget {
  const _View();
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
            padding: const EdgeInsets.all(16),
            children: [
              BatchFilterBar(
                value: state.filter,
                onChanged: (v) => context.read<BatchListCubit>().load(filter: v),
              ),
              const SizedBox(height: 16),
              if (state.current != null)
                CurrentBatchCard(
                  batch: state.current!,
                  onOpen: () => Navigator.of(context).pushNamed(BirdRoutes.gallery, arguments: GalleryArgs(state.current!.id)),
                ),
              const SizedBox(height: 16),
              Text('历史批次', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (state.items.isEmpty)
                const EmptyState(title: '暂无批次', message: '插入存储卡并开始导入后，批次会显示在这里。')
              else
                for (final item in state.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: BatchListTile(
                      batch: item,
                      onOpen: () => Navigator.of(context).pushNamed(BirdRoutes.gallery, arguments: GalleryArgs(item.id)),
                      onResume: () => showDialog(
                        context: context,
                        builder: (_) => BatchResumeDialog(onConfirm: () => context.read<BatchListCubit>().resume(item.id)),
                      ),
                    ),
                  ),
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
}
