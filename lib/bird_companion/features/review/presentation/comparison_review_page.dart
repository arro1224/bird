import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
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
    )..load(widget.args.fileIds.take(2).toList()),
    child: Scaffold(
      backgroundColor: AppColors.paper,
      appBar: BirdSecondaryAppBar(
        title: '照片对比',
        subtitle: _displayGroupName(widget.args.reviewContext?.groupName ?? widget.args.groupId),
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
          listenWhen: (previous, current) => previous.message != current.message && current.message != null,
          listener: (context, state) => BirdFeedback.success(context, state.message!),
          builder: (context, state) {
            if (state.loading) return const Center(child: CircularProgressIndicator());
            if (state.error != null && state.items.isEmpty) return Center(child: Text('无法加载对比照片：${state.error}'));
            if (state.items.length < 2) return const Center(child: Text('对比至少需要两张照片'));
            final leftRetained = _decisionState(state.items[0]).isRetained;
            final rightRetained = _decisionState(state.items[1]).isRetained;
            return SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(_displayGroupName(widget.args.groupId), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark)),
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
                              for (var index = 0; index < 2; index++) ...[
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
                          leftRetained: leftRetained,
                          rightRetained: rightRetained,
                          selectedFeatured: _decisionState(state.items[_selectedIndex]) == KeepState.featured,
                          busy: state.saving,
                          onKeepLeft: () => _mark(context, state, 0, KeepState.keep),
                          onKeepRight: () => _mark(context, state, 1, KeepState.keep),
                          onKeepBoth: () => context.read<ComparisonReviewCubit>().keepBoth(),
                          onFeatureSelected: () => _mark(context, state, _selectedIndex, KeepState.featured),
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
}

String _displayGroupName(String? value) {
  if (value == null || value.isEmpty) return '连拍照片';
  final match = RegExp(r'(\d+)$').firstMatch(value);
  if (match == null) return value;
  return '第 ${int.parse(match.group(1)!)} 组连拍照片';
}

KeepState _decisionState(ReviewDetail detail) => detail.decision?.keepState ?? KeepStateWireValue.fromWire(detail.photo.summary.keepState);
