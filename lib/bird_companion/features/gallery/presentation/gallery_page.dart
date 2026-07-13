import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/selection_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/sort_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key, required this.batchId});
  final String batchId;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => GalleryCubit(
          BirdCompanionScope.of(context).photoRepository,
          batchId,
          BirdCompanionScope.of(context).refreshCoordinator,
          BirdCompanionScope.of(context).dataChangeBus,
        )..refresh(),
      ),
      BlocProvider(create: (_) => SelectionCubit()),
    ],
    child: _GalleryView(batchId: batchId),
  );
}

class _GalleryView extends StatelessWidget {
  const _GalleryView({required this.batchId});
  final String batchId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BirdPageBackButton(),
      title: const Text('图库'),
      actions: [
        IconButton(
          tooltip: '分组审阅',
          icon: const Icon(Icons.collections_bookmark_outlined),
          onPressed: () => Navigator.of(context).pushNamed(BirdRoutes.groupReview, arguments: GroupReviewArgs(batchId)),
        ),
        IconButton(
          tooltip: '复制确认',
          icon: const Icon(Icons.copy_all_outlined),
          onPressed: () => Navigator.of(context).pushNamed(BirdRoutes.copyConfirmation, arguments: CopyConfirmationArgs(batchId)),
        ),
        IconButton(
          tooltip: '筛选照片',
          icon: const Icon(Icons.filter_list),
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => FilterSheet(
              initial: context.read<GalleryCubit>().state.query,
              onApply: (query) => context.read<GalleryCubit>().refresh(query: query),
            ),
          ),
        ),
        IconButton(
          tooltip: '排序方式',
          icon: const Icon(Icons.sort),
          onPressed: () => showModalBottomSheet(
            context: context,
            builder: (_) => SortSheet(
              value: context.read<GalleryCubit>().state.query.sort,
              onChanged: (sort) => context.read<GalleryCubit>().refresh(
                query: context.read<GalleryCubit>().state.query.copyWith(sort: sort, clearCursor: true),
              ),
            ),
          ),
        ),
      ],
    ),
    body: BlocBuilder<GalleryCubit, GalleryState>(
      builder: (context, state) {
        if (state.loading && state.items.isEmpty) return const Center(child: CircularProgressIndicator());
        return BlocBuilder<SelectionCubit, SelectionState>(
          builder: (context, selection) => Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => context.read<GalleryCubit>().refresh(),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 360) context.read<GalleryCubit>().loadMore();
                    return false;
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _GalleryHeader(state: state)),
                      if (state.query.activeLabels.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                ...state.query.activeLabels.map((label) => Chip(label: Text(label))),
                                TextButton(
                                  onPressed: () => context.read<GalleryCubit>().refresh(query: const PhotoQuery()),
                                  child: const Text('清除'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (state.items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _GalleryEmptyState(onReset: () => context.read<GalleryCubit>().refresh(query: const PhotoQuery())),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: .76,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= state.items.length) return Center(child: state.loading ? const CircularProgressIndicator() : const SizedBox.shrink());
                                final photo = state.items[index];
                                return PhotoTile(
                                  photo: photo,
                                  selected: selection.ids.contains(photo.id),
                                  onTap: () {
                                    if (selection.ids.isEmpty) {
                                      Navigator.of(context).pushNamed(BirdRoutes.photoDetail, arguments: PhotoDetailArgs(photo.id));
                                    } else {
                                      context.read<SelectionCubit>().toggle(photo.id);
                                    }
                                  },
                                  onLongPress: () => context.read<SelectionCubit>().toggle(photo.id),
                                );
                              },
                              childCount: state.items.length + (state.loading || state.hasMore ? 1 : 0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (selection.ids.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SelectionActionBar(
                    count: selection.ids.length,
                    busy: selection.submitting,
                    onClear: () => context.read<SelectionCubit>().clear(),
                    onTags: () => _showTagDialog(context, batchId, selection.ids.toList()),
                    onAction: (action) => _batchAction(context, batchId, selection.ids.toList(), action),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({required this.state});
  final GalleryState state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BirdConnectionLine(),
        const SizedBox(height: 18),
        Text('图库', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('${state.items.length} 张已加载 · 下拉刷新同步最新状态', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (state.query.keepState?.isNotEmpty == true) BirdPill(label: '状态：${state.query.keepState}'),
            if (state.query.species?.isNotEmpty == true) BirdPill(label: state.query.species!),
            BirdPill(label: _sortLabel(state.query.sort)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) => context.read<GalleryCubit>().search(value),
          onSubmitted: (value) => context.read<GalleryCubit>().refresh(query: state.query.copyWith(search: value.trim(), clearCursor: true)),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: '搜索文件名、鸟种或标签',
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}

String _sortLabel(String sort) => switch (sort) {
  'score_desc' => '评分从高到低',
  'confidence_desc' => '置信度从高到低',
  _ => '拍摄时间最新',
};

class _GalleryEmptyState extends StatelessWidget {
  const _GalleryEmptyState({required this.onReset});
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.photo_library_outlined, size: 52),
        const SizedBox(height: 12),
        const Text('没有符合条件的照片'),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onReset, child: const Text('清除筛选')),
      ],
    ),
  );
}

Future<void> _batchAction(BuildContext context, String batchId, List<String> ids, String action) async {
  final selection = context.read<SelectionCubit>();
  if (selection.state.submitting) return;
  selection.begin();
  final outcome = await BirdCompanionScope.of(context).photoRepository.batchOperation(batchId, ids, action);
  selection.complete(succeededIds: outcome.succeededIds, failed: outcome.failed);
  if (!context.mounted) return;
  await context.read<GalleryCubit>().refresh();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.queued ? '操作已加入待同步队列' : '已更新 ${outcome.succeededIds.length} 张照片')));
}

Future<void> _showTagDialog(BuildContext context, String batchId, List<String> ids) async {
  final controller = TextEditingController();
  final tags = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('批量添加标签'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: '例如：水鸟, 晨拍'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.split(',').map((value) => value.trim()).where((value) => value.isNotEmpty).toList()), child: const Text('应用')),
      ],
    ),
  );
  controller.dispose();
  if (tags == null || tags.isEmpty || !context.mounted) return;
  final selection = context.read<SelectionCubit>();
  selection.begin();
  final outcome = await BirdCompanionScope.of(context).photoRepository.batchOperation(batchId, ids, 'add_tags', value: tags);
  selection.complete(succeededIds: outcome.succeededIds, failed: outcome.failed);
  if (context.mounted) await context.read<GalleryCubit>().refresh();
}
