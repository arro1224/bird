import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
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
      appBar: AppBar(
        leading: const BirdPageBackButton(),
        title: const Text('照片对比'),
        actions: [
          IconButton(
            tooltip: '对比说明',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(title: Text('如何对比？'), content: Text('点击左右照片选中目标，可保留任意一张，或将当前选中照片设为精选。')),
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: NaturalBackdrop(
        dense: true,
        child: BlocConsumer<ComparisonReviewCubit, ComparisonReviewState>(
          listenWhen: (previous, current) => previous.message != current.message && current.message != null,
          listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!))),
          builder: (context, state) {
            if (state.loading) return const Center(child: CircularProgressIndicator());
            if (state.error != null && state.items.isEmpty) return Center(child: Text('无法加载对比照片：${state.error}'));
            if (state.items.length < 2) return const Center(child: Text('对比至少需要两张照片'));
            return SafeArea(
              top: false,
              child: Column(
                children: [
                  Text(widget.args.groupId, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark)),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _syncZoom = !_syncZoom;
                      _transform.value = Matrix4.identity();
                    }),
                    icon: Icon(_syncZoom ? Icons.check_circle_outline_rounded : Icons.link_off_rounded),
                    label: Text(_syncZoom ? '同步缩放已开启' : '已切换为独立缩放'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
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
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(onPressed: () => _mark(context, state, 0, KeepState.keep), icon: const Icon(Icons.check_circle_outline), label: const Text('保留左图')),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(onPressed: () => _mark(context, state, 1, KeepState.keep), icon: const Icon(Icons.check_circle_outline), label: const Text('保留右图')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _mark(context, state, _selectedIndex, KeepState.featured),
                            icon: const Icon(Icons.star_outline_rounded),
                            label: const Text('将选中照片设为精选'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
