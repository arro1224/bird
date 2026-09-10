import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_pills.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_sheet.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_entry_guard.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_version_batch_coordinator.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/selection_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/active_filter_summary.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_history_entry.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_add_device_button.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/gallery_search_dialog.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_masonry_grid.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/sort_sheet.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/review/domain/review_checkpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_bloc/flutter_bloc.dart';

class GalleryPage extends StatelessWidget {
  const GalleryPage({
    super.key,
    required this.batchId,
    this.batchName,
    this.createdAt,
    this.totalCount,
    this.pendingCount,
    this.keepCount,
    this.discardCount,
    this.initialQuery = const PhotoQuery(),
    this.restoreSavedView = true,
    this.rootMode = false,
    this.reviewContext,
  });
  final String batchId;
  final String? batchName;
  final DateTime? createdAt;
  final int? totalCount;
  final int? pendingCount;
  final int? keepCount;
  final int? discardCount;
  final PhotoQuery initialQuery;
  final bool restoreSavedView;
  final bool rootMode;
  final ReviewContext? reviewContext;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) =>
            GalleryCubit(
              BirdCompanionScope.of(context).photoRepository,
              batchId,
              BirdCompanionScope.of(context).refreshCoordinator,
              BirdCompanionScope.of(context).dataChangeBus,
              BirdCompanionScope.of(context).cache,
              BirdCompanionScope.of(context).pendingOperationStore,
              () => BirdCompanionScope.of(context).deviceSessionCubit.state.device?.id,
              BirdCompanionScope.of(context).reviewCheckpointStore,
              BirdCompanionScope.of(context).settingsStore,
            )..restoreAndRefresh(
              initialQuery,
              restoreSavedView: restoreSavedView,
            ),
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
    child: _GalleryView(
      batchId: batchId,
      batchName: batchName,
      createdAt: createdAt,
      totalCount: totalCount,
      pendingCount: pendingCount,
      keepCount: keepCount,
      discardCount: discardCount,
      rootMode: rootMode,
      reviewContext: reviewContext,
    ),
  );
}

class _GalleryView extends StatelessWidget {
  const _GalleryView({
    required this.batchId,
    this.batchName,
    this.createdAt,
    this.totalCount,
    this.pendingCount,
    this.keepCount,
    this.discardCount,
    required this.rootMode,
    this.reviewContext,
  });
  final String batchId;
  final String? batchName;
  final DateTime? createdAt;
  final int? totalCount;
  final int? pendingCount;
  final int? keepCount;
  final int? discardCount;
  final bool rootMode;
  final ReviewContext? reviewContext;

  ReviewContext get _reviewContext => reviewContext ?? ReviewContext(batchId: batchId, batchName: batchName);

  Future<void> _openCurrentBatchCopy(BuildContext context) async {
    final dependencies = BirdCompanionScope.of(context);
    try {
      // Start both frozen-v1 reads together, then navigate only with their
      // authoritative result instead of the album tab's retained batch id.
      final results = await Future.wait<Object?>([
        dependencies.batchRepository.current(),
        dependencies.jobRepository.page(),
      ]);
      final currentProject = results[0] as BatchSummary?;
      final jobs = results[1] as JobPage;
      if (!context.mounted) return;

      final decision = resolveCurrentCopyEntry(
        displayedBatchId: batchId,
        currentProject: currentProject,
        jobs: jobs.items,
      );
      if (!decision.enabled) {
        dependencies.dataChangeBus.publish(
          const {AppDataResource.batches, AppDataResource.photos},
          reason: 'album_copy_entry_revalidated',
        );
        BirdFeedback.error(context, decision.reason!);
        return;
      }
      await Navigator.of(context).pushNamed<void>(
        BirdRoutes.copyConfirmation,
        arguments: CopyConfirmationArgs(decision.batchId!),
      );
    } catch (error) {
      if (!context.mounted) return;
      final message = UserMessageMapper.fromError(error);
      BirdFeedback.error(context, '${message.title}：${message.message}');
    }
  }

  @override
  Widget build(BuildContext context) => BlocListener<SelectionCubit, SelectionState>(
    listenWhen: (previous, current) => previous.ids.isEmpty != current.ids.isEmpty,
    listener: (context, selection) => BirdShellNavigation.maybeOf(
      context,
    )?.setBottomNavigationVisible(selection.ids.isEmpty),
    child: BlocSelector<SelectionCubit, SelectionState, bool>(
      selector: (state) => state.ids.isEmpty,
      builder: (context, selectionIsEmpty) => PopScope(
        canPop: selectionIsEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !selectionIsEmpty) {
            context.read<SelectionCubit>().clear();
          }
        },
        child: Scaffold(
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
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: AppColors.brandDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
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
                        if (rootMode) const AlbumHistoryAppBarAction(),
                        if (rootMode)
                          IconButton(
                            key: const Key('album-copy-project-button'),
                            tooltip: '复制当前拍摄',
                            icon: const Icon(Icons.copy_all_outlined),
                            onPressed: totalCount != null && totalCount! <= 0 ? null : () => _openCurrentBatchCopy(context),
                          ),
                        if (rootMode)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: AlbumAddDeviceButton(
                              onPressed: () => Navigator.of(context, rootNavigator: true).pushNamed(
                                BirdRoutes.connection,
                                arguments: const ConnectionArgs(entryMode: ConnectionEntryMode.addOrSwitch),
                              ),
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
                              useRootNavigator: true,
                              isScrollControlled: true,
                              showDragHandle: false,
                              backgroundColor: Colors.transparent,
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
                              if (value == 'review') {
                                Navigator.of(context).pushNamed(
                                  BirdRoutes.groupReview,
                                  arguments: GroupReviewArgs(
                                    batchId,
                                    reviewContext: _reviewContext,
                                  ),
                                );
                              } else if (value == 'scenes') {
                                Navigator.of(context).pushNamed(
                                  BirdRoutes.scenes,
                                  arguments: SceneListArgs(
                                    batchId,
                                    batchName: batchName,
                                    totalCount: totalCount,
                                    reviewContext: _reviewContext,
                                  ),
                                );
                              } else if (value == 'copy') {
                                Navigator.of(context).pushNamed(
                                  BirdRoutes.copyConfirmation,
                                  arguments: CopyConfirmationArgs(batchId),
                                );
                              } else {
                                showModalBottomSheet(
                                  context: context,
                                  useRootNavigator: true,
                                  useSafeArea: true,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
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
                                child: ListTile(leading: Icon(Icons.auto_awesome_mosaic_outlined), title: Text('挑选连拍照片')),
                              ),
                              PopupMenuItem(
                                value: 'copy',
                                child: ListTile(
                                  leading: Icon(Icons.copy_all_outlined),
                                  title: Text('复制当前拍摄'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'sort',
                                child: ListTile(leading: Icon(Icons.sort_rounded), title: Text('排序方式')),
                              ),
                            ],
                          ),
                      ],
              ),
            ),
          ),
          body: BlocBuilder<GalleryCubit, GalleryState>(
            builder: (context, state) {
              if (state.loading && state.items.isEmpty && !state.filtering) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.error != null && state.items.isEmpty) {
                final message = UserMessageMapper.fromError(state.error!);
                return NaturalBackdrop(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ErrorNotice(
                        title: '暂时无法加载照片',
                        message: message.message,
                        onRetry: () => context.read<GalleryCubit>().refresh(),
                      ),
                    ),
                  ),
                );
              }
              return NaturalBackdrop(
                child: Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: () => context.read<GalleryCubit>().refresh(),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          final prefetchDistance = MediaQuery.sizeOf(context).height * .75;
                          if (state.error == null && notification.metrics.extentAfter < prefetchDistance) {
                            context.read<GalleryCubit>().loadMore();
                          }
                          return false;
                        },
                        child: CustomScrollView(
                          key: PageStorageKey<String>('photo-gallery-scroll-$batchId'),
                          scrollCacheExtent: const ScrollCacheExtent.viewport(.75),
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: _GalleryHeader(
                                state: state,
                                rootMode: rootMode,
                                batchId: batchId,
                                batchName: batchName,
                                createdAt: createdAt,
                                totalCount: totalCount,
                                pendingCount: pendingCount,
                                keepCount: keepCount,
                                discardCount: discardCount,
                                reviewContext: _reviewContext,
                              ),
                            ),
                            if (state.query.activeLabels.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                                  child: ActiveFilterSummary(
                                    labels: state.query.activeLabels,
                                    onClear: () => context.read<GalleryCubit>().refresh(
                                      query: const PhotoQuery(),
                                    ),
                                  ),
                                ),
                              ),
                            if (state.items.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _GalleryEmptyState(
                                  filtering: state.filtering,
                                  incomplete: !state.resultComplete,
                                  onReset: () => context.read<GalleryCubit>().refresh(query: const PhotoQuery()),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                                sliver: PhotoMasonryGrid(
                                  photos: state.items,
                                  crossAxisCount: state.gridColumns,
                                  itemBuilder: (context, photo, index) => _SelectablePhotoTile(
                                    photo: photo,
                                    compact: rootMode,
                                    showRatingOverlay: state.showRatingOverlay,
                                    onTap: () async {
                                      final selection = context.read<SelectionCubit>();
                                      if (selection.state.ids.isEmpty) {
                                        final gallery = context.read<GalleryCubit>();
                                        final photoIds = state.items.map((item) => item.id).toList(growable: false);
                                        final photoContext = _reviewContext.openPhotos(
                                          photoIds,
                                          initialIndex: index,
                                        );
                                        final dependencies = BirdCompanionScope.of(context);
                                        final batchCubit = rootMode ? context.read<BatchListCubit>() : null;
                                        final batchBeforeReview = batchCubit?.state.current;
                                        final reviewChanges = <ReviewDecisionChanged>[];
                                        final reviewSubscription = rootMode
                                            ? dependencies.dataChangeBus.changes
                                                  .where(
                                                    (change) => change is ReviewDecisionChanged && change.projectId == batchId,
                                                  )
                                                  .cast<ReviewDecisionChanged>()
                                                  .listen(reviewChanges.add)
                                            : null;
                                        final deviceId = dependencies.deviceSessionCubit.state.device?.id.trim();
                                        if (deviceId?.isNotEmpty == true) {
                                          unawaited(
                                            dependencies.reviewCheckpointStore.save(
                                              ReviewCheckpoint.fromContext(
                                                deviceId: deviceId!,
                                                context: photoContext,
                                                query: state.query,
                                              ),
                                            ),
                                          );
                                        }
                                        try {
                                          await Navigator.of(context).pushNamed(
                                            BirdRoutes.photoDetail,
                                            arguments: PhotoDetailArgs.fromReview(
                                              photoContext,
                                              fileId: photo.id,
                                              totalCount: totalCount,
                                              hasMoreSequence: state.hasMore,
                                              loadMoreSequence: () async {
                                                await gallery.loadMore();
                                                final current = gallery.state;
                                                return PhotoSequencePage(
                                                  ids: current.items.map((item) => item.id).toList(growable: false),
                                                  hasMore: current.hasMore,
                                                );
                                              },
                                            ),
                                          );
                                        } finally {
                                          await reviewSubscription?.cancel();
                                        }
                                        if (batchCubit != null && batchBeforeReview != null && reviewChanges.isNotEmpty && !batchCubit.isClosed) {
                                          batchCubit.reconcileReviewChanges(
                                            batchBeforeReview,
                                            reviewChanges,
                                          );
                                        }
                                      } else {
                                        selection.toggle(photo.id);
                                      }
                                    },
                                    onLongPress: () => context.read<SelectionCubit>().toggle(photo.id),
                                  ),
                                ),
                              ),
                            if (state.items.isNotEmpty && (state.loading || state.hasMore || state.error != null))
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: state.error == null ? 52 : 68,
                                  child: Center(
                                    child: state.loading
                                        ? const SizedBox.square(
                                            dimension: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2.4),
                                          )
                                        : state.error != null
                                        ? OutlinedButton.icon(
                                            onPressed: () => context.read<GalleryCubit>().loadMore(),
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                            ),
                                            label: const Text(
                                              '加载更多失败，点击重试',
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (state.filtering)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: rootMode ? 76 : 12,
                        child: _FilterScanProgress(
                          scannedCount: state.scannedCount,
                          matchedCount: state.matchedCount,
                          onCancel: context.read<GalleryCubit>().cancelFiltering,
                        ),
                      ),
                    if (rootMode)
                      BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
                        bloc: BirdCompanionScope.of(context).deviceSessionCubit,
                        builder: (context, session) => !session.isConnected || state.cacheScope == PhotoCacheScope.partial
                            ? const Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: _OfflinePreservedNotice(),
                              )
                            : const SizedBox.shrink(),
                      ),
                    _SelectionActionOverlay(batchId: batchId),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _SelectablePhotoTile extends StatelessWidget {
  const _SelectablePhotoTile({
    required this.photo,
    required this.onTap,
    required this.onLongPress,
    required this.compact,
    required this.showRatingOverlay,
  });

  final PhotoSummary photo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool compact;
  final bool showRatingOverlay;

  @override
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    final session = dependencies.deviceSessionCubit.state;
    return BlocSelector<SelectionCubit, SelectionState, ({bool selected, bool failed})>(
      selector: (state) => (
        selected: state.ids.contains(photo.id),
        failed: state.failed.containsKey(photo.id),
      ),
      builder: (_, selection) => PhotoTile(
        key: ValueKey(photo.id),
        photo: photo,
        compact: compact,
        showRatingOverlay: showRatingOverlay,
        selected: selection.selected,
        operationFailed: selection.failed,
        deviceNamespace: session.device?.id,
        mediaAssetLoader: dependencies.mediaAssetService,
        mediaAssetCoordinator: dependencies.mediaAssetCoordinator,
        allowNetworkFallback: session.isConnected,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _SelectionActionOverlay extends StatefulWidget {
  const _SelectionActionOverlay({required this.batchId});

  final String batchId;

  @override
  State<_SelectionActionOverlay> createState() => _SelectionActionOverlayState();
}

class _SelectionActionOverlayState extends State<_SelectionActionOverlay> {
  var _creatingSelection = false;

  @override
  Widget build(BuildContext context) => BlocBuilder<SelectionCubit, SelectionState>(
    builder: (context, selection) {
      if (selection.ids.isEmpty) return const SizedBox.shrink();
      final ids = selection.ids.toList(growable: false);
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SelectionActionBar(
          count: ids.length,
          busy: selection.submitting || _creatingSelection,
          failedCount: selection.failed.length,
          onClear: () => context.read<SelectionCubit>().clear(),
          onAddTags: () => _showTagDialog(context, widget.batchId, ids, remove: false),
          onRemoveTags: () => _showTagDialog(context, widget.batchId, ids, remove: true),
          onAction: (action) => _requestBatchAction(context, widget.batchId, ids, action),
          onCopy: () => _copySelected(context, ids),
        ),
      );
    },
  );

  /// 创建不可变选择快照（§13.3）后进入复制配置页，范围固定「已选择 N 张」。
  Future<void> _copySelected(BuildContext context, List<String> ids) async {
    if (_creatingSelection) return;
    setState(() => _creatingSelection = true);
    try {
      final dependencies = BirdCompanionScope.of(context);
      final snapshot = await dependencies.copyRepository.createSelection(
        widget.batchId,
        ids,
        clientRevision: 0,
      );
      final galleryState = context.read<GalleryCubit>().state;
      final discardedCount = galleryState.items
          .where(
            (photo) =>
                ids.contains(photo.id) &&
                KeepStateWireValue.fromWire(photo.keepState) ==
                    KeepState.discard,
          )
          .length;
      if (!mounted) return;
      await Navigator.of(context).pushNamed<void>(
        BirdRoutes.copyConfirmation,
        arguments: CopyConfirmationArgs(
          widget.batchId,
          scope: 'selected_assets',
          selectionId: snapshot.selectionId,
          selectionPhotoCount: snapshot.assetCount,
          selectionDiscardedCount: discardedCount,
        ),
      );
      if (!mounted) return;
      context.read<SelectionCubit>().clear();
    } catch (error) {
      if (!mounted) return;
      final message = UserMessageMapper.fromError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${message.title}：${message.message}')),
      );
    } finally {
      if (mounted) setState(() => _creatingSelection = false);
    }
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({
    required this.state,
    required this.rootMode,
    required this.batchId,
    this.batchName,
    this.createdAt,
    this.totalCount,
    this.pendingCount,
    this.keepCount,
    this.discardCount,
    required this.reviewContext,
  });
  final GalleryState state;
  final bool rootMode;
  final String batchId;
  final String? batchName;
  final DateTime? createdAt;
  final int? totalCount;
  final int? pendingCount;
  final int? keepCount;
  final int? discardCount;
  final ReviewContext reviewContext;

  @override
  Widget build(BuildContext context) => BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
    bloc: BirdCompanionScope.of(context).deviceSessionCubit,
    builder: (context, session) {
      final offline = !session.isConnected;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.pendingOperationCount > 0 || state.conflictOperationCount > 0) ...[
              _PendingSyncNotice(
                pendingCount: state.pendingOperationCount,
                conflictCount: state.conflictOperationCount,
                onOpenConflict: state.firstConflictFileId == null
                    ? null
                    : () => _openConflictPhoto(
                        context,
                        state.firstConflictFileId!,
                      ),
              ),
              const SizedBox(height: 12),
            ],
            if (rootMode) ...[
              if (state.fromCache) ...[
                _OfflineSnapshotNotice(
                  cachedAt: state.cachedAt,
                  loadedCount: state.items.length,
                  totalCount: totalCount,
                  resultComplete: state.resultComplete,
                  offline: !session.isConnected,
                ),
                const SizedBox(height: 12),
              ],
              _AlbumDeviceArea(offline: offline),
              const SizedBox(height: 16),
              _QuickFilters(
                query: state.query,
                pendingCount: pendingCount,
                keepCount: keepCount,
                offline: offline,
              ),
              const SizedBox(height: 18),
              _AlbumBatchHeading(
                batchId: batchId,
                batchName: batchName,
                createdAt: createdAt,
                offline: offline,
              ),
              const SizedBox(height: 8),
            ] else ...[
              if (state.fromCache) ...[
                _OfflineSnapshotNotice(
                  cachedAt: state.cachedAt,
                  loadedCount: state.items.length,
                  totalCount: totalCount,
                  resultComplete: state.resultComplete,
                  offline: !session.isConnected,
                ),
                const SizedBox(height: 12),
              ],
              _QuickFilters(query: state.query),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '按${_sortLabel(state.query.sort)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.brandDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '调整排序',
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      useSafeArea: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => SortSheet(
                        value: state.query.sort,
                        onChanged: (sort) => context.read<GalleryCubit>().refresh(
                          query: state.query.copyWith(sort: sort, clearCursor: true),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.grid_view_rounded),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );

  void _openConflictPhoto(BuildContext context, String fileId) {
    final photoIds = state.items.map((item) => item.id).toList(growable: true);
    if (!photoIds.contains(fileId)) photoIds.insert(0, fileId);
    final photoContext = reviewContext.openPhotos(
      photoIds,
      initialIndex: photoIds.indexOf(fileId),
    );
    Navigator.of(context).pushNamed(
      BirdRoutes.photoDetail,
      arguments: PhotoDetailArgs.fromReview(
        photoContext,
        fileId: fileId,
        totalCount: photoIds.length,
      ),
    );
  }
}

class _AlbumDeviceArea extends StatelessWidget {
  const _AlbumDeviceArea({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    if (offline) {
      return _OfflineConnectionBanner(
        onReconnect: () => openReconnectConnection(context),
      );
    }
    return const _AlbumDeviceAlert();
  }
}

class _OfflineConnectionBanner extends StatelessWidget {
  const _OfflineConnectionBanner({required this.onReconnect});

  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.danger.withValues(alpha: .28)),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.danger,
          child: Icon(Icons.link_off_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '设备连接已断开',
            style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onReconnect,
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('重新连接'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        ),
      ],
    ),
  );
}

class _AlbumDeviceAlert extends StatelessWidget {
  const _AlbumDeviceAlert();

  @override
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    return BlocBuilder<DeviceStatusCubit, DeviceStatusState>(
      builder: (context, statusState) => BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
        bloc: dependencies.deviceSessionCubit,
        builder: (context, session) {
          final status = statusState.status;
          final message = _message(status, session);
          if (status == null) {
            return const _AlbumStatusLoading();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeviceStatusPills(
                status: status,
                session: session,
                onTap: () => showDeviceStatusSheet(
                  context,
                  status: status,
                  session: session,
                  onReconnect: () {
                    Navigator.of(context).pop();
                    openReconnectConnection(context);
                  },
                  onOpenDetails: () {
                    Navigator.of(context).pop();
                    final navigation = BirdShellNavigation.maybeOf(context);
                    if (navigation != null) {
                      navigation.openTabRoute(2, BirdRoutes.settingsDeviceDetails);
                    } else {
                      Navigator.of(context).pushNamed(BirdRoutes.settingsDeviceDetails);
                    }
                  },
                  onOpenTask: status.currentJob == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          BirdShellNavigation.maybeOf(context)?.selectTab(1);
                        },
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                _AlbumExceptionBanner(message: message),
              ],
            ],
          );
        },
      ),
    );
  }

  String? _message(DeviceStatus? status, DeviceSessionState session) {
    if (!session.isConnected) return '设备连接已断开';
    if (status == null) return null;
    if (status.hasError) return status.errorMessage ?? '设备发生异常，请检查后重试';
    if (status.temperatureCelsius != null && status.temperatureCelsius! >= 70) {
      return '设备温度偏高，请暂停处理并检查散热';
    }
    if (!status.card.inserted || !status.card.readable) return '存储卡不可用，请检查后重试';
    return null;
  }
}

class _AlbumStatusLoading extends StatelessWidget {
  const _AlbumStatusLoading();

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.paperStrong,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.outline),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 10),
        Text('正在读取盒子状态'),
      ],
    ),
  );
}

class _AlbumExceptionBanner extends StatelessWidget {
  const _AlbumExceptionBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.danger.withValues(alpha: .28)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _AlbumBatchHeading extends StatelessWidget {
  const _AlbumBatchHeading({
    required this.batchId,
    this.batchName,
    this.createdAt,
    this.offline = false,
  });

  final String batchId;
  final String? batchName;
  final DateTime? createdAt;
  final bool offline;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AppColors.brandDark,
          fontSize: 20,
        ),
      ),
      if (offline)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '这些照片已保存在手机上；重新连接后会自动更新你的修改',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
          ),
        )
      else
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AlbumHistorySecondaryAction(),
          ),
        ),
    ],
  );

  String get _displayName {
    final name = batchName?.trim().isNotEmpty == true ? batchName!.trim() : batchId;
    final date = createdAt?.toLocal();
    if (offline && date != null && date.year >= 2000) {
      final cleanName = name.replaceFirst(RegExp(r'^\d{4}[./-]\d{2}[./-]\d{2}\s*'), '');
      return '$cleanName · ${date.month}月${date.day}日';
    }
    if (date == null || date.year < 2000 || name.contains('${date.year}')) return name;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}.${two(date.month)}.${two(date.day)} $name';
  }
}

class _OfflineSnapshotNotice extends StatelessWidget {
  const _OfflineSnapshotNotice({
    this.cachedAt,
    required this.loadedCount,
    this.totalCount,
    required this.resultComplete,
    required this.offline,
  });

  final DateTime? cachedAt;
  final int loadedCount;
  final int? totalCount;
  final bool resultComplete;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final savedAt = cachedAt == null ? '' : ' · 保存于 ${_time(cachedAt!)}';
    final completeness = resultComplete
        ? '已使用完整候选缓存筛选'
        : totalCount == null
        ? '仅在已缓存照片中查找，结果可能不完整'
        : '仅在已缓存的 $loadedCount / $totalCount 张照片中查找，结果可能不完整';
    final color = offline || !resultComplete ? AppColors.danger : AppColors.brand;
    final background = offline || !resultComplete ? AppColors.dangerSoft : AppColors.brandSoft;
    final message = offline ? '设备暂时无法连接；$completeness$savedAt' : '使用本地缓存加速筛选；$completeness$savedAt';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(offline ? Icons.link_off_rounded : Icons.offline_bolt_rounded, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: TextStyle(color: color)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => openReconnectConnection(context),
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

class _PendingSyncNotice extends StatelessWidget {
  const _PendingSyncNotice({
    required this.pendingCount,
    required this.conflictCount,
    this.onOpenConflict,
  });

  final int pendingCount;
  final int conflictCount;
  final VoidCallback? onOpenConflict;

  @override
  Widget build(BuildContext context) {
    final hasConflict = conflictCount > 0;
    final text = hasConflict ? '有 $conflictCount 条照片修改与盒子版本冲突，需在照片详情中处理。' : '有 $pendingCount 条照片修改保存在手机上，重连后只会同步到当前设备。';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: hasConflict ? AppColors.dangerSoft : AppColors.amberLight,
        border: Border.all(color: (hasConflict ? AppColors.danger : AppColors.pending).withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(hasConflict ? Icons.warning_amber_rounded : Icons.cloud_upload_outlined, color: hasConflict ? AppColors.danger : AppColors.pending),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: hasConflict ? AppColors.danger : AppColors.ink)),
          ),
          if (hasConflict && onOpenConflict != null)
            IconButton(
              key: const Key('gallery-conflict-open-button'),
              tooltip: '处理冲突照片',
              onPressed: onOpenConflict,
              icon: const Icon(Icons.chevron_right_rounded),
              color: AppColors.danger,
            ),
        ],
      ),
    );
  }
}

class _OfflinePreservedNotice extends StatelessWidget {
  const _OfflinePreservedNotice();

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.paperStrong.withValues(alpha: .97),
    elevation: 3,
    shadowColor: AppColors.brandDark.withValues(alpha: .14),
    borderRadius: BorderRadius.circular(14),
    child: Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.brand,
            child: Icon(Icons.check_rounded, color: AppColors.cream, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '已保留当前浏览与筛选状态',
              style: TextStyle(
                color: AppColors.brandDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuickFilters extends StatelessWidget {
  const _QuickFilters({
    required this.query,
    this.pendingCount,
    this.keepCount,
    this.offline = false,
  });

  final PhotoQuery query;
  final int? pendingCount;
  final int? keepCount;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final values = <(String, String?, int?, Color?, IconData?)>[
      ('全部', null, null, null, null),
      ('待确认', 'pending', offline ? null : pendingCount, offline ? null : AppColors.pending, offline ? null : Icons.circle),
      ('已保留', 'keep', offline ? null : keepCount, offline ? null : AppColors.brand, offline ? null : Icons.circle),
      ('已弃选', 'discard', null, null, null),
      if (!offline) ('精选', 'featured', null, AppColors.amber, Icons.star_rounded),
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
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: active ? AppColors.cream : AppColors.ink,
                  fontSize: 13,
                ),
                avatar: entry.$5 == null ? null : Icon(entry.$5, size: entry.$5 == Icons.star_rounded ? 18 : 9, color: entry.$4),
                label: Text(
                  entry.$3 == null ? entry.$1 : '${entry.$1} ${_formatCount(entry.$3!)}',
                ),
                onSelected: (_) => context.read<GalleryCubit>().refresh(query: _quickQuery(query, entry.$2)),
              ),
            );
          }),
          ActionChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            avatar: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('筛选'),
            onPressed: () => showModalBottomSheet(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              showDragHandle: false,
              backgroundColor: Colors.transparent,
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
  final value = await showDialog<String>(
    context: context,
    builder: (_) => GallerySearchDialog(initialValue: cubit.state.query.search ?? ''),
  );
  if (value == null || !context.mounted) return;
  await cubit.refresh(query: cubit.state.query.copyWith(search: value, clearCursor: true));
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
  'score_desc' => '照片质量从高到低',
  'confidence_desc' => '识别度从高到低',
  'recommended_desc' => '系统推荐优先',
  _ => '拍摄时间最新',
};

String _formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value.isNegative ? '-' : '');
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

class _GalleryEmptyState extends StatelessWidget {
  const _GalleryEmptyState({
    required this.onReset,
    required this.filtering,
    required this.incomplete,
  });
  final VoidCallback onReset;
  final bool filtering;
  final bool incomplete;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(filtering ? Icons.manage_search_rounded : Icons.photo_library_outlined, size: 52),
        const SizedBox(height: 12),
        Text(
          filtering
              ? '正在筛选照片…'
              : incomplete
              ? '已缓存照片中没有符合条件的结果'
              : '没有符合条件的照片',
        ),
        const SizedBox(height: 8),
        if (!filtering) OutlinedButton(onPressed: onReset, child: const Text('清除筛选')),
      ],
    ),
  );
}

class _FilterScanProgress extends StatelessWidget {
  const _FilterScanProgress({
    required this.scannedCount,
    required this.matchedCount,
    required this.onCancel,
  });

  final int scannedCount;
  final int matchedCount;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppColors.brandSoft,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.brand.withValues(alpha: .22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '正在筛选 · 已扫描 $scannedCount 张 · 命中 $matchedCount 张',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ),
        const SizedBox(height: 6),
        const LinearProgressIndicator(minHeight: 3),
      ],
    ),
  );
}

Future<void> _batchAction(BuildContext context, String batchId, List<String> ids, String action) async {
  final selection = context.read<SelectionCubit>();
  final gallery = context.read<GalleryCubit>();
  if (selection.state.submitting) return;
  final previousById = {
    for (final photo in gallery.state.items.where((photo) => ids.contains(photo.id))) photo.id: photo.keepState ?? 'pending',
  };
  selection.begin();
  final outcome = await _batchOperationByPhotoVersion(
    context,
    batchId,
    ids,
    action,
  );
  selection.complete(succeededIds: outcome.succeededIds, failed: outcome.failed);
  final keepState = _keepStateForOperation(action);
  if (!gallery.isClosed && keepState != null) {
    gallery.applyKeepState(outcome.succeededIds, keepState);
  }
  if (!outcome.queued) {
    final grouped = <String, List<String>>{};
    for (final id in outcome.succeededIds) {
      final previous = previousById[id] ?? 'pending';
      grouped.putIfAbsent(previous, () => []).add(id);
    }
    selection.setUndoActions([for (final entry in grouped.entries) BatchUndoAction(operation: entry.key, ids: entry.value)]);
  }
  if (!context.mounted) return;
  await gallery.refresh();
  if (outcome.queued) {
    BirdFeedback.queued(context, '修改已保存在手机上，重新连接后会自动更新');
  } else if (outcome.succeededIds.isEmpty) {
    BirdFeedback.error(context, '${outcome.failed.length} 张照片操作失败，请重试');
  } else if (outcome.failed.isNotEmpty) {
    BirdFeedback.error(
      context,
      '已更新 ${outcome.succeededIds.length} 张，${outcome.failed.length} 张失败',
    );
  } else {
    BirdFeedback.undo(
      context,
      '已更新 ${outcome.succeededIds.length} 张照片',
      onUndo: () => _undoBatch(context, batchId),
    );
  }
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
        title: Text('确认弃选 ${ids.length} 张照片？'),
        content: const Text('照片不会立即从存储卡删除，但会被标记为弃选，并影响后续复制和导出范围。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('确认弃选'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
  }
  await _batchAction(context, batchId, ids, action);
}

Future<void> _showTagDialog(BuildContext context, String batchId, List<String> ids, {required bool remove}) async {
  var draft = '';
  final tags = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(remove ? '批量删除标签' : '批量添加标签'),
      content: TextField(
        decoration: const InputDecoration(hintText: '例如：水鸟, 晨拍'),
        onChanged: (value) => draft = value,
        onSubmitted: (value) => Navigator.pop(dialogContext, parseUserTags(value)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
            dialogContext,
            parseUserTags(draft),
          ),
          child: const Text('应用'),
        ),
      ],
    ),
  );
  if (tags == null || tags.isEmpty || !context.mounted) return;
  final selection = context.read<SelectionCubit>();
  selection.begin();
  final operation = remove ? 'remove_tags' : 'add_tags';
  final outcome = await _batchOperationByPhotoVersion(
    context,
    batchId,
    ids,
    operation,
    value: tags,
  );
  selection.complete(succeededIds: outcome.succeededIds, failed: outcome.failed);
  if (!outcome.queued) {
    selection.setUndoActions([
      BatchUndoAction(operation: remove ? 'add_tags' : 'remove_tags', ids: outcome.succeededIds, value: tags),
    ]);
  }
  if (!context.mounted) return;
  await context.read<GalleryCubit>().refresh();
  if (outcome.queued) {
    BirdFeedback.queued(context, '标签已保存在手机上，重新连接后会自动更新');
  } else if (outcome.succeededIds.isEmpty) {
    BirdFeedback.error(context, '${outcome.failed.length} 张照片标签操作失败');
  } else if (outcome.failed.isNotEmpty) {
    BirdFeedback.error(
      context,
      '已${remove ? '删除' : '添加'} ${outcome.succeededIds.length} 张的标签，${outcome.failed.length} 张失败',
    );
  } else {
    BirdFeedback.undo(
      context,
      '已${remove ? '删除' : '添加'} ${outcome.succeededIds.length} 张照片的标签',
      onUndo: () => _undoBatch(context, batchId),
    );
  }
}

Future<void> _undoBatch(BuildContext context, String batchId) async {
  if (!context.mounted) return;
  final selection = context.read<SelectionCubit>();
  final gallery = context.read<GalleryCubit>();
  final actions = selection.takeUndoActions();
  if (actions.isEmpty) return;
  selection.begin(preserveUndo: true);
  final failed = <String, String>{};
  final succeeded = <String>[];
  for (final action in actions) {
    final outcome = await _batchOperationByPhotoVersion(
      context,
      batchId,
      action.ids,
      action.operation,
      value: action.value,
    );
    succeeded.addAll(outcome.succeededIds);
    failed.addAll(outcome.failed);
    final keepState = _keepStateForOperation(action.operation);
    if (!gallery.isClosed && keepState != null) {
      gallery.applyKeepState(outcome.succeededIds, keepState);
    }
  }
  selection.complete(succeededIds: succeeded, failed: failed);
  if (!context.mounted) return;
  await gallery.refresh();
  if (failed.isEmpty) {
    BirdFeedback.success(context, '已撤销最近一次批量操作');
  } else {
    BirdFeedback.error(
      context,
      '已撤销 ${succeeded.length} 张，${failed.length} 张撤销失败',
    );
  }
}

KeepState? _keepStateForOperation(String operation) => switch (operation) {
  'pending' => KeepState.pending,
  'keep' => KeepState.keep,
  'discard' => KeepState.discard,
  'featured' => KeepState.featured,
  _ => null,
};

Future<BatchOperationOutcome> _batchOperationByPhotoVersion(
  BuildContext context,
  String batchId,
  List<String> ids,
  String operation, {
  Object? value,
}) async {
  final dependencies = BirdCompanionScope.of(context);
  return PhotoVersionBatchCoordinator(
    dependencies.photoRepository,
    dependencies.reviewRepository,
  ).apply(
    projectId: batchId,
    fileIds: ids,
    currentPhotos: context.read<GalleryCubit>().state.items,
    operation: operation,
    value: value,
  );
}
