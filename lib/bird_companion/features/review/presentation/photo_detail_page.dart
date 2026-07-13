import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/features/review/presentation/photo_detail_cubit.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/conflict_dialog.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/exif_panel.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/rating_reason_panel.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/recognition_panel.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/review_editor.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/subject_overlay_view.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/version_history_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PhotoDetailPage extends StatelessWidget {
  const PhotoDetailPage({super.key, required this.fileId});
  final String fileId;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PhotoDetailCubit(BirdCompanionScope.of(context).reviewRepository, BirdCompanionScope.of(context).refreshCoordinator, BirdCompanionScope.of(context).dataChangeBus)..load(fileId),
    child: _View(fileId: fileId),
  );
}

class _View extends StatefulWidget {
  const _View({required this.fileId});
  final String fileId;
  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  KeepState _keep = KeepState.pending;
  final _species = TextEditingController();
  final _score = TextEditingController();
  final _tags = TextEditingController();
  String? _appliedRevision;
  @override
  void dispose() {
    _species.dispose();
    _score.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _applyExisting(dynamic detail) {
    // A save, undo or "use box version" reloads the detail while this State
    // instance remains mounted. Synchronize the editor when that server
    // revision changes so stale text cannot be saved back over the new value.
    final revision = '${detail.decision?.version ?? 0}-${detail.history.length}-${detail.decision?.updatedAt?.millisecondsSinceEpoch ?? 0}';
    if (_appliedRevision == revision) return;
    final d = detail.decision;
    _keep = d?.keepState ?? KeepState.pending;
    final candidates = detail.photo.summary.recognition?.candidates ?? const [];
    _species.text = d?.userSpecies ?? (candidates.isEmpty ? '' : candidates.first.name);
    _score.text = d?.userScore?.toString() ?? detail.photo.summary.rating?.totalScore.toString() ?? '';
    _tags.text = d?.userTags.join(', ') ?? detail.photo.tags.map((tag) => tag.name).join(', ');
    _appliedRevision = revision;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BirdPageBackButton(),
      title: const Text('照片详情'),
      actions: [
        BlocBuilder<PhotoDetailCubit, PhotoDetailState>(
          builder: (context, state) => IconButton(tooltip: '撤销最近修改', onPressed: state.canUndo ? () => context.read<PhotoDetailCubit>().undo() : null, icon: const Icon(Icons.undo)),
        ),
      ],
    ),
    body: BlocConsumer<PhotoDetailCubit, PhotoDetailState>(
      listener: (context, state) {
        if (state.conflict) {
          showDialog<ConflictChoice>(context: context, builder: (_) => const ConflictDialog()).then((choice) {
            if (!context.mounted) return;
            if (choice == ConflictChoice.remote) context.read<PhotoDetailCubit>().useRemote(widget.fileId);
            if (choice == ConflictChoice.local) context.read<PhotoDetailCubit>().keepLocal();
          });
        }
        if (state.message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!)));
      },
      builder: (context, state) {
        final detail = state.detail;
        if (detail == null) return Center(child: state.message == null ? const CircularProgressIndicator() : Text(state.message!));
        _applyExisting(detail);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('照片详情', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                ),
                BirdPill(label: _keep == KeepState.pending ? '待人工确认' : '已人工确认'),
              ],
            ),
            const SizedBox(height: 16),
            SubjectOverlayView(photo: detail.photo, subjects: detail.photo.subjects),
            const SizedBox(height: 16),
            Text(detail.photo.summary.filename, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '拍摄时间：${_formatCapturedAt(detail.photo.summary.capturedAt)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text('AI 识别', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            RecognitionPanel(value: detail.photo.summary.recognition),
            RatingReasonPanel(value: detail.photo.summary.rating),
            const SizedBox(height: 24),
            ReviewEditor(keepState: _keep, speciesController: _species, scoreController: _score, tagsController: _tags, onKeepChanged: (value) => setState(() => _keep = value)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: state.saving
                  ? null
                  : () => context.read<PhotoDetailCubit>().save(
                      UserDecision(
                        fileId: widget.fileId,
                        keepState: _keep,
                        userSpecies: _species.text.trim().isEmpty ? null : _species.text.trim(),
                        userScore: double.tryParse(_score.text),
                        userTags: _tags.text.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList(),
                        updatedAt: DateTime.now(),
                        version: detail.decision?.version,
                      ),
                    ),
              child: Text(state.saving ? '正在保存…' : '保存人工修改'),
            ),
            ExifPanel(exif: detail.photo.exif),
            VersionHistoryPanel(items: detail.history),
          ],
        );
      },
    ),
  );
}

String _formatCapturedAt(DateTime? value) {
  if (value == null) return '盒子未提供';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
