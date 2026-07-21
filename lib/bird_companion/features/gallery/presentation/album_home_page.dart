import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/album_add_device_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Root of the three-tab information architecture. The current batch opens
/// directly as an album; batch/history browsing remains available as a
/// secondary route instead of occupying the primary photo tab.
class AlbumHomePage extends StatelessWidget {
  const AlbumHomePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => BatchListCubit(
      BirdCompanionScope.of(context).batchRepository,
      BirdCompanionScope.of(context).refreshCoordinator,
      BirdCompanionScope.of(context).dataChangeBus,
    )..load(),
    child: const _AlbumHomeView(),
  );
}

class _AlbumHomeView extends StatelessWidget {
  const _AlbumHomeView();

  @override
  Widget build(BuildContext context) => BlocBuilder<BatchListCubit, BatchListState>(
    builder: (context, state) {
      final batch = state.current;
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
                actionLabel: '查看本次与过去的拍摄',
                onAction: () => Navigator.of(context).pushNamed(BirdRoutes.batches),
              ),
      );
    },
  );
}
