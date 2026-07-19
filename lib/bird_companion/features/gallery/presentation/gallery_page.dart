import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_pills.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_sheet.dart';
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
  const GalleryPage({super.key, required this.batchId, this.batchName, this.totalCount, this.initialQuery = const PhotoQuery(), this.rootMode = false});
  final String batchId;
  final String? batchName;
  final int? totalCount;
  final PhotoQuery initialQuery;
  final bool rootMode;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => GalleryCubit(
          BirdCompanionScope.of(context).photoRepository,
          batchId,
          BirdCompanionScope.of(context).refreshCoordinator,
          BirdCompanionScope.of(context).dataChangeBus,
          BirdCompanionScope.of(context).cache,
        )..restoreAndRefresh(initialQuery),
      ),
      BlocProvider(create: (_) => SelectionCubit()),
      if (rootMode)
        BlocProvider(
          create: (_) => DeviceStatusCubit(
            BirdCompanionScope.of(context).deviceRepository,
            BirdCompanionScope.of(context).deviceSessionCubit,
            BirdCompanionScope.of(context).refreshCoordinator,
            BirdCompanionScope.of(context).dataChangeBus,
          )..load(),
        ),
    ],
    child: _GalleryView(batchId: batchId, batchName: batchName, totalCount: totalCount, rootMode: rootMode),
  );
}

class _GalleryView extends StatelessWidget {
  const _GalleryView({required this.batchId, this.batchName, this.totalCount, required this.rootMode});
  final String batchId;
  final String? batchName;
  final int? totalCount;
  final bool rootMode;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: BlocBuilder<SelectionCubit, SelectionState>(
        builder: (context, selection) => AppBar(
          automaticallyImplyLeading: !rootMode,
          leading: selection.ids.isEmpty
              ? rootMode
                    ? null
                    : const BirdPageBackButton()
              : IconButton(tooltip: '退出多选', onPressed: context.read<SelectionCubit>().clear, icon: const Icon(Icons.close_rounded)),
          centerTitle: selection.ids.isNotEmpty,
          title: selection.ids.isNotEmpty
              ? Text('已选择 ${selection.ids.length} 张')
              : rootMode
              ? Text(
                  '相册',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.w800),
                )
              : BlocBuilder<GalleryCubit, GalleryState>(
                  buildWhen: (previous, current) => previous.items.length != current.items.length,
                  builder: (_, state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(batchName ?? batchId, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        totalCount == null ? '已加载 ${state.items.length} 张' : '$totalCount 张照片',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
          actions: selection.ids.isNotEmpty
              ? [TextButton(onPressed: selection.submitting ? null : context.read<SelectionCubit>().clear, child: const Text('取消'))]
              : [
                  if (rootMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: IconButton.filled(
                        tooltip: '新增或切换设备',
                        onPressed: () => Navigator.of(context, rootNavigator: true).pushNamed(
                          BirdRoutes.connection,
                          arguments: const ConnectionArgs(entryMode: ConnectionEntryMode.addOrSwitch),
                        ),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ),
                  if (!rootMode)
                    IconButton(
                      tooltip: '搜索照片',
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => _showGallerySearch(context),
                    ),
                  if (!rootMode)
                    IconButton(
                      tooltip: '筛选照片',
                      icon: const Icon(Icons.filter_alt_outlined),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => FilterSheet(
                          initial: context.read<GalleryCubit>().state.query,
                          onApply: (query) => context.read<GalleryCubit>().refresh(query: query),
                        ),
                      ),
                    ),
                  if (!rootMode)
                    PopupMenuButton<String>(
                      tooltip: '更多操作',
                      onSelected: (value) {
                        if (value == 'copy') {
                          Navigator.of(context).pushNamed(BirdRoutes.copyConfirmation, arguments: CopyConfirmationArgs(batchId));
                        } else if (value == 'review') {
                          Navigator.of(context).pushNamed(BirdRoutes.groupReview, arguments: GroupReviewArgs(batchId));
                        } else if (value == 'scenes') {
                          Navigator.of(context).pushNamed(
                            BirdRoutes.scenes,
                            arguments: SceneListArgs(batchId, batchName: batchName, totalCount: totalCount),
                          );
                        } else {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => SortSheet(
                              value: context.read<GalleryCubit>().state.query.sort,
                              onChanged: (sort) => context.read<GalleryCubit>().refresh(
                                query: context.read<GalleryCubit>().state.query.copyWith(sort: sort, clearCursor: true),
                              ),
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'scenes',
                          child: ListTile(leading: Icon(Icons.account_tree_outlined), title: Text('按场景浏览')),
                        ),
                        PopupMenuItem(
                          value: 'review',
                          child: ListTile(leading: Icon(Icons.auto_awesome_mosaic_outlined), title: Text('分组审阅')),
                        ),
                        PopupMenuItem(
                          value: 'sort',
                          child: ListTile(leading: Icon(Icons.sort_rounded), title: Text('排序方式')),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: ListTile(leading: Icon(Icons.copy_all_outlined), title: Text('复制照片')),
                        ),
                      ],
                    ),
                ],
        ),
      ),
    ),
    body: BlocBuilder<GalleryCubit, GalleryState>(
      builder: (context, state) {
        if (state.loading && state.items.isEmpty) return const Center(child: CircularProgressIndicator());
        return NaturalBackdrop(
          child: Stack(
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
                      SliverToBoxAdapter(
                        child: _GalleryHeader(
                          state: state,
                          rootMode: rootMode,
                          batchId: batchId,
                          batchName: batchName,
                          totalCount: totalCount,
                        ),
                      ),
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
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 1,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= state.items.length) return Center(child: state.loading ? const CircularProgressIndicator() : const SizedBox.shrink());
                                final photo = state.items[index];
                                return _SelectablePhotoTile(
                                  photo: photo,
                                  compact: rootMode,
                                  onTap: () {
                                    final selection = context.read<SelectionCubit>();
                                    if (selection.state.ids.isEmpty) {
                                      Navigator.of(context).pushNamed(
                                        BirdRoutes.photoDetail,
                                        arguments: PhotoDetailArgs(
                                          photo.id,
                                          displayIndex: index + 1,
                                          totalCount: totalCount,
                                          sequence: state.items.map((item) => item.id).toList(growable: false),
                                        ),
                                      );
                                    } else {
                                      selection.toggle(photo.id);
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
              _SelectionActionOverlay(batchId: batchId),
            ],
          ),
        );
      },
    ),
  );
}

class _SelectablePhotoTile extends StatelessWidget {
  const _SelectablePhotoTile({required this.photo, required this.onTap, required this.onLongPress, required this.compact});

  final PhotoSummary photo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool compact;

  @override
  Widget build(BuildContext context) => BlocSelector<SelectionCubit, SelectionState, bool>(
    selector: (state) => state.ids.contains(photo.id),
    builder: (_, selected) => PhotoTile(
      key: ValueKey(photo.id),
      photo: photo,
      compact: compact,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    ),
  );
}

class _SelectionActionOverlay extends StatelessWidget {
  const _SelectionActionOverlay({required this.batchId});

  final String batchId;

  @override
  Widget build(BuildContext context) => BlocBuilder<SelectionCubit, SelectionState>(
    builder: (context, selection) {
      if (selection.ids.isEmpty) return const SizedBox.shrink();
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SelectionActionBar(
          count: selection.ids.length,
          busy: selection.submitting,
          onClear: () => context.read<SelectionCubit>().clear(),
          onAddTags: () => _showTagDialog(context, batchId, selection.ids.toList(), remove: false),
          onRemoveTags: () => _showTagDialog(context, batchId, selection.ids.toList(), remove: true),
          onAction: (action) => _requestBatchAction(context, batchId, selection.ids.toList(), action),
        ),
      );
    },
  );
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({required this.state, required this.rootMode, required this.batchId, this.batchName, this.totalCount});
  final GalleryState state;
  final bool rootMode;
  final String batchId;
  final String? batchName;
  final int? totalCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rootMode) ...[
          const _AlbumDeviceStatus(),
          const SizedBox(height: 12),
          const _DeviceHint(),
          const SizedBox(height: 18),
          _AlbumBatchHeading(
            batchId: batchId,
            batchName: batchName,
            totalCount: totalCount,
          ),
          const SizedBox(height: 14),
        ],
        if (state.fromCache) ...[
          _OfflineSnapshotNotice(cachedAt: state.cachedAt),
          const SizedBox(height: 12),
        ],
        _QuickFilters(query: state.query),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '按${_sortLabel(state.query.sort)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: '调整排序',
              onPressed: () => showModalBottomSheet(
                context: context,
                builder: (_) => SortSheet(
                  value: state.query.sort,
                  onChanged: (sort) => context.read<GalleryCubit>().refresh(query: state.query.copyWith(sort: sort, clearCursor: true)),
                ),
              ),
              icon: const Icon(Icons.grid_view_rounded),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AlbumDeviceStatus extends StatelessWidget {
  const _AlbumDeviceStatus();

  @override
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    return BlocBuilder<DeviceStatusCubit, DeviceStatusState>(
      builder: (context, statusState) => BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
        bloc: dependencies.deviceSessionCubit,
        builder: (context, session) {
          final status = statusState.status;
          if (status != null) {
            return DeviceStatusPills(
              status: status,
              session: session,
              onTap: () => _showAlbumStatusSheet(context, status, session),
            );
          }
          return OutlinedButton.icon(
            onPressed: statusState.phase == DeviceStatusPhase.loading ? null : context.read<DeviceStatusCubit>().load,
            icon: statusState.phase == DeviceStatusPhase.loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              statusState.phase == DeviceStatusPhase.loading ? '正在读取设备状态' : '设备状态暂不可用，点按重试',
            ),
          );
        },
      ),
    );
  }

  void _showAlbumStatusSheet(
    BuildContext context,
    DeviceStatus status,
    DeviceSessionState session,
  ) {
    showDeviceStatusSheet(
      context,
      status: status,
      session: session,
      onReconnect: () {
        Navigator.of(context).pop();
        BirdCompanionScope.of(context).deviceSessionCubit.reconnect();
      },
      onOpenDetails: () {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamed(BirdRoutes.deviceStatus);
      },
      onOpenTask: status.currentJob == null
          ? null
          : () {
              Navigator.of(context).pop();
              BirdShellNavigation.maybeOf(context)?.selectTab(1);
            },
    );
  }
}

class _AlbumBatchHeading extends StatelessWidget {
  const _AlbumBatchHeading({required this.batchId, this.batchName, this.totalCount});

  final String batchId;
  final String? batchName;
  final int? totalCount;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batchName ?? batchId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark),
                ),
                const SizedBox(height: 3),
                Text(
                  totalCount == null ? '当前批次' : '$totalCount 张照片',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(BirdRoutes.batches),
            icon: const Icon(Icons.chevron_right_rounded),
            iconAlignment: IconAlignment.end,
            label: const Text('批次'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.of(context).pushNamed(
            BirdRoutes.scenes,
            arguments: SceneListArgs(batchId, batchName: batchName, totalCount: totalCount),
          ),
          child: const Text('批次  >  场景  >  连拍组  >'),
        ),
      ),
    ],
  );
}

class _DeviceHint extends StatefulWidget {
  const _DeviceHint();

  @override
  State<_DeviceHint> createState() => _DeviceHintState();
}

class _DeviceHintState extends State<_DeviceHint> {
  var _visible = true;

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.paperStrong.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const Text('•', style: TextStyle(color: AppColors.brand, fontSize: 22)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('点这里查看设备温度、存储和任务状态', style: TextStyle(color: AppColors.inkMuted)),
          ),
          IconButton(
            tooltip: '关闭提示',
            onPressed: () => setState(() => _visible = false),
            icon: const Icon(Icons.close_rounded, size: 19, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _OfflineSnapshotNotice extends StatelessWidget {
  const _OfflineSnapshotNotice({this.cachedAt});

  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final suffix = cachedAt == null ? '' : ' · 缓存于 ${_time(cachedAt!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        border: Border.all(color: AppColors.danger.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.link_off_rounded, color: AppColors.danger),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('设备暂不可用，正在浏览本机缓存$suffix', style: const TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: BirdCompanionScope.of(context).deviceSessionCubit.reconnect,
              child: const Text('重新连接'),
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _QuickFilters extends StatelessWidget {
  const _QuickFilters({required this.query});

  final PhotoQuery query;

  @override
  Widget build(BuildContext context) {
    final values = <(String, String?)>[
      ('全部', null),
      ('待确认', 'pending'),
      ('已保留', 'keep'),
      ('已弃用', 'discard'),
      ('精选', 'featured'),
    ];
    final selected = query.recommendedOnly ? '__ai__' : query.keepState;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...values.map((entry) {
            final active = selected == entry.$2;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: active,
                label: Text(entry.$1),
                onSelected: (_) => context.read<GalleryCubit>().refresh(query: _quickQuery(query, entry.$2)),
              ),
            );
          }),
          ActionChip(
            avatar: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('筛选'),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => FilterSheet(
                initial: context.read<GalleryCubit>().state.query,
                onApply: (value) => context.read<GalleryCubit>().refresh(query: value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showGallerySearch(BuildContext context) async {
  final cubit = context.read<GalleryCubit>();
  final controller = TextEditingController(text: cubit.state.query.search ?? '');
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('搜索照片'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: '文件名、鸟种或标签'),
        onSubmitted: (text) => Navigator.pop(dialogContext, text),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('搜索')),
      ],
    ),
  );
  controller.dispose();
  if (value == null || !context.mounted) return;
  await cubit.refresh(query: cubit.state.query.copyWith(search: value.trim(), clearCursor: true));
}

PhotoQuery _quickQuery(PhotoQuery source, String? value) => PhotoQuery(
  sort: source.sort,
  search: source.search,
  species: source.species,
  minScore: source.minScore,
  minConfidence: source.minConfidence,
  tags: source.tags,
  keepState: value == '__ai__' ? null : value,
  analysisState: source.analysisState,
  clarityState: source.clarityState,
  recognitionState: source.recognitionState,
  recommendedOnly: value == '__ai__',
  groupId: source.groupId,
  sceneId: source.sceneId,
);

String _sortLabel(String sort) => switch (sort) {
  'score_desc' => '评分从高到低',
  'confidence_desc' => '置信度从高到低',
  'recommended_desc' => 'AI 推荐优先',
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
  final previousById = {
    for (final photo in context.read<GalleryCubit>().state.items.where((photo) => ids.contains(photo.id))) photo.id: photo.keepState ?? 'pending',
  };
  selection.begin();
  final outcome = await BirdCompanionScope.of(context).photoRepository.batchOperation(batchId, ids, action);
  selection.complete(succeededIds: outcome.succeededIds, failed: outcome.failed);
  if (!outcome.queued) {
    final grouped = <String, List<String>>{};
    for (final id in outcome.succeededIds) {
      final previous = previousById[id] ?? 'pending';
      grouped.putIfAbsent(previous, () => []).add(id);
    }
    selection.setUndoActions([for (final entry in grouped.entries) BatchUndoAction(operation: entry.key, ids: entry.value)]);
  }
  if (!context.mounted) return;
  await context.read<GalleryCubit>().refresh();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        outcome.queued ? '操作已加入待同步队列' : '已更新 ${outcome.succeededIds.length} 张照片${outcome.failed.isEmpty ? '' : '，${outcome.failed.length} 张失败'}',
      ),
      action: outcome.queued || outcome.succeededIds.isEmpty ? null : SnackBarAction(label: '撤销', onPressed: () => _undoBatch(context, batchId)),
    ),
  );
}

Future<void> _requestBatchAction(
  BuildContext context,
  String batchId,
  List<String> ids,
  String action,
) async {
  if (action == 'discard') {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: Text('确认弃用 ${ids.length} 张照片？'),
        content: const Text('照片不会立即从存储卡删除，但会被标记为弃用，并影响后续复制和导出范围。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('确认弃用'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
  }
  await _batchAction(context, batchId, ids, action);
}

Future<void> _showTagDialog(BuildContext context, String batchId, List<String> ids, {required bool remove}) async {
  final controller = TextEditingController();
  final tags = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(remove ? '批量删除标签' : '批量添加标签'),
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
  final operation = remove ? 'remove_tags' : 'add_tags';
  final outcome = await BirdCompanionScope.of(context).photoRepository.batchOperation(batchId, ids, operation, value: tags);
  selection.complete(succeededIds: outcome.succeededIds, failed: outcome.failed);
  if (!outcome.queued) {
    selection.setUndoActions([
      BatchUndoAction(operation: remove ? 'add_tags' : 'remove_tags', ids: outcome.succeededIds, value: tags),
    ]);
  }
  if (!context.mounted) return;
  await context.read<GalleryCubit>().refresh();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        outcome.queued ? '标签操作已加入待同步队列' : '已${remove ? '删除' : '添加'} ${outcome.succeededIds.length} 张照片的标签${outcome.failed.isEmpty ? '' : '，${outcome.failed.length} 张失败'}',
      ),
      action: outcome.queued || outcome.succeededIds.isEmpty ? null : SnackBarAction(label: '撤销', onPressed: () => _undoBatch(context, batchId)),
    ),
  );
}

Future<void> _undoBatch(BuildContext context, String batchId) async {
  if (!context.mounted) return;
  final selection = context.read<SelectionCubit>();
  final actions = selection.takeUndoActions();
  if (actions.isEmpty) return;
  selection.begin(preserveUndo: true);
  final failed = <String, String>{};
  final succeeded = <String>[];
  for (final action in actions) {
    final outcome = await BirdCompanionScope.of(context).photoRepository.batchOperation(
      batchId,
      action.ids,
      action.operation,
      value: action.value,
    );
    succeeded.addAll(outcome.succeededIds);
    failed.addAll(outcome.failed);
  }
  selection.complete(succeededIds: succeeded, failed: failed);
  if (!context.mounted) return;
  await context.read<GalleryCubit>().refresh();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(failed.isEmpty ? '已撤销最近一次批量操作' : '已撤销 ${succeeded.length} 张，${failed.length} 张撤销失败')),
  );
}
