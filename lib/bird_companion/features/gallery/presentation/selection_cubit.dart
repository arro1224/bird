import 'package:flutter_bloc/flutter_bloc.dart';

class BatchUndoAction {
  const BatchUndoAction({
    required this.operation,
    required this.ids,
    this.value,
    this.transitionFromOperation,
  });
  final String operation;
  final List<String> ids;
  final Object? value;

  /// The state currently applied to [ids] before this undo action runs.
  /// Tags leave this null because they do not affect review counters.
  final String? transitionFromOperation;
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
        // Once the user changes the selection manually, the previous attempt
        // no longer describes the selected set and its failure markers are
        // stale. A direct retry does not call toggle(), so it keeps them.
        clearFailed: true,
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
    final retryableFailures = {
      for (final id in failedIds) id: failed[id]!,
    };
    emit(
      state.copyWith(
        // Successful items leave selection. Failed items remain selected so
        // the existing action sheet can present a one-tap retry.
        ids: failedIds,
        phase: failedIds.isEmpty ? SelectionPhase.idle : SelectionPhase.partialFailure,
        failed: retryableFailures,
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
