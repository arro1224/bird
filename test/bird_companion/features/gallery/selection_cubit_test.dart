import 'package:aves/bird_companion/features/gallery/presentation/selection_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('部分失败时只保留失败照片以便直接重试', () {
    final cubit = SelectionCubit();
    addTearDown(cubit.close);
    cubit
      ..toggle('photo-1')
      ..toggle('photo-2')
      ..begin()
      ..complete(
        succeededIds: const ['photo-1'],
        failed: const {'photo-2': '盒子忙碌'},
      );

    expect(cubit.state.ids, {'photo-2'});
    expect(cubit.state.phase, SelectionPhase.partialFailure);
    expect(cubit.state.failed, {'photo-2': '盒子忙碌'});

    cubit
      ..begin()
      ..complete(succeededIds: const ['photo-2'], failed: const {});

    expect(cubit.state.ids, isEmpty);
    expect(cubit.state.phase, SelectionPhase.idle);
    expect(cubit.state.failed, isEmpty);
  });

  test('手动改变失败选择后清除上一次失败标记', () {
    final cubit = SelectionCubit();
    addTearDown(cubit.close);
    cubit
      ..toggle('photo-1')
      ..begin()
      ..complete(
        succeededIds: const [],
        failed: const {'photo-1': '网络中断'},
      )
      ..toggle('photo-2');

    expect(cubit.state.ids, {'photo-1', 'photo-2'});
    expect(cubit.state.phase, SelectionPhase.selecting);
    expect(cubit.state.failed, isEmpty);
  });
}
