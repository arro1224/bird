import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_cubit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GroupReviewPage extends StatelessWidget {
  const GroupReviewPage({
    super.key,
    required this.batchId,
    this.sceneId,
    this.sceneName,
    this.reviewContext,
  });

  final String batchId;
  final String? sceneId;
  final String? sceneName;
  final ReviewContext? reviewContext;

  ReviewContext get _reviewContext =>
      reviewContext ??
      ReviewContext(
        batchId: batchId,
        sceneId: sceneId,
        sceneName: sceneName,
      );

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => GroupReviewCubit(
      BirdCompanionScope.of(context).reviewRepository,
      BirdCompanionScope.of(context).refreshCoordinator,
      BirdCompanionScope.of(context).dataChangeBus,
    )..load(batchId, sceneId: sceneId),
    child: _GroupReviewView(
      sceneName: sceneName,
      reviewContext: _reviewContext,
    ),
  );
}

class _GroupReviewView extends StatefulWidget {
  const _GroupReviewView({this.sceneName, required this.reviewContext});

  final String? sceneName;
  final ReviewContext reviewContext;

  @override
  State<_GroupReviewView> createState() => _GroupReviewViewState();
}

class _GroupReviewViewState extends State<_GroupReviewView> {
  int _index = 0;
  int _selectedPhotoIndex = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: BirdSecondaryAppBar(
      title: '连拍照片挑选',
      subtitle: widget.sceneName ?? '从每组连拍照片中挑出满意的照片',
      helpTooltip: '连拍照片说明',
      onHelp: () => showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('为什么照片会分组？'),
          content: Text('短时间内连续拍摄的照片会放在一起。系统会根据鸟是否清楚、画面是否完整等因素，把更值得查看的照片排在前面。'),
        ),
      ),
    ),
    body: BlocConsumer<GroupReviewCubit, GroupReviewState>(
      listenWhen: (previous, current) => previous.message != current.message && current.message != null,
      listener: (context, state) => BirdFeedback.success(context, state.message!),
      builder: (context, state) {
        if (state.loading && state.groups.isEmpty) return const Center(child: CircularProgressIndicator());
        if (state.error != null && state.groups.isEmpty) return const Center(child: Text('暂时无法加载连拍照片，请稍后重试'));
        if (state.groups.isEmpty) return const Center(child: Text('这次拍摄没有需要挑选的连拍照片'));
        final index = _index.clamp(0, state.groups.length - 1);
        final group = state.groups[index];
        return NaturalBackdrop(
          dense: true,
          child: _GroupContent(
            group: group,
            index: index,
            total: state.groups.length,
            reviewContext: widget.reviewContext,
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
    required this.reviewContext,
    required this.selectedPhotoIndex,
    required this.onSelectPhoto,
    this.onPrevious,
    this.onNext,
  });

  final BirdGroup group;
  final int index;
  final int total;
  final ReviewContext reviewContext;
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
    final selectedKeepState = KeepStateWireValue.fromWire(representative?.keepState);
    final score = representative?.rating?.totalScore;
    final reasons = group.recommendationReasons.take(3).toList();
    final busy = context.select<GroupReviewCubit, bool>((cubit) => cubit.state.actingGroupId == group.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Text(
          '${_displayGroupName(group.id)} · ${group.memberFileIds.length} 张',
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
                BirdPressable(
                  borderRadius: BorderRadius.circular(18),
                  onTap: representative == null
                      ? null
                      : () {
                          final detailContext = reviewContext.enterGroup(
                            group.id,
                            name: _displayGroupName(group.id),
                            photos: photos.map((photo) => photo.id).toList(growable: false),
                            initialIndex: selectedIndex,
                          );
                          Navigator.of(context).pushNamed(
                            BirdRoutes.photoDetail,
                            arguments: PhotoDetailArgs.fromReview(
                              detailContext,
                              fileId: representative.id,
                            ),
                          );
                        },
                  child: _HeroPhoto(
                    photo: representative,
                    recommended: representative?.isRecommended == true || group.rankOrder.isNotEmpty,
                    score: score,
                    reasons: reasons,
                  ),
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
              child: _MarkButton(label: '弃用', icon: Icons.delete_outline, color: AppColors.danger, filled: selectedKeepState == KeepState.discard, onTap: busy ? null : () => _mark(context, representativeId, KeepState.discard)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '待确认', icon: Icons.help_outline, color: AppColors.amber, filled: selectedKeepState == KeepState.pending, onTap: busy ? null : () => _mark(context, representativeId, KeepState.pending)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '保留', icon: Icons.check_circle_outline, color: AppColors.brand, filled: selectedKeepState == KeepState.keep, onTap: busy ? null : () => _mark(context, representativeId, KeepState.keep)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '精选', icon: Icons.star_outline, color: AppColors.amber, filled: selectedKeepState == KeepState.featured, onTap: busy ? null : () => _mark(context, representativeId, KeepState.featured)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: rankedIds.length < 2
              ? null
              : () {
                  final comparisonContext = reviewContext.enterGroup(
                    group.id,
                    name: _displayGroupName(group.id),
                    photos: rankedIds.take(3).toList(growable: false),
                  );
                  Navigator.of(context).pushNamed(
                    BirdRoutes.comparisonReview,
                    arguments: ComparisonReviewArgs.fromReview(
                      comparisonContext,
                    ),
                  );
                },
          icon: const Icon(Icons.compare_rounded),
          label: const Text('对比最推荐的 2 张'),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(onPressed: onPrevious, icon: const Icon(Icons.chevron_left), label: const Text('上一组')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(onPressed: onNext, icon: const Icon(Icons.chevron_right), label: const Text('下一组'), iconAlignment: IconAlignment.end),
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
                placeholder: (_, _) => const _PhotoPlaceholder(),
                errorWidget: (_, _, _) => const _PhotoPlaceholder(),
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
                              Text(_friendlyReason(reason), style: const TextStyle(color: Colors.white, fontSize: 11)),
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
        '系统最推荐',
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
    return BirdPressable(
      borderRadius: BorderRadius.circular(10),
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
                  placeholder: (_, _) => const _PhotoPlaceholder(compact: true),
                  errorWidget: (_, _, _) => const _PhotoPlaceholder(compact: true),
                )
              else
                const ColoredBox(color: AppColors.mist, child: Icon(Icons.photo_outlined)),
              Positioned(
                left: 4,
                top: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brand : AppColors.inkMuted.withValues(alpha: .88),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(
                      rank <= 3 ? '推荐 $rank' : '第 $rank 张',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              if (photo.clarityState == ClarityState.blurred)
                const Positioned(
                  right: 4,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xAA14341E),
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text('模糊', style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
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

String _displayGroupName(String value) {
  final match = RegExp(r'(\d+)$').firstMatch(value);
  if (match == null) return value;
  return '第 ${int.parse(match.group(1)!)} 组连拍照片';
}

String _friendlyReason(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('鸟眼') || normalized.contains('eye')) return '鸟的眼睛清楚';
  if (normalized.contains('主体') || normalized.contains('subject')) return '鸟的身体完整';
  if (normalized.contains('构图') || normalized.contains('composition')) return '画面看起来舒服';
  if (normalized.contains('清晰') || normalized.contains('sharp')) return '照片清楚';
  if (normalized.contains('曝光') || normalized.contains('exposure')) return '亮度合适';
  return value;
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.brandLight,
    child: Center(
      child: SizedBox.square(
        dimension: compact ? 20 : 28,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
