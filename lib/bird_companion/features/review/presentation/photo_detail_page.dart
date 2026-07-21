import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/presentation/user_facing_text.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/photo_detail_cubit.dart';
import 'package:aves/bird_companion/features/review/presentation/review_edit_page.dart';
import 'package:aves/bird_companion/features/review/presentation/version_history_page.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/conflict_dialog.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/exif_panel.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/rating_reason_panel.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/recognition_panel.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/subject_overlay_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PhotoDetailPage extends StatelessWidget {
  const PhotoDetailPage({
    super.key,
    required this.fileId,
    this.displayIndex,
    this.totalCount,
    this.sequence = const [],
    this.reviewContext,
  });
  final String fileId;
  final int? displayIndex;
  final int? totalCount;
  final List<String> sequence;
  final ReviewContext? reviewContext;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PhotoDetailCubit(
      BirdCompanionScope.of(context).reviewRepository,
      BirdCompanionScope.of(context).refreshCoordinator,
      BirdCompanionScope.of(context).dataChangeBus,
    )..load(fileId),
    child: _View(
      fileId: fileId,
      displayIndex: displayIndex,
      totalCount: totalCount,
      sequence: sequence,
      reviewContext: reviewContext,
    ),
  );
}

class _View extends StatefulWidget {
  const _View({
    required this.fileId,
    this.displayIndex,
    this.totalCount,
    required this.sequence,
    this.reviewContext,
  });
  final String fileId;
  final int? displayIndex;
  final int? totalCount;
  final List<String> sequence;
  final ReviewContext? reviewContext;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  KeepState _keep = KeepState.pending;
  String? _speciesId;
  final _species = TextEditingController();
  final _score = TextEditingController();
  final _tags = TextEditingController();
  String? _appliedRevision;
  var _showSubjects = false;
  late int _currentIndex;

  List<String> get _sequence => widget.reviewContext?.photoIds.isNotEmpty == true ? widget.reviewContext!.photoIds : widget.sequence;

  String get _currentFileId => _sequence.isEmpty ? widget.fileId : _sequence[_currentIndex.clamp(0, _sequence.length - 1)];

  int? get _currentDisplayIndex => _sequence.isEmpty ? widget.displayIndex : _currentIndex + 1;

  @override
  void initState() {
    super.initState();
    final contextIndex = widget.reviewContext?.safeCurrentIndex;
    final sequenceIndex = _sequence.indexOf(widget.fileId);
    _currentIndex = contextIndex ?? (sequenceIndex < 0 ? 0 : sequenceIndex);
  }

  @override
  void dispose() {
    _species.dispose();
    _score.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _applyExisting(ReviewDetail detail) {
    final revision = '${detail.decision?.version ?? 0}-${detail.history.length}-${detail.decision?.updatedAt?.millisecondsSinceEpoch ?? 0}';
    if (_appliedRevision == revision) return;
    final decision = detail.decision;
    final candidates = detail.photo.summary.recognition?.candidates ?? const [];
    _keep = decision?.keepState ?? KeepState.pending;
    _speciesId = decision?.userSpeciesId;
    _species.text = decision?.userSpecies ?? (candidates.isEmpty ? '' : candidates.first.name);
    _score.text = decision?.userScore?.toString() ?? detail.photo.summary.rating?.totalScore.toString() ?? '';
    _tags.text = decision?.userTags.join(', ') ?? detail.photo.tags.map((tag) => tag.name).join(', ');
    _appliedRevision = revision;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: BirdSecondaryAppBar(
      title: _currentDisplayIndex == null ? _currentFileId : '$_currentDisplayIndex / ${widget.totalCount ?? _sequence.length}',
      trailing: [
        BlocBuilder<PhotoDetailCubit, PhotoDetailState>(
          builder: (context, state) => PopupMenuButton<String>(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_horiz_rounded),
            position: PopupMenuPosition.under,
            offset: const Offset(-8, 8),
            elevation: 8,
            color: AppColors.paperStrong,
            surfaceTintColor: Colors.transparent,
            constraints: const BoxConstraints.tightFor(width: 260),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppColors.outline),
            ),
            onSelected: (value) => _handleMenu(context, state, value),
            itemBuilder: (_) => [
              if (_previousId != null)
                const PopupMenuItem(
                  value: 'previous',
                  height: 52,
                  child: _DetailMenuItem(icon: Icons.chevron_left_rounded, label: '上一张'),
                ),
              if (_nextId != null)
                const PopupMenuItem(
                  value: 'next',
                  height: 52,
                  child: _DetailMenuItem(icon: Icons.chevron_right_rounded, label: '下一张'),
                ),
              const PopupMenuItem(
                value: 'featured',
                height: 52,
                child: _DetailMenuItem(icon: Icons.star_outline_rounded, label: '设为精选'),
              ),
              const PopupMenuItem(
                value: 'pending',
                height: 52,
                child: _DetailMenuItem(icon: Icons.help_outline_rounded, label: '标记待确认'),
              ),
              const PopupMenuItem(
                value: 'history',
                height: 52,
                child: _DetailMenuItem(icon: Icons.history_rounded, label: '修改记录'),
              ),
              if (state.canUndo)
                const PopupMenuItem(
                  value: 'undo',
                  height: 52,
                  child: _DetailMenuItem(icon: Icons.undo_rounded, label: '撤销最近修改'),
                ),
            ],
          ),
        ),
      ],
    ),
    body: BlocConsumer<PhotoDetailCubit, PhotoDetailState>(
      listenWhen: (previous, current) => previous.conflict != current.conflict || previous.message != current.message,
      listener: (context, state) {
        if (state.conflict) {
          showDialog<ConflictChoice>(context: context, builder: (_) => const ConflictDialog()).then((choice) {
            if (!context.mounted) return;
            if (choice == ConflictChoice.remote) context.read<PhotoDetailCubit>().useRemote(_currentFileId);
            if (choice == ConflictChoice.local) context.read<PhotoDetailCubit>().keepLocal();
          });
        }
        if (state.message != null) {
          if (state.detail == null) {
            BirdFeedback.error(context, state.message!);
          } else {
            BirdFeedback.success(context, state.message!);
          }
        }
      },
      builder: (context, state) {
        final detail = state.detail;
        if (detail == null) return Center(child: state.message == null ? const CircularProgressIndicator() : Text(state.message!));
        _applyExisting(detail);
        return NaturalBackdrop(
          dense: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SubjectOverlayView(photo: detail.photo, subjects: _showSubjects ? detail.photo.subjects : const []),
              const SizedBox(height: 12),
              _RecognitionSummary(
                detail: detail,
                species: _species.text,
                onEdit: () => _openEditor(context, detail),
              ),
              const SizedBox(height: 12),
              _QuickActions(
                saving: state.saving,
                keepState: _keep,
                onDiscard: () => _save(context, detail, KeepState.discard),
                onTags: () => _editTags(context, detail),
                onKeep: () => _save(context, detail, KeepState.keep),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ExpansionTile(
                      leading: const Icon(Icons.bar_chart_rounded, color: AppColors.brand),
                      title: const Text(
                        '详细指标',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.brandDark),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: [
                        RecognitionPanel(value: detail.photo.summary.recognition),
                        const SizedBox(height: 10),
                        RatingReasonPanel(value: detail.photo.summary.rating),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('标出照片中的鸟'),
                          value: _showSubjects,
                          onChanged: (value) => setState(() => _showSubjects = value),
                        ),
                      ],
                    ),
                    const Divider(),
                    ExpansionTile(
                      leading: const Icon(Icons.info_outline_rounded, color: AppColors.brand),
                      title: const Text(
                        '更多信息',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.brandDark),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: [
                        ListTile(title: const Text('文件名'), trailing: Text(detail.photo.summary.filename)),
                        ListTile(title: const Text('拍摄时间'), trailing: Text(_formatCapturedAt(detail.photo.summary.capturedAt))),
                        ExifPanel(exif: detail.photo.exif),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VersionHistoryPage(items: detail.history))),
                            icon: const Icon(Icons.history_rounded),
                            label: const Text('查看修改记录'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  String? get _previousId {
    return _currentIndex > 0 && _sequence.isNotEmpty ? _sequence[_currentIndex - 1] : null;
  }

  String? get _nextId {
    return _sequence.isNotEmpty && _currentIndex + 1 < _sequence.length ? _sequence[_currentIndex + 1] : null;
  }

  void _handleMenu(BuildContext context, PhotoDetailState state, String value) {
    final detail = state.detail;
    if (detail == null || state.loading || state.saving) return;
    if (value == 'undo') {
      context.read<PhotoDetailCubit>().undo();
      return;
    }
    if (value == 'history') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => VersionHistoryPage(items: detail.history)));
      return;
    }
    if (value == 'featured') {
      _save(context, detail, KeepState.featured);
      return;
    }
    if (value == 'pending') {
      _save(context, detail, KeepState.pending);
      return;
    }
    final id = value == 'previous' ? _previousId : _nextId;
    if (id == null) return;
    _openInPlace(context, id);
  }

  Future<void> _openInPlace(BuildContext context, String id) async {
    final index = _sequence.indexOf(id);
    if (index < 0 || index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _appliedRevision = null;
      _showSubjects = false;
    });
    await context.read<PhotoDetailCubit>().load(id);
  }

  Future<void> _save(BuildContext context, ReviewDetail detail, KeepState value) async {
    setState(() => _keep = value);
    await context.read<PhotoDetailCubit>().save(_decision(detail, keepState: value));
  }

  UserDecision _decision(ReviewDetail detail, {KeepState? keepState}) => UserDecision(
    fileId: _currentFileId,
    keepState: keepState ?? _keep,
    userSpeciesId: _speciesId,
    userSpecies: _species.text.trim().isEmpty ? null : _species.text.trim(),
    userScore: double.tryParse(_score.text),
    userTags: _tags.text.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList(),
    updatedAt: DateTime.now(),
    version: detail.decision?.version,
  );

  Future<void> _editTags(BuildContext context, ReviewDetail detail) async {
    final controller = TextEditingController(text: _tags.text);
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('添加标签', style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例如：翠鸟，水鸟，枝头'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(sheetContext, controller.text), child: const Text('保存标签')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() => _tags.text = value);
    await context.read<PhotoDetailCubit>().save(_decision(detail));
  }

  Future<void> _openEditor(BuildContext context, ReviewDetail detail) async {
    final result = await Navigator.of(context).push<ReviewEditResult>(
      MaterialPageRoute(
        builder: (_) => ReviewEditPage(
          keepState: _keep,
          species: _species.text,
          score: _score.text,
          tags: _tags.text,
          initialCandidates: detail.photo.summary.recognition?.candidates ?? const [],
          previewUri: detail.photo.summary.preview.previewUri,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _keep = result.keepState;
      _speciesId = result.speciesId;
      _species.text = result.species;
      _score.text = result.score;
      _tags.text = result.tags;
    });
    await context.read<PhotoDetailCubit>().save(_decision(detail));
  }
}

class _DetailMenuItem extends StatelessWidget {
  const _DetailMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22, color: AppColors.brand),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.brandDark),
        ),
      ),
    ],
  );
}

class _RecognitionSummary extends StatelessWidget {
  const _RecognitionSummary({required this.detail, required this.species, required this.onEdit});
  final ReviewDetail detail;
  final String species;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final summary = detail.photo.summary;
    final candidate = summary.recognition?.candidates.firstOrNull;
    final confidence = candidate?.confidence;
    final score = summary.rating?.totalScore;
    final quality = score == null
        ? '待评估'
        : score >= 4.5
        ? '优秀'
        : score >= 3.5
        ? '良好'
        : '一般';
    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      species.isEmpty ? '待确认鸟种' : species,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (summary.isRecommended) const Chip(label: Text('建议保留')),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, color: AppColors.brand),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                confidence == null ? '识别度：等待确认' : '识别度：${UserFacingText.recognitionCertaintyWithPercent(confidence)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (confidence != null) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: confidence, minHeight: 7, borderRadius: BorderRadius.circular(99)),
              ],
              const SizedBox(height: 14),
              Text('照片质量：$quality', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.brand)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.saving, required this.keepState, required this.onDiscard, required this.onTags, required this.onKeep});
  final bool saving;
  final KeepState keepState;
  final VoidCallback onDiscard;
  final VoidCallback onTags;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: saving ? null : onDiscard,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: const Text('弃用', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
              onPressed: saving ? null : onTags,
              icon: const Icon(Icons.sell_outlined, size: 19),
              label: const Text('添加标签', maxLines: 1, style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 5)),
              onPressed: saving ? null : onKeep,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(keepState == KeepState.keep ? '已保留' : '保留', maxLines: 1, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatCapturedAt(DateTime? value) {
  if (value == null) return '盒子未提供';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
