import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/presentation/scene_list_cubit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SceneListPage extends StatelessWidget {
  const SceneListPage({super.key, required this.args});

  final SceneListArgs args;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SceneListCubit(BirdCompanionScope.of(context).photoRepository, args.batchId)..load(),
    child: _SceneListView(args: args),
  );
}

class _SceneListView extends StatelessWidget {
  const _SceneListView({required this.args});

  final SceneListArgs args;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: AppBar(
      leading: const BirdPageBackButton(),
      title: Text(args.batchName ?? args.batchId, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [IconButton(onPressed: () => _showHelp(context), icon: const Icon(Icons.help_outline_rounded), tooltip: '场景说明')],
    ),
    body: NaturalBackdrop(
      dense: true,
      child: BlocBuilder<SceneListCubit, SceneListState>(
        builder: (context, state) {
          if (state.loading && state.items.isEmpty) return const Center(child: CircularProgressIndicator());
          if (state.error != null && state.items.isEmpty) {
            return ErrorNotice(title: '无法读取拍摄场景', message: '请检查设备连接后重试。', onRetry: context.read<SceneListCubit>().load);
          }
          if (state.items.isEmpty) {
            return EmptyState(
              icon: Icons.account_tree_outlined,
              title: '当前批次还没有场景分组',
              message: '可以先浏览全部照片，盒子完成分组后再回来查看。',
              actionLabel: '浏览全部照片',
              onAction: () => _openGallery(context),
            );
          }
          final photoCount = args.totalCount ?? state.items.fold<int>(0, (sum, item) => sum + item.photoCount);
          final groupCount = args.burstGroupCount ?? state.items.fold<int>(0, (sum, item) => sum + item.burstGroupCount);
          return RefreshIndicator(
            onRefresh: context.read<SceneListCubit>().load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.pageHorizontal, AppSpacing.sm, AppSpacing.pageHorizontal, AppSpacing.xxl),
              children: [
                Text(
                  '场景 ${state.items.length} 个 · 连拍组 $groupCount 组 · 照片 $photoCount 张',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.xl),
                const _Breadcrumb(),
                const SizedBox(height: AppSpacing.lg),
                for (final scene in state.items) ...[
                  _SceneCard(scene: scene, onTap: () => _openGroups(context, scene)),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );

  void _openGallery(BuildContext context, {SceneSummary? scene}) {
    Navigator.of(context).pushNamed(
      BirdRoutes.gallery,
      arguments: GalleryArgs(
        args.batchId,
        batchName: scene == null ? args.batchName : '${args.batchName ?? args.batchId} · ${scene.name}',
        totalCount: scene?.photoCount ?? args.totalCount,
        initialQuery: PhotoQuery(sceneId: scene?.id),
      ),
    );
  }

  void _openGroups(BuildContext context, SceneSummary scene) {
    Navigator.of(context).pushNamed(
      BirdRoutes.groupReview,
      arguments: GroupReviewArgs(args.batchId, sceneId: scene.id, sceneName: scene.name),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('什么是拍摄场景？'),
        content: Text('拍鸟伴侣会按拍摄时间与画面变化整理场景。进入场景后仍可继续按连拍组审阅。'),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb();

  @override
  Widget build(BuildContext context) => const Center(
    child: BirdPill(
      label: '批次  >  场景  >  连拍组  >  单张照片',
      color: AppColors.paperStrong,
      textColor: AppColors.inkMuted,
    ),
  );
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.scene, required this.onTap});

  final SceneSummary scene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = scene.cover?.thumbnailUri?.toString();
    return BirdCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            child: SizedBox(
              width: 148,
              height: 112,
              child: imageUrl?.isNotEmpty == true ? CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover, errorWidget: (_, _, _) => const _ScenePlaceholder()) : const _ScenePlaceholder(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scene.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.brandDark),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(_timeRange(scene), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted)),
                const SizedBox(height: AppSpacing.sm),
                Text('${scene.photoCount} 张 · ${scene.burstGroupCount} 组', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
        ],
      ),
    );
  }

  String _timeRange(SceneSummary scene) => '${_time(scene.capturedFrom)}–${_time(scene.capturedTo)}';

  String _time(DateTime? value) {
    if (value == null) return '--:--';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ScenePlaceholder extends StatelessWidget {
  const _ScenePlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.brandLight,
    child: Icon(Icons.landscape_outlined, size: 42, color: AppColors.brand),
  );
}
