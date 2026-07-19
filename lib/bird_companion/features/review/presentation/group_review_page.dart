import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_cubit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GroupReviewPage extends StatelessWidget {
  const GroupReviewPage({super.key, required this.batchId, this.sceneId, this.sceneName});

  final String batchId;
  final String? sceneId;
  final String? sceneName;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => GroupReviewCubit(
      BirdCompanionScope.of(context).reviewRepository,
      BirdCompanionScope.of(context).refreshCoordinator,
      BirdCompanionScope.of(context).dataChangeBus,
    )..load(batchId, sceneId: sceneId),
    child: _GroupReviewView(sceneName: sceneName),
  );
}

class _GroupReviewView extends StatefulWidget {
  const _GroupReviewView({this.sceneName});

  final String? sceneName;

  @override
  State<_GroupReviewView> createState() => _GroupReviewViewState();
}

class _GroupReviewViewState extends State<_GroupReviewView> {
  int _index = 0;
  int _selectedPhotoIndex = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: AppBar(
      leading: const BirdPageBackButton(),
      centerTitle: true,
      title: BlocBuilder<GroupReviewCubit, GroupReviewState>(
        builder: (_, state) => Column(
          children: [
            const Text('连拍组审阅'),
            Text(
              widget.sceneName ?? '${state.groups.length} 组待复核',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: '连拍组说明',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(title: Text('什么是连拍组？'), content: Text('盒子会把短时间连续拍摄的照片归为一组，并根据鸟眼、主体和构图给出推荐顺序。')),
          ),
          icon: const Icon(Icons.help_outline_rounded),
        ),
      ],
    ),
    body: BlocConsumer<GroupReviewCubit, GroupReviewState>(
      listenWhen: (previous, current) => previous.message != current.message && current.message != null,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!))),
      builder: (context, state) {
        if (state.loading && state.groups.isEmpty) return const Center(child: CircularProgressIndicator());
        if (state.error != null && state.groups.isEmpty) return Center(child: Text('无法加载分组：${state.error}'));
        if (state.groups.isEmpty) return const Center(child: Text('当前批次没有需要审阅的连拍分组'));
        final index = _index.clamp(0, state.groups.length - 1);
        final group = state.groups[index];
        return NaturalBackdrop(
          dense: true,
          child: _GroupContent(
            group: group,
            index: index,
            total: state.groups.length,
            selectedPhotoIndex: _selectedPhotoIndex,
            onSelectPhoto: (value) => setState(() => _selectedPhotoIndex = value),
            onPrevious: index == 0
                ? null
                : () => setState(() {
                    _index = index - 1;
                    _selectedPhotoIndex = 0;
                  }),
            onNext: index == state.groups.length - 1
                ? null
                : () => setState(() {
                    _index = index + 1;
                    _selectedPhotoIndex = 0;
                  }),
          ),
        );
      },
    ),
  );
}

class _GroupContent extends StatelessWidget {
  const _GroupContent({
    required this.group,
    required this.index,
    required this.total,
    required this.selectedPhotoIndex,
    required this.onSelectPhoto,
    this.onPrevious,
    this.onNext,
  });

  final BirdGroup group;
  final int index;
  final int total;
  final int selectedPhotoIndex;
  final ValueChanged<int> onSelectPhoto;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final rankedIds = group.rankOrder.isEmpty ? group.memberFileIds : group.rankOrder;
    final ranked = <PhotoSummary>[
      for (final id in rankedIds) ...group.members.where((photo) => photo.id == id),
    ];
    final photos = ranked.isEmpty ? group.members : ranked;
    final selectedIndex = photos.isEmpty ? 0 : selectedPhotoIndex.clamp(0, photos.length - 1);
    final representative = photos.isEmpty ? null : photos[selectedIndex];
    final representativeId = representative?.id ?? group.representativeFileId;
    final score = representative?.rating?.totalScore;
    final reasons = group.recommendationReasons.take(3).toList();
    final busy = context.select<GroupReviewCubit, bool>((cubit) => cubit.state.actingGroupId == group.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text(
          '${group.id} · ${group.memberFileIds.length} 张',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.brandDark),
        ),
        const SizedBox(height: 4),
        Text(
          _timeRange(group),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _HeroPhoto(
                  photo: representative,
                  recommended: representative?.isRecommended == true || group.rankOrder.isNotEmpty,
                  score: score,
                  reasons: reasons,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, photoIndex) => _Thumbnail(
              photo: photos[photoIndex],
              rank: photoIndex + 1,
              selected: photoIndex == selectedIndex,
              onTap: () => onSelectPhoto(photoIndex),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MarkButton(label: '弃用', icon: Icons.delete_outline, color: AppColors.danger, onTap: busy ? null : () => _mark(context, representativeId, KeepState.discard)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '待确认', icon: Icons.help_outline, color: AppColors.amber, onTap: busy ? null : () => _mark(context, representativeId, KeepState.pending)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '保留', icon: Icons.check_circle_outline, color: AppColors.brand, filled: true, onTap: busy ? null : () => _mark(context, representativeId, KeepState.keep)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '精选', icon: Icons.star_outline, color: AppColors.amber, onTap: busy ? null : () => _mark(context, representativeId, KeepState.featured)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: rankedIds.length < 2
              ? null
              : () => Navigator.of(context).pushNamed(
                  BirdRoutes.comparisonReview,
                  arguments: ComparisonReviewArgs(groupId: group.id, fileIds: rankedIds.take(2).toList()),
                ),
          icon: const Icon(Icons.compare_rounded),
          label: const Text('对比 Top 2'),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(onPressed: onPrevious, icon: const Icon(Icons.chevron_left), label: Text(index == 0 ? '已经是第一组' : '上一组')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(onPressed: onNext, icon: const Icon(Icons.chevron_right), label: Text(index + 1 == total ? '已经是最后一组' : '下一组'), iconAlignment: IconAlignment.end),
            ),
          ],
        ),
      ],
    );
  }

  void _mark(BuildContext context, String id, KeepState state) => context.read<GroupReviewCubit>().markFile(group, id, state);
}

class _HeroPhoto extends StatelessWidget {
  const _HeroPhoto({this.photo, this.recommended = false, this.score, this.reasons = const []});

  final PhotoSummary? photo;
  final bool recommended;
  final double? score;
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final url = photo?.preview.previewUri?.toString();
    return AspectRatio(
      aspectRatio: 1.25,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url?.isNotEmpty == true)
              CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const ColoredBox(color: AppColors.brandLight),
              )
            else
              const ColoredBox(
                color: AppColors.brandLight,
                child: Icon(Icons.photo_outlined, size: 64, color: AppColors.brand),
              ),
            if (recommended) const Positioned(left: 12, top: 12, child: _AiBadge()),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.transparent, Color(0xC614341E)]),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: AppColors.brandLight),
                  const SizedBox(width: 8),
                  Text(
                    score?.toStringAsFixed(1) ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
                  ),
                  const Text(' / 5', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        for (final reason in reasons.take(3))
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, size: 15, color: AppColors.brandLight),
                              const SizedBox(width: 3),
                              Text(reason, style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: .9), borderRadius: BorderRadius.circular(8)),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        'AI 推荐 Top 1',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photo, required this.rank, required this.selected, required this.onTap});

  final PhotoSummary photo;
  final int rank;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = photo.preview.thumbnailUri?.toString();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? AppColors.brand : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url?.isNotEmpty == true)
                CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const ColoredBox(color: AppColors.mist),
                )
              else
                const ColoredBox(color: AppColors.mist, child: Icon(Icons.photo_outlined)),
              Positioned(
                left: 4,
                top: 4,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: selected ? AppColors.brand : AppColors.inkMuted,
                  child: Text('$rank', style: const TextStyle(fontSize: 10, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({required this.label, required this.icon, required this.color, required this.onTap, this.filled = false});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      foregroundColor: filled ? Colors.white : color,
      backgroundColor: filled ? color : Colors.transparent,
      side: BorderSide(color: filled ? color : AppColors.outline),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

String _timeRange(BirdGroup group) {
  String time(DateTime? value) {
    if (value == null) return '--:--:--';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  return '${time(group.capturedFrom)} - ${time(group.capturedTo)}';
}
