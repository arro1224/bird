import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
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
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ComparisonReviewCubit(BirdCompanionScope.of(context).reviewRepository, BirdCompanionScope.of(context).refreshCoordinator, BirdCompanionScope.of(context).dataChangeBus)..load(widget.args.fileIds),
    child: Scaffold(
      appBar: AppBar(leading: const BirdPageBackButton()),
      body: BlocBuilder<ComparisonReviewCubit, ComparisonReviewState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());
          if (state.error != null && state.items.isEmpty) return Center(child: Text('无法加载对比照片：${state.error}'));
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 4 : 2;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('对比审阅', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 7),
                        Text('${widget.args.groupId} · ${state.items.length} 张候选', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: .66),
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        final detail = state.items[index];
                        final id = detail.photo.summary.id;
                        return ComparisonPhotoPane(detail: detail, rank: index, saving: state.savingId == id, transformationController: _transform, onMark: (value) => context.read<ComparisonReviewCubit>().mark(id, value));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(onPressed: () => setState(() => _transform.value = Matrix4.identity()), child: const Text('重置同步缩放')),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}
