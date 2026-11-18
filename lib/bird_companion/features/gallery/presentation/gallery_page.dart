import 'package:aves/bird_companion/core/widgets/navigation_guard.dart';
import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_sheet.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_entry_guard.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/gallery_timing.dart';
import 'package:aves/bird_companion/features/gallery/domain/batch_tag_change.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_version_batch_coordinator.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/selection_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/active_filter_summary.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/batch_add_tags_dialog.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/batch_remove_tags_dialog.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_history_entry.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_add_device_button.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/gallery_candidate_notice.dart';
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
    this.timing,
    this.batchSummary,
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
  final GalleryTiming? timing;
  final BatchSummary? batchSummary;

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
                BirdCompanionScope.of(context).batchRepository is BatchSummaryReader ? BirdCompanionScope.of(context).batchRepository as BatchSummaryReader : null,
              )
              ..seedReviewCounts(
                pendingCount: pendingCount,
                keepCount: keepCount,
                discardCount: discardCount,
              )
              ..restoreAndRefresh(
                initialQuery,
                restoreSavedView: restoreSavedView,
                timing: timing,
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
    child: _GallerySummaryBinding(
      summary: batchSummary,
      child: _GalleryView(
        batchId: batchId,
        batchName: batchName,
        createdAt: createdAt,
        totalCount: totalCount,
        rootMode: rootMode,
        reviewContext: reviewContext,
      ),
    ),
  );
}

class _GallerySummaryBinding extends StatefulWidget {
  const _GallerySummaryBinding({required this.summary, required this.child});
  final BatchSummary? summary;
  final Widget child;
  @override
  State<_GallerySummaryBinding> createState() => _GallerySummaryBindingState();
}

class _GallerySummaryBindingState extends State<_GallerySummaryBinding> {
  void _apply() {
    final summary = widget.summary;
    if (summary?.countsDeviceId == null) return;
    context.read<GalleryCubit>().applyBatchSummary(summary!, deviceId: summary.countsDeviceId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  @override
  void didUpdateWidget(_GallerySummaryBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.summary != oldWidget.summary) _apply();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _GalleryView extends StatelessWidget {
  const _GalleryView({
    required this.batchId,
    this.batchName,
    this.createdAt,
    this.totalCount,
    required this.rootMode,
    this.reviewContext,
  });
  final String batchId;
  final String? batchName;
  final DateTime? createdAt;
  final int? totalCount;
  final bool rootMode;
  final ReviewContext? reviewContext;

  ReviewContext get _reviewContext => reviewContext ?? ReviewContext(batchId: batchId, batchName: batchName);

  bool _compactAlbumToolbar(BuildContext context) => MediaQuery.sizeOf(context).width < 360 || MediaQuery.textScalerOf(context).scale(28) > 36;

  bool _albumToolbarNeedsMenu(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width < 320 || width < 400 && MediaQuery.textScalerOf(context).scale(24) > 42;
  }

  void _addOrSwitchAlbumDevice(BuildContext context) {
    unawaited(
      guardBirdNavigation(
        context,
        () => Navigator.of(context, rootNavigator: true).pushNamed<void>(
          BirdRoutes.connection,
          arguments: const ConnectionArgs(entryMode: ConnectionEntryMode.addOrSwitch),
        ),
      ),
    );
  }

  Future<void> _openCurrentBatchCopy(BuildContext context) => guardBirdNavigation<void>(context, () async {
    final gallery = context.read<GalleryCubit>();
    if (!gallery.state.resultComplete) return;
    final dependencies = BirdCompanionScope.of(context);
    final sourceDevice = dependencies.deviceSessionCubit.state.device;
    try {
      // Start both frozen-v1 reads together, then navigate only with their
      // authoritative result instead of the album tab's retained batch id.
      final results = await Future.wait<Object?>([
        dependencies.batchRepository.current(),
        dependencies.jobRepository.page(),
      ]);
      final currentProject = results[0] as BatchSummary?;
      final jobs = results[1] as JobPage;
      if (!context.mounted || !gallery.state.resultComplete) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final currentDevice = dependencies.deviceSessionCubit.state.device;
      if (sourceDevice?.id != currentDevice?.id || sourceDevice?.baseUri != currentDevice?.baseUri) return;

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
        arguments: CopyConfirmationArgs(
          decision.batchId!,
          filter: context.read<GalleryCubit>().state.query.toCopyFilterV1(),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      final message = UserMessageMapper.fromError(error);
      BirdFeedback.error(context, '${message.title}：${message.message}');
    }
  });

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
                titleSpacing: rootMode && selection.ids.isEmpty && _compactAlbumToolbar(context) ? 8 : null,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          color: AppColors.brandDark,
                          fontSize: _compactAlbumToolbar(context) ? 24 : 28,
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
                        if (rootMode) _AlbumStatusAction(compact: _compactAlbumToolbar(context)),
                        if (rootMode) const AlbumHistoryAppBarAction(),
                        if (rootMode)
                          BlocSelector<GalleryCubit, GalleryState, bool>(
                            selector: (state) => state.resultComplete,
                            builder: (context, complete) {
                              final canCopy = complete && (totalCount == null || totalCount! > 0);
                              if (_albumToolbarNeedsMenu(context)) {
                                return PopupMenuButton<bool>(
                                  tooltip: '更多操作',
                                  onSelected: (copy) {
                                    if (copy) {
                                      unawaited(_openCurrentBatchCopy(context));
                                    } else {
                                      _addOrSwitchAlbumDevice(context);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(value: true, enabled: canCopy, child: const Text('复制当前拍摄')),
                                    const PopupMenuItem(value: false, child: Text('新增或切换设备')),
                                  ],
                                );
                              }
                              return IconButton(
                                key: const Key('album-copy-project-button'),
                                tooltip: '复制当前拍摄',
                                icon: const Icon(Icons.copy_all_outlined),
                                onPressed: canCopy ? () => _openCurrentBatchCopy(context) : null,
                              );
                            },
                          ),
                        if (rootMode && !_albumToolbarNeedsMenu(context))
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: AlbumAddDeviceButton(
                              onPressed: () => _addOrSwitchAlbumDevice(context),
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
                            onPressed: () => guardBirdNavigation(
                              context,
                              () => showModalBottomSheet(
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
                          ),
                        if (!rootMode)
                          PopupMenuButton<String>(
                            tooltip: '更多操作',
                            onSelected: (value) {
                              if (value == 'review') {
                                guardBirdNavigation(
                                  context,
                                  () => Navigator.of(context).pushNamed(
                                    BirdRoutes.groupReview,
                                    arguments: GroupReviewArgs(
                                      batchId,
                                      reviewContext: _reviewContext,
                                    ),
                                  ),
                                );
                              } else if (value == 'scenes') {
                                guardBirdNavigation(
                                  context,
                                  () => Navigator.of(context).pushNamed(
                                    BirdRoutes.scenes,
                                    arguments: SceneListArgs(
                                      batchId,
                                      batchName: batchName,
                                      totalCount: totalCount,
                                      reviewContext: _reviewContext,
                                    ),
                                  ),
                                );
                              } else if (value == 'copy') {
                                final state = context.read<GalleryCubit>().state;
                                if (!state.resultComplete) return;
                                guardBirdNavigation(
                                  context,
                                  () => Navigator.of(context).pushNamed(
                                    BirdRoutes.copyConfirmation,
                                    arguments: CopyConfirmationArgs(
                                      batchId,
                                      filter: state.query.toCopyFilterV1(),
                                    ),
                                  ),
                                );
                              } else {
                                guardBirdNavigation(
                                  context,
                                  () => showModalBottomSheet(
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
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'scenes',
                                child: ListTile(leading: Icon(Icons.account_tree_outlined), title: Text('按场景浏览')),
                              ),
                              const PopupMenuItem(
                                value: 'review',
                                child: ListTile(leading: Icon(Icons.auto_awesome_mosaic_outlined), title: Text('挑选连拍照片')),
                              ),
                              PopupMenuItem(
                                value: 'copy',
                                enabled: context.read<GalleryCubit>().state.resultComplete,
                                child: const ListTile(
                                  leading: Icon(Icons.copy_all_outlined),
                                  title: Text('复制当前拍摄'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'sort',
                                child: ListTile(leading: Icon(Icons.sort_rounded), title: Text('排序方式')),
                              ),
                            ],
                          ),
                      ],
              ),
            ),
          ),
          // Reserve the panel's actual height so the last photo can always
          // scroll fully into view, including with large text and safe insets.
          bottomNavigationBar: _SelectionActionPanel(batchId: batchId),
          body: BlocBuilder<GalleryCubit, GalleryState>(
            builder: (context, state) {
              if (state.loading && state.items.isEmpty && !state.filtering) {
                return const Center(child: CircularProgressIndicator(semanticsLabel: '正在读取照片列表'));
              }
              if (!rootMode && state.error != null && state.items.isEmpty) {
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
                                reviewContext: _reviewContext,
                              ),
                            ),
                            if (state.query.activeLabels.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: rootMode ? const EdgeInsets.fromLTRB(12, 0, 12, 4) : const EdgeInsets.fromLTRB(24, 0, 24, 8),
                                  child: ActiveFilterSummary(
                                    compact: rootMode,
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
                                child: _emptyContent(context, state),
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
                                    onFirstThumbnail: context.read<GalleryCubit>().visibleTiming?.firstThumbnail,
                                    onTap: () async {
                                      final selection = context.read<SelectionCubit>();
                                      if (selection.state.ids.isEmpty) {
                                        await guardBirdNavigation<void>(context, () async {
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
                                        });
                                      } else {
                                        selection.toggle(photo.id);
                                      }
                                    },
                                    onLongPress: () => context.read<SelectionCubit>().toggle(photo.id),
                                  ),
                                ),
                              ),
                            if (state.items.isNotEmpty && !state.filtering && (state.loading || state.hasMore || (state.resultComplete && state.error != null)))
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
                    if (state.filtering && (!rootMode || state.items.isNotEmpty))
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _FilterScanProgress(
                          compact: rootMode,
                          scannedCount: state.scannedCount,
                          matchedCount: state.matchedCount,
                          onCancel: context.read<GalleryCubit>().cancelFiltering,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _emptyContent(BuildContext context, GalleryState state) {
    final gallery = context.read<GalleryCubit>();
    void reset() => unawaited(gallery.refresh(query: const PhotoQuery()));
    final empty = _GalleryEmptyState(
      filtering: state.filtering,
      waitingForFirstPage: state.scannedCount == 0,
      incomplete: !state.resultComplete,
      fromCache: state.fromCache,
      onReset: reset,
      onRetry: rootMode && !state.resultComplete ? gallery.refresh : null,
    );
    if (!rootMode) return empty;
    if (state.filtering) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _FilterScanProgress(
            compact: true,
            scannedCount: state.scannedCount,
            matchedCount: state.matchedCount,
            onCancel: gallery.cancelFiltering,
          ),
        ),
      );
    }
    return BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
      bloc: BirdCompanionScope.of(context).deviceSessionCubit,
      builder: (context, session) {
        if (!session.isConnected) {
          return AlbumOfflineEmptyState(
            reconnecting: session.isVerifying,
            onReconnect: () => openReconnectConnection(context),
            onClearFilters: state.query.activeLabels.isNotEmpty ? reset : null,
          );
        }
        final error = state.error;
        if (error == null) return empty;
        return Center(
          child: ErrorNotice(
            title: '暂时无法加载照片',
            message: UserMessageMapper.fromError(error).message,
            onRetry: gallery.refresh,
          ),
        );
      },
    );
  }
}

class _SelectablePhotoTile extends StatelessWidget {
  const _SelectablePhotoTile({
    required this.photo,
    required this.onTap,
    required this.onLongPress,
    required this.compact,
    required this.showRatingOverlay,
    this.onFirstThumbnail,
  });

  final PhotoSummary photo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool compact;
  final bool showRatingOverlay;
  final VoidCallback? onFirstThumbnail;

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
        onFirstThumbnail: onFirstThumbnail,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _SelectionActionPanel extends StatefulWidget {
  const _SelectionActionPanel({required this.batchId});

  final String batchId;

  @override
  State<_SelectionActionPanel> createState() => _SelectionActionPanelState();
}

class _SelectionActionPanelState extends State<_SelectionActionPanel> {
  var _creatingSelection = false;

  @override
  Widget build(BuildContext context) => BlocBuilder<SelectionCubit, SelectionState>(
    builder: (context, selection) {
      if (selection.ids.isEmpty) return const SizedBox.shrink();
      final ids = selection.ids.toList(growable: false);
      return SelectionActionBar(
        count: ids.length,
        busy: selection.submitting || _creatingSelection,
        failedCount: selection.failed.length,
        onClear: () => context.read<SelectionCubit>().clear(),
        onAddTags: () => _showTagDialog(context, widget.batchId, ids, remove: false),
        onRemoveTags: () => _showTagDialog(context, widget.batchId, ids, remove: true),
        onAction: (action) => _requestBatchAction(context, widget.batchId, ids, action),
        onCopy: () => _copySelected(context, ids),
      );
    },
  );

  /// 创建不可变选择快照（§13.3）后进入复制配置页，范围固定「已选择 N 张」。
  Future<void> _copySelected(BuildContext context, List<String> ids) async {
    if (_creatingSelection) return;
    setState(() => _creatingSelection = true);
    try {
      final dependencies = BirdCompanionScope.of(context);
      // §13.3 client_revision：客户端对所选照片的视图修订号，取选中照片的
      // 最大 version，帮助后端识别过期选择；照片缺少版本信息时退回 0。
      final galleryState = context.read<GalleryCubit>().state;
      final selectedPhotos = galleryState.items.where((photo) => ids.contains(photo.id)).toList(growable: false);
      final clientRevision = selectedPhotos.fold(
        0,
        (max, photo) => photo.version != null && photo.version! > max ? photo.version! : max,
      );
      final selectedAssetIds = selectedPhotos.map((photo) => photo.assetId ?? photo.id).toSet().toList(growable: false);
      final snapshot = await dependencies.copyRepository.createSelection(
        widget.batchId,
        selectedAssetIds,
        clientRevision: clientRevision,
      );
      final discardedCount = galleryState.items
          .where(
            (photo) => ids.contains(photo.id) && KeepStateWireValue.fromWire(photo.keepState) == KeepState.discard,
          )
          .length;
      if (!mounted) return;
      await guardBirdNavigation(
        context,
        () => Navigator.of(context).pushNamed<void>(
          BirdRoutes.copyConfirmation,
          arguments: CopyConfirmationArgs(
            widget.batchId,
            scope: 'selected_assets',
            selectionId: snapshot.selectionId,
            selectionPhotoCount: snapshot.assetCount,
            selectionDiscardedCount: discardedCount,
            filter: galleryState.query.toCopyFilterV1(),
          ),
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
    required this.reviewContext,
  });
  final GalleryState state;
  final bool rootMode;
  final String batchId;
  final String? batchName;
  final DateTime? createdAt;
  final int? totalCount;
  final ReviewContext reviewContext;

  @override
  Widget build(BuildContext context) => BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
    bloc: BirdCompanionScope.of(context).deviceSessionCubit,
    builder: (context, session) {
      final offline = !session.isConnected;
      return Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, rootMode ? 4 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rootMode && !offline) _AlbumDeviceWarning(session: session),
            if (state.conflictOperationCount > 0 || state.pendingOperationCount > 0 && (!rootMode || !offline || state.items.isEmpty)) ...[
              _PendingSyncNotice(
                compact: rootMode,
                pendingCount: state.pendingOperationCount,
                conflictCount: state.conflictOperationCount,
                onOpenConflict: state.firstConflictFileId == null
                    ? null
                    : () => _openConflictPhoto(
                        context,
                        state.firstConflictFileId!,
                      ),
              ),
              SizedBox(height: rootMode ? 4 : 12),
            ],
            if (!rootMode && !state.filtering && !state.resultComplete && !state.fromCache && state.items.isNotEmpty)
              TextButton(
                onPressed: () => context.read<GalleryCubit>().refresh(),
                child: const Text('筛选未完成，点击重新筛选'),
              ),
            if (!rootMode && state.fromCache)
              GalleryCandidateNotice(
                loadedCount: state.items.length,
                totalCount: totalCount,
                resultComplete: state.resultComplete,
                offline: offline,
                onReconnect: () => openReconnectConnection(context),
                onRefresh: () => context.read<GalleryCubit>().refresh(query: state.query),
              ),
            _GalleryCountsNotice(state: state, offline: offline),
            if (rootMode) ...[
              _QuickFilters(
                query: state.query,
                pinFilterAction: true,
                pendingCount: state.pendingCount,
                keepCount: state.keepCount,
                discardCount: state.discardCount,
                recognizedCount: state.recognizedCount,
                filteredCount: state.filteredCount,
                offline: offline,
              ),
              _AlbumBatchHeading(
                batchId: batchId,
                batchName: batchName,
                createdAt: createdAt,
                offline: offline,
              ),
              if (state.items.isNotEmpty && (offline || !state.loading && !state.filtering && (!state.resultComplete || state.cacheScope == PhotoCacheScope.partial)))
                GalleryCandidateNotice(
                  album: true,
                  loadedCount: state.items.length,
                  resultComplete: state.resultComplete && state.cacheScope != PhotoCacheScope.partial && (!offline || !state.hasMore),
                  fromCache: state.fromCache || state.cacheScope != PhotoCacheScope.none,
                  offline: offline,
                  reconnecting: session.isVerifying,
                  pendingSyncCount: offline && state.conflictOperationCount == 0 ? state.pendingOperationCount : 0,
                  onReconnect: () => openReconnectConnection(context),
                  onRefresh: () => context.read<GalleryCubit>().refresh(query: state.query),
                ),
            ] else ...[
              _QuickFilters(query: state.query, pendingCount: state.pendingCount, keepCount: state.keepCount, discardCount: state.discardCount, recognizedCount: state.recognizedCount, filteredCount: state.filteredCount, offline: offline),
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
                    onPressed: () => guardBirdNavigation(
                      context,
                      () => showModalBottomSheet(
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
    guardBirdNavigation(
      context,
      () => Navigator.of(context).pushNamed(
        BirdRoutes.photoDetail,
        arguments: PhotoDetailArgs.fromReview(
          photoContext,
          fileId: fileId,
          totalCount: photoIds.length,
        ),
      ),
    );
  }
}

DeviceStatus? _currentAlbumDeviceStatus(DeviceSessionState session, DeviceStatusState state) {
  final status = state.status;
  final device = session.device;
  if (!session.isConnected || state.phase != DeviceStatusPhase.ready || status == null || device == null) return null;
  return status.connection.id == device.id && status.connection.baseUri == device.baseUri ? status : null;
}

class _AlbumStatusAction extends StatelessWidget {
  const _AlbumStatusAction({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sessionCubit = BirdCompanionScope.of(context).deviceSessionCubit;
    return BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
      bloc: sessionCubit,
      builder: (context, session) {
        if (!session.isConnected) {
          final label = switch (session.phase) {
            DeviceSessionPhase.connecting => '连接中',
            DeviceSessionPhase.reconnecting => '重连中',
            DeviceSessionPhase.incompatible => '版本不兼容',
            _ => '未连接',
          };
          return _button(
            context,
            label: label,
            description: '盒子$label',
            icon: session.isVerifying ? Icons.sync_rounded : Icons.wifi_off_rounded,
            warning: !session.isVerifying,
            onTap: session.isVerifying ? null : () => openReconnectConnection(context),
          );
        }

        return BlocBuilder<DeviceStatusCubit, DeviceStatusState>(
          builder: (context, state) {
            final status = _currentAlbumDeviceStatus(session, state);
            final reading = state.phase == DeviceStatusPhase.loading;
            final battery = status?.batteryPercent;
            return _button(
              context,
              label: reading
                  ? '读取中'
                  : battery == null
                  ? '电量未知'
                  : '$battery%',
              description: reading ? '盒子已连接，正在读取状态' : '盒子已连接，${battery == null ? '电量未知' : '电量 $battery%'}',
              icon: reading ? Icons.hourglass_top_rounded : Icons.wifi_rounded,
              showBattery: !reading,
              batteryPercent: battery,
              onTap: reading
                  ? null
                  : status == null
                  ? context.read<DeviceStatusCubit>().load
                  : () => _openStatus(context, status, session, sessionCubit),
            );
          },
        );
      },
    );
  }

  Widget _button(
    BuildContext context, {
    required String label,
    required String description,
    required IconData icon,
    required VoidCallback? onTap,
    bool showBattery = false,
    int? batteryPercent,
    bool warning = false,
  }) {
    final color = warning ? AppColors.danger : AppColors.brand;
    return Semantics(
      key: const ValueKey('album-device-status'),
      label: description,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: description,
        child: SizedBox(
          width: compact ? 56 : 92,
          height: AppSpacing.minimumTouchTarget,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: warning ? AppColors.dangerSoft : AppColors.brandLight,
                  border: Border.all(color: color.withValues(alpha: .25)),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 17, color: color),
                      if (!compact) ...[
                        const SizedBox(width: 3),
                        if (batteryPercent != null) Icon(Icons.battery_5_bar_rounded, size: 15, color: color),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ] else if (showBattery)
                        if (batteryPercent == null)
                          Icon(Icons.battery_unknown_rounded, size: 14, color: color)
                        else
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openStatus(BuildContext context, DeviceStatus status, DeviceSessionState session, DeviceSessionCubit sessionCubit) {
    final navigator = Navigator.of(context);
    final navigation = BirdShellNavigation.maybeOf(context);
    unawaited(
      showDeviceStatusSheet(
        context,
        status: status,
        session: session,
        sessionCubit: sessionCubit,
        onReconnect: () {
          navigator.pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) openReconnectConnection(context);
          });
        },
        onOpenDetails: () {
          navigator.pop();
          if (navigation != null) {
            navigation.openTabRoute(2, BirdRoutes.settingsDeviceDetails);
          } else {
            unawaited(navigator.pushNamed<void>(BirdRoutes.settingsDeviceDetails));
          }
        },
        onOpenTask: status.currentJob == null || navigation == null
            ? null
            : () {
                navigator.pop();
                navigation.selectTab(1);
              },
      ),
    );
  }
}

class _AlbumDeviceWarning extends StatelessWidget {
  const _AlbumDeviceWarning({required this.session});

  final DeviceSessionState session;

  @override
  Widget build(BuildContext context) {
    final status = _currentAlbumDeviceStatus(session, context.watch<DeviceStatusCubit>().state);
    if (status == null) return const SizedBox.shrink();
    final message = status.hasError
        ? status.errorMessage ?? '设备发生异常，请检查后重试'
        : (status.temperatureCelsius ?? 0) >= 70
        ? '设备温度偏高，请暂停处理并检查散热'
        : !status.card.inserted || !status.card.readable || status.card.errorCode != null
        ? status.card.errorMessage ?? '存储卡不可用，请检查后重试'
        : null;
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCompact),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        flex: 3,
        child: Text(
          _displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.brandDark,
            fontSize: 17,
          ),
        ),
      ),
      const SizedBox(width: 8),
      const Flexible(flex: 2, child: AlbumHistorySecondaryAction()),
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

class _PendingSyncNotice extends StatelessWidget {
  const _PendingSyncNotice({
    required this.pendingCount,
    required this.conflictCount,
    this.onOpenConflict,
    this.compact = false,
  });

  final int pendingCount;
  final int conflictCount;
  final VoidCallback? onOpenConflict;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hasConflict = conflictCount > 0;
    final text = compact
        ? hasConflict
              ? '$conflictCount 项照片修改冲突'
              : '$pendingCount 项照片修改待同步'
        : hasConflict
        ? '有 $conflictCount 条照片修改与盒子版本冲突，需在照片详情中处理。'
        : '有 $pendingCount 条照片修改保存在手机上，重连后只会同步到当前设备。';
    return Container(
      width: double.infinity,
      padding: compact ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: hasConflict ? AppColors.dangerSoft : AppColors.amberLight,
        border: Border.all(color: (hasConflict ? AppColors.danger : AppColors.pending).withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
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

class _GalleryCountsNotice extends StatelessWidget {
  const _GalleryCountsNotice({required this.state, required this.offline});
  final GalleryState state;
  final bool offline;
  @override
  Widget build(BuildContext context) {
    final time = state.countsUpdatedAt?.toLocal();
    final stamp = time == null ? '时间未记录' : '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.countsStatus == GalleryCountsStatus.loading) const Text('正在更新统计…', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        if (state.countsStatus == GalleryCountsStatus.unread) const Text('统计暂不可用', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        if ((offline || state.countsStatus == GalleryCountsStatus.stale) && state.pendingCount != null) Text('上次统计：$stamp${offline ? ' · 当前离线' : ' · 待更新'}', style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
      ],
    );
  }
}

class _QuickFilters extends StatelessWidget {
  const _QuickFilters({
    required this.query,
    this.pendingCount,
    this.keepCount,
    this.discardCount,
    this.recognizedCount,
    this.filteredCount,
    this.offline = false,
    this.pinFilterAction = false,
  });

  final PhotoQuery query;
  final int? pendingCount;
  final int? keepCount;
  final int? discardCount;
  final int? recognizedCount, filteredCount;
  final bool offline;
  final bool pinFilterAction;

  @override
  Widget build(BuildContext context) {
    final values = <(String, String?, int?, Color?, IconData?)>[
      ('全部', null, null, null, null),
      ('识别度高', 'recognized', recognizedCount, AppColors.brand, null),
      ('待确认', 'needs_review', pendingCount, AppColors.pending, Icons.circle),
      ('已跳过', 'filtered', filteredCount, null, null),
      ('已保留', 'keep', keepCount, AppColors.brand, Icons.circle),
      ('已弃选', 'discard', discardCount, AppColors.danger, Icons.circle),
      if (!offline) ('精选', 'featured', null, AppColors.amber, Icons.star_rounded),
    ];
    final selected = query.recommendedOnly ? '__ai__' : query.recognitionState ?? (query.analysisState == 'skipped' ? 'filtered' : query.keepState);
    final chips = SingleChildScrollView(
      key: pinFilterAction ? const ValueKey('album-quick-filters') : null,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...values.map((entry) {
            final active = selected == entry.$2;
            return Padding(
              padding: EdgeInsets.only(right: pinFilterAction ? 6 : 8),
              child: ChoiceChip(
                key: ValueKey('gallery-category-${entry.$2 ?? 'all'}'),
                selected: active,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                padding: pinFilterAction ? const EdgeInsets.symmetric(horizontal: 3, vertical: 2) : const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                labelPadding: pinFilterAction ? const EdgeInsets.symmetric(horizontal: 5) : null,
                avatarBoxConstraints: pinFilterAction ? BoxConstraints.tightFor(width: entry.$5 == Icons.star_rounded ? 18 : 13, height: 18) : null,
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
          if (!pinFilterAction)
            ActionChip(
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              avatar: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('筛选'),
              onPressed: () => _openFilters(context),
            ),
        ],
      ),
    );
    if (!pinFilterAction) return chips;

    final hasFilters = query.activeLabels.isNotEmpty;
    return Row(
      children: [
        Expanded(child: chips),
        SizedBox.square(
          dimension: 48,
          child: IconButton(
            key: const ValueKey('album-filter-button'),
            tooltip: '筛选照片',
            onPressed: () => _openFilters(context),
            padding: EdgeInsets.zero,
            icon: DecoratedBox(
              decoration: BoxDecoration(
                color: hasFilters ? AppColors.brandLight : AppColors.paperStrong,
                border: Border.all(color: hasFilters ? AppColors.outlineStrong : AppColors.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const SizedBox.square(
                dimension: 34,
                child: Icon(Icons.tune_rounded, color: AppColors.brand, size: 20),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openFilters(BuildContext context) {
    final cubit = context.read<GalleryCubit>();
    guardBirdNavigation(
      context,
      () => showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (_) => FilterSheet(
          initial: cubit.state.query,
          onApply: (query) => cubit.refresh(query: query),
        ),
      ),
    );
  }
}

Future<void> _showGallerySearch(BuildContext context) async {
  final cubit = context.read<GalleryCubit>();
  final value = await guardBirdNavigation(
    context,
    () => showDialog<String>(
      context: context,
      builder: (_) => GallerySearchDialog(initialValue: cubit.state.query.search ?? ''),
    ),
  );
  if (value == null || !context.mounted) return;
  await cubit.refresh(query: cubit.state.query.copyWith(search: value, clearCursor: true));
}

PhotoQuery _quickQuery(PhotoQuery source, String? value) => source.forQuickCategory(value);

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
    required this.waitingForFirstPage,
    required this.incomplete,
    required this.fromCache,
    this.onRetry,
  });
  final VoidCallback onReset;
  final bool filtering;
  final bool waitingForFirstPage;
  final bool incomplete;
  final bool fromCache;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(filtering ? Icons.manage_search_rounded : Icons.photo_library_outlined, size: 52),
        const SizedBox(height: 12),
        Text(
          filtering
              ? waitingForFirstPage
                    ? '正在读取照片列表…'
                    : '正在筛选照片…'
              : incomplete
              ? fromCache
                    ? '已缓存照片中没有符合条件的结果'
                    : '筛选未完成'
              : '没有符合条件的照片',
        ),
        const SizedBox(height: 8),
        if (!filtering)
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (onRetry != null) OutlinedButton(onPressed: onRetry, child: Text(fromCache ? '刷新' : '重新筛选')),
              OutlinedButton(onPressed: onReset, child: const Text('清除筛选')),
            ],
          ),
      ],
    ),
  );
}

class _FilterScanProgress extends StatelessWidget {
  const _FilterScanProgress({
    required this.scannedCount,
    required this.matchedCount,
    required this.onCancel,
    this.compact = false,
  });

  final int scannedCount;
  final int matchedCount;
  final VoidCallback onCancel;
  final bool compact;

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
                scannedCount == 0 ? '正在读取照片列表…' : '已扫描 $scannedCount 张 · 当前命中 $matchedCount 张',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('取消')),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          const LinearProgressIndicator(minHeight: 3),
        ],
      ],
    ),
  );
}

Future<void> _batchAction(BuildContext context, String batchId, List<String> ids, String action) async {
  final selection = context.read<SelectionCubit>();
  final gallery = context.read<GalleryCubit>();
  final dependencies = BirdCompanionScope.of(context);
  final deviceId = dependencies.deviceSessionCubit.state.device?.id.trim();
  if (selection.state.submitting) return;
  final previousById = {
    for (final photo in gallery.state.items.where((photo) => ids.contains(photo.id))) photo.id: KeepStateWireValue.fromWire(photo.keepState),
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
  final transitions = keepState == null
      ? const <ReviewStateTransition>[]
      : [
          for (final id in outcome.succeededIds)
            ReviewStateTransition(
              fileId: id,
              before: previousById[id] ?? KeepState.pending,
              after: keepState,
            ),
        ];
  if (!gallery.isClosed && transitions.isNotEmpty) {
    gallery.applyReviewTransitions(transitions);
  }
  _publishBatchReviewChange(
    dependencies.dataChangeBus,
    deviceId: deviceId,
    projectId: batchId,
    transitions: transitions,
    queued: outcome.queued,
  );
  if (!outcome.queued) {
    final grouped = <KeepState, List<String>>{};
    for (final id in outcome.succeededIds) {
      final previous = previousById[id] ?? KeepState.pending;
      grouped.putIfAbsent(previous, () => []).add(id);
    }
    selection.setUndoActions([
      for (final entry in grouped.entries)
        BatchUndoAction(
          operation: entry.key.wireValue,
          ids: entry.value,
          transitionFromOperation: keepState?.wireValue,
        ),
    ]);
  }
  if (!gallery.isClosed) await gallery.refresh();
  if (!context.mounted) return;
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
    final approved = await guardBirdNavigation(
      context,
      () => showDialog<bool>(
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
      ),
    );
    if (approved != true || !context.mounted) return;
  }
  await _batchAction(context, batchId, ids, action);
}

Future<void> _showTagDialog(BuildContext context, String batchId, List<String> ids, {required bool remove}) async {
  final dependencies = BirdCompanionScope.of(context);

  Future<List<PhotoSummary>> loadPhotos() async {
    final photos = <PhotoSummary>[];
    for (var start = 0; start < ids.length; start += 6) {
      final chunk = ids.skip(start).take(6);
      final details = await Future.wait(chunk.map(dependencies.reviewRepository.detail));
      for (final detail in details) {
        photos.add(
          PhotoSummary.fromJson({
            ...detail.photo.summary.toJson(),
            'user_tags': detail.userTags,
            'version': detail.decision?.version ?? detail.photo.summary.version,
          }),
        );
      }
    }
    return photos;
  }

  final change = await guardBirdNavigation(
    context,
    () => showDialog<BatchTagChange>(
      context: context,
      builder: (_) => remove ? BatchRemoveTagsDialog(loadPhotos: loadPhotos) : BatchAddTagsDialog(loadPhotos: loadPhotos),
    ),
  );
  if (change == null || change.groups.isEmpty || !context.mounted) return;
  final selection = context.read<SelectionCubit>();
  if (selection.state.submitting) return;
  selection.begin();

  final coordinator = PhotoVersionBatchCoordinator(dependencies.photoRepository, dependencies.reviewRepository);
  final operation = remove ? 'remove_tags' : 'add_tags';
  final succeeded = <String>[];
  final failed = <String, String>{};
  var queued = false;
  final undoActions = <BatchUndoAction>[];
  for (final group in change.groups) {
    final result = await coordinator.apply(
      projectId: batchId,
      fileIds: group.ids,
      currentPhotos: group.photos,
      operation: operation,
      value: group.tags,
      // An addition and its undo must use the tags and version from the same snapshot.
      loadMissingVersions: remove,
    );
    succeeded.addAll(result.succeededIds);
    failed.addAll(result.failed);
    queued = queued || result.queued;
    if (result.succeededIds.isNotEmpty) {
      undoActions.add(BatchUndoAction(operation: remove ? 'add_tags' : 'remove_tags', ids: result.succeededIds, value: group.tags));
    }
  }

  if (selection.isClosed) return;
  selection.complete(succeededIds: succeeded, failed: failed);
  if (!queued) {
    selection.setUndoActions(undoActions);
  }
  if (!context.mounted) return;
  await context.read<GalleryCubit>().refresh();
  if (!context.mounted) return;
  if (queued && failed.isNotEmpty) {
    BirdFeedback.error(context, '有标签修改等待同步，${failed.length} 张照片操作失败');
  } else if (queued) {
    BirdFeedback.queued(context, '标签已保存在手机上，重新连接后会自动更新');
  } else if (succeeded.isEmpty) {
    BirdFeedback.error(context, '${failed.length} 张照片标签操作失败');
  } else if (failed.isNotEmpty) {
    BirdFeedback.error(
      context,
      '已${remove ? '删除' : '添加'} ${succeeded.length} 张的标签，${failed.length} 张失败',
    );
  } else {
    BirdFeedback.undo(
      context,
      '已${remove ? '删除' : '添加'} ${succeeded.length} 张照片的标签',
      onUndo: () => _undoBatch(context, batchId),
    );
  }
}

Future<void> _undoBatch(BuildContext context, String batchId) async {
  if (!context.mounted) return;
  final selection = context.read<SelectionCubit>();
  final gallery = context.read<GalleryCubit>();
  final dependencies = BirdCompanionScope.of(context);
  final deviceId = dependencies.deviceSessionCubit.state.device?.id.trim();
  final actions = selection.takeUndoActions();
  if (actions.isEmpty) return;
  selection.begin(preserveUndo: true);
  final failed = <String, String>{};
  final succeeded = <String>[];
  final transitions = <ReviewStateTransition>[];
  var queued = false;
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
    queued = queued || outcome.queued;
    final after = _keepStateForOperation(action.operation);
    final before = _keepStateForOperation(action.transitionFromOperation ?? '');
    if (after != null) {
      transitions.addAll([
        for (final id in outcome.succeededIds)
          ReviewStateTransition(
            fileId: id,
            before: before ?? _visibleKeepState(gallery, id) ?? after,
            after: after,
          ),
      ]);
    }
  }
  if (!gallery.isClosed && transitions.isNotEmpty) {
    gallery.applyReviewTransitions(transitions);
  }
  _publishBatchReviewChange(
    dependencies.dataChangeBus,
    deviceId: deviceId,
    projectId: batchId,
    transitions: transitions,
    queued: queued,
  );
  selection.complete(succeededIds: succeeded, failed: failed);
  if (!gallery.isClosed) await gallery.refresh();
  if (!context.mounted) return;
  if (queued) {
    BirdFeedback.queued(context, '撤销已保存在手机上，重新连接后会自动更新');
  } else if (failed.isEmpty) {
    BirdFeedback.success(context, '已撤销最近一次批量操作');
  } else {
    BirdFeedback.error(
      context,
      '已撤销 ${succeeded.length} 张，${failed.length} 张撤销失败',
    );
  }
}

KeepState? _visibleKeepState(GalleryCubit gallery, String fileId) {
  for (final photo in gallery.state.items) {
    if (photo.id == fileId) return KeepStateWireValue.fromWire(photo.keepState);
  }
  return null;
}

void _publishBatchReviewChange(
  AppDataChangeBus dataChanges, {
  required String? deviceId,
  required String projectId,
  required List<ReviewStateTransition> transitions,
  required bool queued,
}) {
  final normalizedDeviceId = deviceId?.trim();
  if (normalizedDeviceId == null || normalizedDeviceId.isEmpty || transitions.isEmpty) {
    return;
  }
  dataChanges.publishChange(
    BatchReviewDecisionChanged(
      deviceId: normalizedDeviceId,
      projectId: projectId,
      transitions: List.unmodifiable(transitions),
      queued: queued,
    ),
  );
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
