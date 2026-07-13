import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_cubit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GroupReviewPage extends StatelessWidget {
  const GroupReviewPage({super.key, required this.batchId});
  final String batchId;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => GroupReviewCubit(BirdCompanionScope.of(context).reviewRepository, BirdCompanionScope.of(context).refreshCoordinator, BirdCompanionScope.of(context).dataChangeBus)..load(batchId),
    child: Scaffold(
      appBar: AppBar(leading: const BirdPageBackButton()),
      body: BlocBuilder<GroupReviewCubit, GroupReviewState>(
        builder: (context, state) {
          if (state.loading && state.groups.isEmpty) return const Center(child: CircularProgressIndicator());
          if (state.error != null && state.groups.isEmpty) return Center(child: Text('无法加载分组：${state.error}'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            children: [
              Text('分组审阅', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Burst / Scene · 先挑出最值得保留的照片', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              ...state.groups.map((group) => _GroupPanel(group: group)),
              const SizedBox(height: 20),
              FilledButton(onPressed: state.groups.isEmpty ? null : () => context.read<GroupReviewCubit>().keepTopRecommendations(), child: const Text('批量保留 Top 1 推荐图')),
            ],
          );
        },
      ),
    ),
  );
}

class _GroupPanel extends StatelessWidget {
  const _GroupPanel({required this.group});
  final BirdGroup group;
  @override
  Widget build(BuildContext context) {
    final busy = context.select((GroupReviewCubit cubit) => cubit.state.actingGroupId == group.id);
    final ids = (group.rankOrder.isEmpty ? group.memberFileIds : group.rankOrder).take(4).toList();
    final matches = group.members.where((photo) => photo.id == group.representativeFileId).toList();
    final representative = matches.isNotEmpty ? matches.first : (group.members.isEmpty ? null : group.members.first);
    final name = representative?.recognition?.candidates.isNotEmpty == true ? representative!.recognition!.candidates.first.name : '推荐照片';
    final title = group.type == 'burst' ? '连拍' : '场景';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: ids.length < 2
              ? null
              : () => Navigator.of(context).pushNamed(
                  BirdRoutes.comparisonReview,
                  arguments: ComparisonReviewArgs(groupId: group.id, fileIds: ids),
                ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _Preview(photo: representative),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BirdPill(label: 'Top 1'),
                      const SizedBox(height: 13),
                      Text('$title ${group.capturedFrom == null ? '' : '${group.capturedFrom!.hour.toString().padLeft(2, '0')}:${group.capturedFrom!.minute.toString().padLeft(2, '0')}'}', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(name, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Text(
                        '${group.memberFileIds.length} 张 · 推荐：${representative?.rating?.totalScore.toStringAsFixed(0) ?? '-'} 分',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text(
                        '审阅›',
                        style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w900),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({this.photo});
  final dynamic photo;
  @override
  Widget build(BuildContext context) {
    final url = photo?.preview.thumbnailUri?.toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 96,
        height: 124,
        child: url?.isNotEmpty == true
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.brandLight),
              )
            : const ColoredBox(
                color: AppColors.brandLight,
                child: Icon(Icons.diamond_outlined, color: AppColors.brand, size: 44),
              ),
      ),
    );
  }
}
