import 'package:flutter_bloc/flutter_bloc.dart';

class BatchUndoAction {
  const BatchUndoAction({required this.operation, required this.ids, this.value});
  final String operation;
  final List<String> ids;
  final Object? value;
}

class SelectionState {
  const SelectionState({this.ids = const {}, this.submitting = false, this.failed = const {}, this.undoActions = const []});
  final Set<String> ids;
  final bool submitting;
  final Map<String, String> failed;
  final List<BatchUndoAction> undoActions;
  bool get canUndo => undoActions.isNotEmpty && !submitting;

  SelectionState copyWith({Set<String>? ids, bool? submitting, Map<String, String>? failed, List<BatchUndoAction>? undoActions, bool clearFailed = false, bool clearUndo = false}) => SelectionState(
    ids: ids ?? this.ids,
    submitting: submitting ?? this.submitting,
    failed: clearFailed ? const {} : failed ?? this.failed,
    undoActions: clearUndo ? const [] : undoActions ?? this.undoActions,
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

  void begin({bool preserveUndo = false}) => emit(state.copyWith(submitting: true, clearFailed: true, clearUndo: !preserveUndo));

  void complete({required List<String> succeededIds, required Map<String, String> failed}) {
    final remaining = {...state.ids}..removeAll(succeededIds);
    emit(state.copyWith(ids: remaining, submitting: false, failed: failed));
  }

  void setUndoActions(List<BatchUndoAction> actions) => emit(state.copyWith(undoActions: actions));

  List<BatchUndoAction> takeUndoActions() {
    final actions = state.undoActions;
    emit(state.copyWith(clearUndo: true));
    return actions;
  }

  void clear() {
    if (!state.submitting) emit(const SelectionState());
  }
}
