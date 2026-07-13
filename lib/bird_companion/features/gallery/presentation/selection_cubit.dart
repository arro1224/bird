import 'package:flutter_bloc/flutter_bloc.dart';

class SelectionState {
  const SelectionState({this.ids = const {}, this.submitting = false, this.failed = const {}});
  final Set<String> ids;
  final bool submitting;
  final Map<String, String> failed;

  SelectionState copyWith({Set<String>? ids, bool? submitting, Map<String, String>? failed, bool clearFailed = false}) => SelectionState(
    ids: ids ?? this.ids,
    submitting: submitting ?? this.submitting,
    failed: clearFailed ? const {} : failed ?? this.failed,
  );
}

class SelectionCubit extends Cubit<SelectionState> {
  SelectionCubit() : super(const SelectionState());

  void toggle(String id) {
    if (state.submitting) return;
    final next = {...state.ids};
    next.contains(id) ? next.remove(id) : next.add(id);
    emit(state.copyWith(ids: next));
  }

  void begin() => emit(state.copyWith(submitting: true, clearFailed: true));

  void complete({required List<String> succeededIds, required Map<String, String> failed}) {
    final remaining = {...state.ids}..removeAll(succeededIds);
    emit(state.copyWith(ids: remaining, submitting: false, failed: failed));
  }

  void clear() {
    if (!state.submitting) emit(const SelectionState());
  }
}
