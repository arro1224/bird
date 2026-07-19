import 'package:aves/bird_companion/features/gallery/presentation/selection_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('批量操作保留可撤销的反向操作', () {
    final cubit = SelectionCubit()..toggle('photo-1');
    cubit.begin();
    cubit.complete(succeededIds: const ['photo-1'], failed: const {});
    cubit.setUndoActions(const [
      BatchUndoAction(operation: 'pending', ids: ['photo-1']),
    ]);

    expect(cubit.state.ids, isEmpty);
    expect(cubit.state.canUndo, isTrue);
    expect(cubit.takeUndoActions().single.operation, 'pending');
    expect(cubit.state.canUndo, isFalse);
  });
}
