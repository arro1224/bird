import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SceneListState {
  const SceneListState({this.items = const [], this.loading = false, this.error});

  final List<SceneSummary> items;
  final bool loading;
  final Object? error;
}

class SceneListCubit extends Cubit<SceneListState> {
  SceneListCubit(this._repository, this.batchId) : super(const SceneListState());

  final PhotoRepository _repository;
  final String batchId;

  Future<void> load() async {
    emit(SceneListState(items: state.items, loading: true));
    try {
      emit(SceneListState(items: await _repository.scenes(batchId)));
    } catch (error) {
      emit(SceneListState(items: state.items, error: error));
    }
  }
}
