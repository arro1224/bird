import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/comparison_review_cubit.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/comparison_review_actions.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/comparison_photo_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ComparisonReviewPage extends StatefulWidget {
  const ComparisonReviewPage({super.key, required this.args});
  final ComparisonReviewArgs args;

  @override
  State<ComparisonReviewPage> createState() => _ComparisonReviewPageState();
}

class _ComparisonReviewPageState extends State<ComparisonReviewPage> {
  final _transform = TransformationController();
  var _syncZoom = true;
  var _selectedIndex = 0;
  late int _groupIndex;

  List<ReviewContext> get _groups => widget.args.groups;

  ReviewContext? get _activeGroup {
    if (_groups.isNotEmpty) return _groups[_groupIndex];
    return widget.args.reviewContext;
  }

  List<String> get _activeFileIds => _activeGroup?.photoIds ?? widget.args.fileIds;

  String get _activeGroupId => _activeGroup?.groupId ?? widget.args.groupId;

  @override
  void initState() {
    super.initState();
    _groupIndex = _groups.isEmpty ? 0 : widget.args.initialGroupIndex.clamp(0, _groups.length - 1);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ComparisonReviewCubit(
      BirdCompanionScope.of(context).reviewRepository,
      BirdCompanionScope.of(context).refreshCoordinator,
      BirdCompanionScope.of(context).dataChangeBus,
      _activeGroup?.batchId,
    )..load(_activeFileIds.take(2).toList()),
    child: Scaffold(
      backgroundColor: AppColors.paper,
      appBar: BirdSecondaryAppBar(
        title: '照片对比',
        subtitle: _displayGroupName(
          _activeGroup?.groupName ?? _activeGroupId,
        ),
        helpTooltip: '对比说明',
        onHelp: () => showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            title: Text('如何对比？'),
            content: Text('点击左右照片选中目标，可保留任意一张或同时保留两张。精选只作用于当前选中照片，不会取消另一张已有的保留状态。'),
          ),
        ),
      ),
      body: NaturalBackdrop(
        dense: true,
        child: BlocConsumer<ComparisonReviewCubit, ComparisonReviewState>(
          listenWhen: (previous, current) => (previous.message != current.message && current.message != null) || (previous.error != current.error && current.error != null),
          listener: (context, state) {
            if (state.error != null) {
              final message = UserMessageMapper.fromError(state.error!);
              BirdFeedback.error(context, message.message);
            } else if (state.message != null) {
              if (state.messageIsError) {
                BirdFeedback.error(context, state.message!);
              } else {
                BirdFeedback.success(context, state.message!);
              }
            }
          },
          builder: (context, state) {
            if (state.loading) return const Center(child: CircularProgressIndicator());
            if (state.error != null && state.items.isEmpty) {
              final message = UserMessageMapper.fromError(state.error!);
              return ErrorNotice(
                title: '无法加载对比照片',
                message: message.message,
                onRetry: () => context.read<ComparisonReviewCubit>().load(
                  _activeFileIds.take(2).toList(),
                ),
              );
            }
            if (state.items.length < 2) return const Center(child: Text('对比至少需要两张照片'));
            if (_selectedIndex >= state.items.length) {
              _selectedIndex = 0;
            }
            final selectedState = _decisionState(
              state.items[_selectedIndex],
            );
            return SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        _displayGroupName(_activeGroupId),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _syncZoom = !_syncZoom;
                          _transform.value = Matrix4.identity();
                        }),
                        icon: Icon(_syncZoom ? Icons.check_circle_outline_rounded : Icons.link_off_rounded),
                        label: Text(_syncZoom ? '同步缩放已开启' : '已切换为独立缩放'),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: (constraints.maxWidth * 1.12).clamp(420.0, 490.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              for (var index = 0; index < state.items.length; index++) ...[
                                if (index > 0) const SizedBox(width: 10),
                                Expanded(
                                  child: ComparisonPhotoPane(
                                    detail: state.items[index],
                                    rank: index,
                                    selected: _selectedIndex == index,
                                    saving: state.savingBoth || state.savingId == state.items[index].photo.summary.id,
                                    transformationController: _syncZoom ? _transform : null,
                                    onTap: () => setState(() => _selectedIndex = index),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
                        child: ComparisonReviewActions(
                          selectedState: selectedState,
                          itemCount: state.items.length,
                          busy: state.saving,
                          onDiscardSelected: () => _mark(
                            context,
                            state,
                            _selectedIndex,
                            KeepState.discard,
                          ),
                          onKeepSelected: () => _mark(
                            context,
                            state,
                            _selectedIndex,
                            KeepState.keep,
                          ),
                          onKeepAll: () => context.read<ComparisonReviewCubit>().keepAll(),
                          onFeatureSelected: () => _mark(
                            context,
                            state,
                            _selectedIndex,
                            KeepState.featured,
                          ),
                        ),
                      ),
                      if (_groups.length > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            24,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: state.saving || _groupIndex == 0 ? null : () => _moveGroup(context, -1),
                                  icon: const Icon(
                                    Icons.chevron_left_rounded,
                                  ),
                                  label: const Text('上一组'),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  '${_groupIndex + 1} / ${_groups.length}',
                                  style: const TextStyle(
                                    color: AppColors.inkMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: state.saving || _groupIndex == _groups.length - 1 ? null : () => _moveGroup(context, 1),
                                  icon: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  iconAlignment: IconAlignment.end,
                                  label: const Text('下一组'),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  void _mark(BuildContext context, ComparisonReviewState state, int index, KeepState value) {
    if (state.saving || index >= state.items.length) return;
    if (value.isRetained && _selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
    context.read<ComparisonReviewCubit>().mark(state.items[index].photo.summary.id, value);
  }

  void _moveGroup(BuildContext context, int delta) {
    final next = (_groupIndex + delta).clamp(0, _groups.length - 1);
    if (next == _groupIndex) return;
    setState(() {
      _groupIndex = next;
      _selectedIndex = 0;
      _transform.value = Matrix4.identity();
    });
    context.read<ComparisonReviewCubit>().load(
      _activeFileIds.take(2).toList(),
    );
  }
}

String _displayGroupName(String? value) {
  if (value == null || value.isEmpty) return '连拍照片';
  final match = RegExp(r'(\d+)$').firstMatch(value);
  if (match == null) return value;
  return '第 ${int.parse(match.group(1)!)} 组连拍照片';
}

KeepState _decisionState(ReviewDetail detail) => detail.decision?.keepState ?? KeepStateWireValue.fromWire(detail.photo.summary.keepState);
