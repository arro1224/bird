import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/album_materialization_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_add_device_button.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_history_entry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Root of the three-tab information architecture. The current batch opens
/// directly as an album; batch/history browsing remains available as a
/// secondary route instead of occupying the primary photo tab.
class AlbumHomePage extends StatelessWidget {
  const AlbumHomePage({super.key, this.focusRequest});

  final ValueListenable<AlbumFocusRequest?>? focusRequest;

  @override
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    final session = dependencies.deviceSessionCubit;
    String? activeDeviceId() => session.state.isConnected ? session.state.device?.id.trim() : null;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => BatchListCubit(
            dependencies.batchRepository,
            dependencies.refreshCoordinator,
            dependencies.dataChangeBus,
          )..load(),
        ),
        BlocProvider(
          create: (_) {
            final cubit = AlbumMaterializationCubit(
              dependencies.batchRepository,
              dependencies.photoRepository,
              dependencies.dataChangeBus,
              activeDeviceId: activeDeviceId,
              deviceChanges: session.stream
                  .map(
                    (state) => state.isConnected ? state.device?.id.trim() : null,
                  )
                  .distinct(),
            );
            final initialFocus = focusRequest?.value;
            if (initialFocus != null) {
              cubit.materialize(initialFocus.projectId);
            }
            return cubit;
          },
        ),
      ],
      child: _AlbumFocusListener(
        focusRequest: focusRequest,
        child: const _AlbumHomeListeners(child: _AlbumHomeView()),
      ),
    );
  }
}

class AlbumFocusRequest {
  const AlbumFocusRequest({required this.projectId, required this.generation});

  final String projectId;
  final int generation;
}

class _AlbumFocusListener extends StatefulWidget {
  const _AlbumFocusListener({required this.focusRequest, required this.child});

  final ValueListenable<AlbumFocusRequest?>? focusRequest;
  final Widget child;

  @override
  State<_AlbumFocusListener> createState() => _AlbumFocusListenerState();
}

class _AlbumFocusListenerState extends State<_AlbumFocusListener> {
  int? _handledGeneration;

  @override
  void initState() {
    super.initState();
    widget.focusRequest?.addListener(_handleFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleFocus());
  }

  @override
  void didUpdateWidget(_AlbumFocusListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRequest == widget.focusRequest) return;
    oldWidget.focusRequest?.removeListener(_handleFocus);
    widget.focusRequest?.addListener(_handleFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleFocus());
  }

  void _handleFocus() {
    if (!mounted) return;
    final request = widget.focusRequest?.value;
    if (request == null || request.generation == _handledGeneration) return;
    _handledGeneration = request.generation;
    final cubit = context.read<AlbumMaterializationCubit>();
    if (cubit.state.projectId != request.projectId || cubit.state.phase == AlbumMaterializationPhase.idle) {
      cubit.materialize(request.projectId);
    }
  }

  @override
  void dispose() {
    widget.focusRequest?.removeListener(_handleFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AlbumHomeListeners extends StatelessWidget {
  const _AlbumHomeListeners({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<AlbumMaterializationCubit, AlbumMaterializationState>(
        listenWhen: (previous, current) => !previous.ready && current.ready,
        listener: (context, _) => unawaited(context.read<BatchListCubit>().load()),
      ),
      BlocListener<BatchListCubit, BatchListState>(
        listener: (context, batchState) {
          final materialization = context.read<AlbumMaterializationCubit>().state;
          if (materialization.ready && batchState.current?.id == materialization.projectId) {
            context.read<AlbumMaterializationCubit>().settle();
          }
        },
      ),
    ],
    child: child,
  );
}

class _AlbumHomeView extends StatelessWidget {
  const _AlbumHomeView();

  @override
  Widget build(BuildContext context) => BlocBuilder<AlbumMaterializationCubit, AlbumMaterializationState>(
    builder: (context, materialization) => BlocBuilder<BatchListCubit, BatchListState>(
      builder: (context, state) {
        if (materialization.preparing) {
          return const _AlbumPreparingView();
        }
        if (materialization.timedOut) {
          return Scaffold(
            key: const Key('album-materialization-timeout'),
            backgroundColor: AppColors.paper,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('相册'),
              actions: const [
                AlbumHistoryAppBarAction(),
                SizedBox(width: 12),
              ],
            ),
            body: ErrorNotice(
              title: '照片列表尚未准备好',
              message: '识别任务已经完成，但盒子暂时还不能读取这次拍摄的照片列表。',
              onRetry: context.read<AlbumMaterializationCubit>().retry,
            ),
          );
        }
        final focusedBatch = materialization.ready ? materialization.batch : null;
        final batch = state.current?.id == materialization.projectId ? state.current : focusedBatch ?? state.current;
        if (batch != null) {
          return GalleryPage(
            key: ValueKey('album-${batch.id}'),
            batchId: batch.id,
            batchName: batch.name,
            createdAt: batch.createdAt,
            totalCount: batch.totalFiles,
            pendingCount: batch.pendingReviewCount,
            keepCount: batch.keepCount,
            discardCount: batch.discardCount,
            rootMode: true,
          );
        }
        if (state.loading) {
          return const Scaffold(
            backgroundColor: AppColors.paper,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.paper,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('相册'),
            actions: [
              const AlbumHistoryAppBarAction(),
              AlbumAddDeviceButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).pushNamed(
                  BirdRoutes.connection,
                  arguments: const ConnectionArgs(entryMode: ConnectionEntryMode.addOrSwitch),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: state.error != null
              ? ErrorNotice(
                  title: '暂时无法读取相册',
                  message: '请检查设备连接，或稍后重新加载本次拍摄。',
                  onRetry: context.read<BatchListCubit>().load,
                )
              : EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: '还没有可浏览的照片',
                  message: '插入存储卡并开始导入后，照片会直接显示在相册首页。',
                  actionLabel: '查看全部拍摄记录',
                  onAction: () => openAlbumHistory(context),
                ),
        );
      },
    ),
  );
}

class _AlbumPreparingView extends StatelessWidget {
  const _AlbumPreparingView();

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('album-materialization-preparing'),
    backgroundColor: AppColors.paper,
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text('相册'),
      actions: const [
        AlbumHistoryAppBarAction(),
        SizedBox(width: 12),
      ],
    ),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text(
              '识别已完成，正在准备照片列表',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              '照片条目可读取后会立即显示，不需要等待全部缩略图生成。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    ),
  );
}
