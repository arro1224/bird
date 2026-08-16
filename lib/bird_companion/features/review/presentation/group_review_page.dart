import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/progressive_photo_image.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_cubit.dart';
import 'package:aves/bird_companion/features/review/presentation/review_media_context.dart';
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:aves/bird_companion/features/review/domain/review_checkpoint.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/group_review_comparison_action.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/group_review_scope_selector.dart';
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
  Widget build(BuildContext context) {
    final dependencies = BirdCompanionScope.of(context);
    final media = resolveReviewMediaContext(dependencies);
    return BlocProvider(
      create: (_) => GroupReviewCubit(
        dependencies.reviewRepository,
        dependencies.refreshCoordinator,
        dependencies.dataChangeBus,
      )..load(batchId, sceneId: sceneId),
      child: _GroupReviewView(
        sceneName: sceneName,
        reviewContext: _reviewContext,
        checkpointStore: dependencies.reviewCheckpointStore,
        deviceId: media.deviceNamespace,
        thumbnailSize: dependencies.settingsStore.read().thumbnailSize,
        media: media,
      ),
    );
  }
}

class _GroupReviewView extends StatefulWidget {
  const _GroupReviewView({
    this.sceneName,
    required this.reviewContext,
    required this.checkpointStore,
    required this.thumbnailSize,
    required this.media,
    this.deviceId,
  });

  final String? sceneName;
  final ReviewContext reviewContext;
  final ReviewCheckpointStore checkpointStore;
  final String? deviceId;
  final String thumbnailSize;
  final ReviewMediaContext media;

  @override
  State<_GroupReviewView> createState() => _GroupReviewViewState();
}

class _GroupReviewViewState extends State<_GroupReviewView> {
  int _index = 0;
  int _selectedPhotoIndex = 0;
  var _restoredInitialPosition = false;
  var _applyToWholeGroup = false;

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
      listenWhen: (previous, current) => (previous.message != current.message && current.message != null) || (previous.error != current.error && current.error != null),
      listener: (context, state) {
        if (state.error != null) {
          final message = UserMessageMapper.fromError(state.error!);
          BirdFeedback.error(context, message.message);
        } else if (state.message != null) {
          BirdFeedback.success(context, state.message!);
        }
      },
      builder: (context, state) {
        if (state.loading && state.groups.isEmpty) return const Center(child: CircularProgressIndicator());
        if (state.error != null && state.groups.isEmpty) {
          final message = UserMessageMapper.fromError(state.error!);
          return ErrorNotice(
            title: '暂时无法加载连拍照片',
            message: message.message,
            onRetry: () => context.read<GroupReviewCubit>().load(
              widget.reviewContext.batchId,
              sceneId: widget.reviewContext.sceneId,
            ),
          );
        }
        if (state.groups.isEmpty) return const Center(child: Text('这次拍摄没有需要挑选的连拍照片'));
        _restoreInitialPosition(state.groups);
        final index = _index.clamp(0, state.groups.length - 1);
        final group = state.groups[index];
        return NaturalBackdrop(
          dense: true,
          child: _GroupContent(
            group: group,
            index: index,
            total: state.groups.length,
            reviewContext: widget.reviewContext,
            media: widget.media,
            selectedPhotoIndex: _selectedPhotoIndex,
            thumbnailSize: widget.thumbnailSize,
            comparisonGroups: state.groups
                .map(
                  (candidate) => _contextForGroup(
                    widget.reviewContext,
                    candidate,
                  ),
                )
                .toList(growable: false),
            comparisonGroupIndex: index,
            applyToWholeGroup: _applyToWholeGroup,
            onScopeChanged: (value) {
              setState(() => _applyToWholeGroup = value);
            },
            onSelectPhoto: (value) {
              setState(() => _selectedPhotoIndex = value);
              _saveCheckpoint(group, value);
            },
            onPrevious: index == 0
                ? null
                : () {
                    setState(() {
                      _index = index - 1;
                      _selectedPhotoIndex = 0;
                    });
                    _saveCheckpoint(state.groups[_index], 0);
                  },
            onNext: index == state.groups.length - 1
                ? null
                : () {
                    setState(() {
                      _index = index + 1;
                      _selectedPhotoIndex = 0;
                    });
                    _saveCheckpoint(state.groups[_index], 0);
                  },
          ),
        );
      },
    ),
  );

  void _restoreInitialPosition(List<BirdGroup> groups) {
    if (_restoredInitialPosition) return;
    final requestedGroupId = widget.reviewContext.groupId;
    final requestedGroupIndex = requestedGroupId == null ? -1 : groups.indexWhere((group) => group.id == requestedGroupId);
    _index = requestedGroupIndex < 0 ? 0 : requestedGroupIndex;
    final ids = _orderedPhotoIds(groups[_index]);
    final requestedPhotoId = widget.reviewContext.currentPhotoId;
    final requestedPhotoIndex = requestedPhotoId == null ? -1 : ids.indexOf(requestedPhotoId);
    _selectedPhotoIndex = requestedPhotoIndex >= 0
        ? requestedPhotoIndex
        : widget.reviewContext.currentIndex.clamp(
            0,
            ids.isEmpty ? 0 : ids.length - 1,
          );
    _restoredInitialPosition = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _saveCheckpoint(groups[_index], _selectedPhotoIndex);
      }
    });
  }

  void _saveCheckpoint(BirdGroup group, int photoIndex) {
    final deviceId = widget.deviceId?.trim();
    if (deviceId == null || deviceId.isEmpty) return;
    final reviewContext = _contextForGroup(
      widget.reviewContext,
      group,
      initialIndex: photoIndex,
    );
    final previous = widget.checkpointStore.read(
      deviceId: deviceId,
      batchId: reviewContext.batchId,
    );
    unawaited(
      widget.checkpointStore.save(
        ReviewCheckpoint.fromContext(
          deviceId: deviceId,
          context: reviewContext,
          query: previous?.query ?? const PhotoQuery(),
        ),
      ),
    );
  }
}

List<String> _orderedPhotoIds(BirdGroup group) => group.rankOrder.isEmpty ? group.memberFileIds : group.rankOrder;

ReviewContext _contextForGroup(
  ReviewContext baseContext,
  BirdGroup group, {
  int initialIndex = 0,
}) {
  final base = baseContext.sceneId == null && group.sceneId != null
      ? ReviewContext(
          batchId: baseContext.batchId,
          batchName: baseContext.batchName,
          sceneId: group.sceneId,
        )
      : baseContext;
  return base.enterGroup(
    group.id,
    name: _displayGroupName(group.id),
    photos: _orderedPhotoIds(group),
    initialIndex: initialIndex,
  );
}

class _GroupContent extends StatelessWidget {
  const _GroupContent({
    required this.group,
    required this.index,
    required this.total,
    required this.reviewContext,
    required this.media,
    required this.selectedPhotoIndex,
    required this.thumbnailSize,
    required this.comparisonGroups,
    required this.comparisonGroupIndex,
    required this.applyToWholeGroup,
    required this.onScopeChanged,
    required this.onSelectPhoto,
    this.onPrevious,
    this.onNext,
  });

  final BirdGroup group;
  final int index;
  final int total;
  final ReviewContext reviewContext;
  final ReviewMediaContext media;
  final int selectedPhotoIndex;
  final String thumbnailSize;
  final List<ReviewContext> comparisonGroups;
  final int comparisonGroupIndex;
  final bool applyToWholeGroup;
  final ValueChanged<bool> onScopeChanged;
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
    final memberStates = photos.map((photo) => KeepStateWireValue.fromWire(photo.keepState)).toSet();
    final activeKeepState = applyToWholeGroup
        ? memberStates.length == 1
              ? memberStates.first
              : null
        : selectedKeepState;
    final score = representative?.rating?.totalScore;
    final reasons = group.recommendationReasons.take(3).toList();
    final busy = context.select<GroupReviewCubit, bool>((cubit) => cubit.state.actingGroupId == group.id);
    final thumbnailExtent = _thumbnailExtent(thumbnailSize);

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
                    media: media,
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
          height: thumbnailExtent + 22,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, photoIndex) => _Thumbnail(
              photo: photos[photoIndex],
              media: media,
              rank: photoIndex + 1,
              selected: photoIndex == selectedIndex,
              extent: thumbnailExtent,
              onTap: () => onSelectPhoto(photoIndex),
            ),
          ),
        ),
        const SizedBox(height: 16),
        GroupReviewScopeSelector(
          applyToWholeGroup: applyToWholeGroup,
          memberCount: group.memberFileIds.length,
          onChanged: busy ? null : onScopeChanged,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MarkButton(label: '弃选', icon: Icons.delete_outline, color: AppColors.danger, filled: activeKeepState == KeepState.discard, onTap: busy ? null : () => _mark(context, representativeId, KeepState.discard)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '待确认', icon: Icons.help_outline, color: AppColors.amber, filled: activeKeepState == KeepState.pending, onTap: busy ? null : () => _mark(context, representativeId, KeepState.pending)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '保留', icon: Icons.check_circle_outline, color: AppColors.brand, filled: activeKeepState == KeepState.keep, onTap: busy ? null : () => _mark(context, representativeId, KeepState.keep)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MarkButton(label: '精选', icon: Icons.star_outline, color: AppColors.amber, filled: activeKeepState == KeepState.featured, onTap: busy ? null : () => _mark(context, representativeId, KeepState.featured)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GroupReviewComparisonAction(
          onPressed: rankedIds.length < 2
              ? null
              : () {
                  final comparisonContext = comparisonGroups.isEmpty
                      ? reviewContext.enterGroup(
                          group.id,
                          name: _displayGroupName(group.id),
                          photos: rankedIds.take(2).toList(growable: false),
                        )
                      : comparisonGroups[comparisonGroupIndex];
                  Navigator.of(context).pushNamed(
                    BirdRoutes.comparisonReview,
                    arguments: ComparisonReviewArgs.fromReview(
                      comparisonContext,
                      groups: comparisonGroups,
                      initialGroupIndex: comparisonGroupIndex,
                    ),
                  );
                },
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

  Future<void> _mark(
    BuildContext context,
    String id,
    KeepState state,
  ) async {
    final cubit = context.read<GroupReviewCubit>();
    if (!applyToWholeGroup) {
      await cubit.markFile(group, id, state);
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认整组修改？'),
        content: Text(
          '将把本组 ${group.memberFileIds.length} 张照片全部设为'
          '“${_keepStateActionLabel(state)}”。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (approved == true && context.mounted) {
      await cubit.markGroup(group, state);
    }
  }
}

String _keepStateActionLabel(KeepState state) => switch (state) {
  KeepState.pending => '待确认',
  KeepState.keep => '保留',
  KeepState.discard => '弃选',
  KeepState.featured => '精选',
};

class _HeroPhoto extends StatelessWidget {
  const _HeroPhoto({
    required this.media,
    this.photo,
    this.recommended = false,
    this.score,
    this.reasons = const [],
  });

  final ReviewMediaContext media;
  final PhotoSummary? photo;
  final bool recommended;
  final double? score;
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.25,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              ProgressivePhotoImage(
                photo: photo!,
                kind: MediaAssetKind.preview,
                loader: media.loader,
                coordinator: media.coordinator,
                deviceNamespace: media.deviceNamespace,
                allowNetworkFallback: media.allowNetworkFallback,
                fallbackToThumbnail: true,
                fit: BoxFit.cover,
                cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(320, 1440),
                legacyCacheVariant: 'group-hero',
                missingBuilder: (_) => const ColoredBox(
                  color: AppColors.brandLight,
                  child: Icon(
                    Icons.photo_outlined,
                    size: 64,
                    color: AppColors.brand,
                  ),
                ),
                placeholderBuilder: (_) => const _PhotoPlaceholder(),
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
  const _Thumbnail({
    required this.photo,
    required this.media,
    required this.rank,
    required this.selected,
    required this.extent,
    required this.onTap,
  });

  final PhotoSummary photo;
  final ReviewMediaContext media;
  final int rank;
  final bool selected;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BirdPressable(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: extent,
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
              ProgressivePhotoImage(
                photo: photo,
                kind: MediaAssetKind.thumbnail,
                loader: media.loader,
                coordinator: media.coordinator,
                deviceNamespace: media.deviceNamespace,
                allowNetworkFallback: media.allowNetworkFallback,
                fit: BoxFit.cover,
                cacheWidth: (extent * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(76, 512),
                cacheHeight: (extent * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(76, 512),
                legacyCacheVariant: 'group-thumbnail',
                missingBuilder: (_) => const ColoredBox(
                  color: AppColors.mist,
                  child: Icon(Icons.photo_outlined),
                ),
                placeholderBuilder: (_) => const _PhotoPlaceholder(compact: true),
              ),
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

double _thumbnailExtent(String preference) => switch (preference) {
  'small' => 76,
  'large' => 116,
  _ => 96,
};

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
