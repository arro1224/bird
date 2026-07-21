import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
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
    appBar: BirdSecondaryAppBar(
      title: _scenePageTitle(args.batchName ?? args.batchId),
      onHelp: () => _showHelp(context),
      helpTooltip: '场景说明',
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
              title: '这次拍摄还没有按场景整理',
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
                  '拍摄场景 ${state.items.length} 个 · 连拍照片 ${_formatCount(groupCount)} 组 · 共 ${_formatCount(photoCount)} 张',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: 54),
                BirdReviewBreadcrumb(
                  current: BirdReviewLevel.scene,
                  onBatch: () => Navigator.of(context).maybePop(),
                  padding: EdgeInsets.zero,
                ),
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
    final reviewContext = scene == null ? args.context : args.context.enterScene(scene.id, name: scene.name);
    Navigator.of(context).pushNamed(
      BirdRoutes.gallery,
      arguments: GalleryArgs(
        args.batchId,
        batchName: scene == null ? args.batchName : '${args.batchName ?? args.batchId} · ${scene.name}',
        totalCount: scene?.photoCount ?? args.totalCount,
        initialQuery: PhotoQuery(sceneId: scene?.id),
        reviewContext: reviewContext,
      ),
    );
  }

  void _openGroups(BuildContext context, SceneSummary scene) {
    final reviewContext = args.context.enterScene(scene.id, name: scene.name);
    Navigator.of(context).pushNamed(
      BirdRoutes.groupReview,
      arguments: GroupReviewArgs(
        args.batchId,
        sceneId: scene.id,
        sceneName: scene.name,
        reviewContext: reviewContext,
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('什么是拍摄场景？'),
        content: Text('拍鸟伴侣会根据拍摄时间和画面变化把照片整理到不同场景中。进入场景后，还可以继续挑选每组连拍照片。'),
      ),
    );
  }
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imageWidth = constraints.maxWidth < 330 ? 126.0 : 148.0;
          return SizedBox(
            height: 112,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                  child: SizedBox(
                    width: imageWidth,
                    height: 112,
                    child: imageUrl?.isNotEmpty == true
                        ? CachedNetworkImage(
                            imageUrl: imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const _ScenePlaceholder(),
                            errorWidget: (_, _, _) => const _ScenePlaceholder(),
                          )
                        : const _ScenePlaceholder(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scene.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.brandDark),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _timeRange(scene),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${_formatCount(scene.photoCount)} 张 · ${scene.burstGroupCount} 组',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
              ],
            ),
          );
        },
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

String _scenePageTitle(String value) {
  final match = RegExp(r'^(\d{4})\.(\d{1,2})\.(\d{1,2})\s+(.+)$').firstMatch(value.trim());
  if (match == null) return value;
  return '${match.group(4)} · ${int.parse(match.group(2)!)}月${int.parse(match.group(3)!)}日';
}

String _formatCount(int value) {
  final digits = value.toString();
  return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

class _ScenePlaceholder extends StatelessWidget {
  const _ScenePlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.brandLight,
    child: Icon(Icons.landscape_outlined, size: 42, color: AppColors.brand),
  );
}
