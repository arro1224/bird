import 'package:flutter_bloc/flutter_bloc.dart';

class BatchUndoAction {
  const BatchUndoAction({required this.operation, required this.ids, this.value});
  final String operation;
  final List<String> ids;
  final Object? value;
}

enum SelectionPhase { idle, selecting, submitting, partialFailure }

class SelectionState {
  const SelectionState({
    this.ids = const {},
    this.phase = SelectionPhase.idle,
    this.failed = const {},
    this.undoActions = const [],
  });
  final Set<String> ids;
  final SelectionPhase phase;
  final Map<String, String> failed;
  final List<BatchUndoAction> undoActions;
  bool get submitting => phase == SelectionPhase.submitting;
  bool get isSelecting => ids.isNotEmpty;
  bool get hasPartialFailure => phase == SelectionPhase.partialFailure;
  bool get canUndo => undoActions.isNotEmpty && !submitting;

  SelectionState copyWith({
    Set<String>? ids,
    SelectionPhase? phase,
    Map<String, String>? failed,
    List<BatchUndoAction>? undoActions,
    bool clearFailed = false,
    bool clearUndo = false,
  }) => SelectionState(
    ids: ids ?? this.ids,
    phase: phase ?? this.phase,
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
    emit(
      state.copyWith(
        ids: next,
        phase: next.isEmpty ? SelectionPhase.idle : SelectionPhase.selecting,
        clearFailed: state.ids.isEmpty,
      ),
    );
  }

  void begin({bool preserveUndo = false}) => emit(
    state.copyWith(
      phase: SelectionPhase.submitting,
      clearFailed: true,
      clearUndo: !preserveUndo,
    ),
  );

  void complete({required List<String> succeededIds, required Map<String, String> failed}) {
    final attempted = {...state.ids};
    final failedIds = attempted.where(failed.containsKey).toSet();
    final allFailed = attempted.isNotEmpty && succeededIds.isEmpty && failedIds.isNotEmpty;
    emit(
      state.copyWith(
        ids: allFailed ? failedIds : const {},
        phase: allFailed ? SelectionPhase.partialFailure : SelectionPhase.idle,
        failed: failed,
      ),
    );
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
