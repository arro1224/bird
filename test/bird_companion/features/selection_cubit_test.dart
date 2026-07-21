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
    expect(cubit.state.phase, SelectionPhase.idle);
    expect(cubit.state.canUndo, isTrue);
    expect(cubit.takeUndoActions().single.operation, 'pending');
    expect(cubit.state.canUndo, isFalse);
  });

  test('部分成功时退出选择态并保留失败角标', () {
    final cubit = SelectionCubit()
      ..toggle('photo-1')
      ..toggle('photo-2');
    cubit.begin();
    cubit.complete(
      succeededIds: const ['photo-1'],
      failed: const {'photo-2': '设备断开'},
    );

    expect(cubit.state.ids, isEmpty);
    expect(cubit.state.phase, SelectionPhase.idle);
    expect(cubit.state.failed, contains('photo-2'));
  });

  test('全部失败时保留失败项以便重试或取消', () {
    final cubit = SelectionCubit()
      ..toggle('photo-1')
      ..toggle('photo-2');
    cubit.begin();
    cubit.complete(
      succeededIds: const [],
      failed: const {'photo-1': '超时', 'photo-2': '超时'},
    );

    expect(cubit.state.ids, {'photo-1', 'photo-2'});
    expect(cubit.state.phase, SelectionPhase.partialFailure);
    expect(cubit.state.submitting, isFalse);
  });
}
