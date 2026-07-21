import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/comparison_review_cubit.dart';
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
            content: Text('点击左右照片选中目标，可保留任意一张，或将当前选中照片设为精选。'),
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
                                    saving: state.savingId == state.items[index].photo.summary.id,
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
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _ComparisonActionButton(
                                    label: '保留左图',
                                    selected: _decisionState(state.items[0]) == KeepState.keep,
                                    onPressed: state.savingId == null ? () => _mark(context, state, 0, KeepState.keep) : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ComparisonActionButton(
                                    label: '保留右图',
                                    selected: _decisionState(state.items[1]) == KeepState.keep,
                                    onPressed: state.savingId == null ? () => _mark(context, state, 1, KeepState.keep) : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: _ComparisonActionButton(
                                label: '将选中照片设为精选',
                                selected: _decisionState(state.items[_selectedIndex]) == KeepState.featured,
                                featured: true,
                                onPressed: state.savingId == null ? () => _mark(context, state, _selectedIndex, KeepState.featured) : null,
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
    if (state.savingId != null || index >= state.items.length) return;
    context.read<ComparisonReviewCubit>().mark(state.items[index].photo.summary.id, value);
  }
}

String _displayGroupName(String? value) {
  if (value == null || value.isEmpty) return '连拍照片';
  final match = RegExp(r'(\d+)$').firstMatch(value);
  if (match == null) return value;
  return '第 ${int.parse(match.group(1)!)} 组连拍照片';
}

class _ComparisonActionButton extends StatelessWidget {
  const _ComparisonActionButton({required this.label, required this.selected, required this.onPressed, this.featured = false});

  final String label;
  final bool selected;
  final bool featured;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = featured ? AppColors.amber : AppColors.brand;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : color,
        backgroundColor: selected ? color : Colors.transparent,
        side: BorderSide(color: selected ? color : AppColors.outline),
      ),
      icon: Icon(featured ? Icons.star_outline_rounded : Icons.check_circle_outline),
      label: Text(selected ? (featured ? '已设为精选' : '$label（已选）') : label),
    );
  }
}

KeepState _decisionState(ReviewDetail detail) => detail.decision?.keepState ?? KeepStateWireValue.fromWire(detail.photo.summary.keepState);
