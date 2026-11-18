import 'dart:math';

import 'repair_acceptance_profile.dart';

/// Deterministic replay for acceptance, sharing the normal simulated HTTP host.
/// Recognition and the copy queue have independent lifetimes and controls.
final class RepairAcceptanceWorkflow {
  RepairAcceptanceWorkflow(this.profile, this.photos);
  final RepairAcceptanceProfile profile;
  final List<Map<String, dynamic>> photos;
  String state = 'created';
  String? phase, blocker, errorCode, errorMessage;
  String targetMediaId = 'media_7f9a76e6c97690b61aedf6fd';
  int processed = 0, version = 0;
  int? cutoff;
  bool recognitionFinished = false, failNextWrite = false;
  final accepted = <int>{}, copied = <int>{}, failed = <int>{}, stopped = <int>{};
  Iterable<int> get queued => accepted.where((seq) => !copied.contains(seq) && !failed.contains(seq) && !stopped.contains(seq));
  bool get _canWrite => blocker == null && const {'following', 'draining'}.contains(state) && (phase == null || phase == 'awaiting_results');
  bool get _terminal => const {'completed', 'completed_partial', 'failed'}.contains(state);

  void start(String target) {
    reset();
    targetMediaId = target;
    state = 'following';
    version++;
  }

  List<String> get allowedActions {
    if (phase == 'pause_requested') return const [];
    return switch (state) {
      'following' => const ['pause', 'finish_current_results', 'stop_following'],
      'paused' => const ['resume', 'finish_current_results', 'stop_following'],
      'waiting_for_target' || 'waiting_for_source' => const ['pause', 'stop_following'],
      _ => const [],
    };
  }

  String? advance(Map<String, dynamic> body) {
    final action = body['action'];
    if (body['from_action'] == true) {
      if (body['expected_state_version'] != version) return 'SMART_FOLLOW_STATE_VERSION_CONFLICT';
      if (!allowedActions.contains(action)) return 'SMART_FOLLOW_ACTION_NOT_ALLOWED';
    } else if (_terminal && action != 'reset') {
      return 'SMART_FOLLOW_ACTION_NOT_ALLOWED';
    }
    switch (action) {
      case 'pause':
        phase = 'pause_requested';
      case 'resume':
        state = blocker == 'waiting_for_source'
            ? 'waiting_for_source'
            : blocker == 'waiting_for_target' || blocker == 'waiting_for_storage'
            ? 'waiting_for_target'
            : recognitionFinished
            ? 'draining'
            : 'following';
        phase = blocker;
      case 'finish_current_results':
        cutoff = processed;
        state = blocker == null ? 'draining' : state;
        phase = blocker;
      case 'stop_following':
        cutoff = processed;
        stopped.addAll(queued.toList());
        state = 'completed_partial';
        phase = null;
      case 'commit':
        final count = body['count'] ?? 1;
        if (count is! int || count < 0 || count > profile.total) return 'invalid recognition count';
        _recognize(count);
      case 'finish_recognition':
        if (processed != profile.total) return 'recognition results are not complete';
        recognitionFinished = true;
      case 'complete_children':
        if (_canWrite) _copy(queued.length);
      case 'wait_writer':
        state = 'following';
        phase = blocker = 'waiting_for_writer';
      case 'await_results':
        if (queued.isNotEmpty) return 'queued results still exist';
        state = 'following';
        phase = 'awaiting_results';
      case 'wait_target':
        state = 'waiting_for_target';
        phase = blocker = 'waiting_for_target';
        errorCode = 'SMART_FOLLOW_TARGET_UNAVAILABLE';
        errorMessage = '目标盘暂不可用，队列已保留';
      case 'wait_source':
        state = 'waiting_for_source';
        phase = blocker = 'waiting_for_source';
      case 'storage_unavailable':
        state = 'waiting_for_target';
        phase = blocker = 'waiting_for_storage';
        errorCode = 'SMART_FOLLOW_STORAGE_UNAVAILABLE';
        errorMessage = '存储服务暂不可用，队列已保留';
      case 'recover':
        if (body['target_media_id'] != null && body['target_media_id'] != targetMediaId) return 'SMART_FOLLOW_TARGET_ID_MISMATCH';
        state = state == 'paused'
            ? 'paused'
            : recognitionFinished || cutoff != null
            ? 'draining'
            : 'following';
        blocker = null;
        phase = null;
        errorCode = null;
        errorMessage = null;
      case 'fail_next_write':
        failNextWrite = true;
      case 'fail':
        cutoff = processed;
        state = 'failed';
        phase = null;
        errorCode = 'SMART_FOLLOW_RECONCILIATION_REQUIRED';
        errorMessage = '验收故障样例：复制需要核对';
      case 'reset':
        reset();
        return null;
      default:
        return 'unknown acceptance action';
    }
    _settle();
    version++;
    return null;
  }

  void tick({int recognitionCount = 5, bool completeWrites = true, bool recognitionRunning = true}) {
    if (state == 'created') return;
    final before = (processed, state, phase, copied.length, failed.length);
    if (phase == 'pause_requested') {
      state = 'paused';
      phase = null;
    }
    if (recognitionRunning) _recognize(recognitionCount);
    if (_canWrite && completeWrites) _copy(3);
    _settle();
    if (before != (processed, state, phase, copied.length, failed.length)) version++;
  }

  void _recognize(int count) {
    final end = min(profile.total, processed + count);
    while (processed < end) {
      final photo = photos[processed++];
      if (cutoff == null && !_terminal && RepairAcceptanceProfile.recognized(photo)) accepted.add(processed);
    }
    recognitionFinished = processed == profile.total;
    if (phase == 'awaiting_results' && queued.isNotEmpty) phase = null;
  }

  void _copy(int maximum) {
    for (final seq in queued.take(maximum).toList()) {
      if (failNextWrite) {
        failed.add(seq);
        failNextWrite = false;
      } else {
        copied.add(seq);
      }
    }
  }

  void _settle() {
    if (recognitionFinished && state == 'following' && _canWrite) state = 'draining';
    if (state == 'draining' && queued.isEmpty) state = failed.isNotEmpty || (cutoff != null && cutoff! < profile.total) ? 'completed_partial' : 'completed';
  }

  Map<String, dynamic> get summary {
    final blocked = state == 'waiting_for_target' || state == 'waiting_for_source' || state == 'failed';
    return {
      'execution_mode': 'continuous_queue',
      'phase': phase ?? (state == 'following' && queued.isEmpty ? 'awaiting_results' : state),
      'recognition_total': profile.total,
      'recognition_processed': processed,
      'eligible_asset_count': accepted.length,
      'planned_file_count': accepted.length,
      'copied_bytes': copied.length * 25 * 1024 * 1024,
      'file_counts': {'queued': blocked ? 0 : queued.length, 'copying': 0, 'retry_wait': 0, 'blocked': blocked ? queued.length : 0, 'copied': copied.length, 'failed': failed.length, 'stopped': stopped.length, 'skipped_conflict': 0},
      'asset_counts': {'copied': copied.length, 'failed': failed.length},
    };
  }

  List<Map<String, dynamic>> get items => [
    for (final seq in accepted)
      {
        'item_id': 'repair-item-$seq',
        'file_id': photos[seq - 1]['file_id'],
        'name': photos[seq - 1]['filename'],
        'state': copied.contains(seq)
            ? 'copied'
            : failed.contains(seq)
            ? 'failed'
            : stopped.contains(seq)
            ? 'stopped'
            : state == 'waiting_for_target' || state == 'waiting_for_source' || state == 'failed'
            ? 'blocked'
            : 'queued',
        'attempt_count': copied.contains(seq) || failed.contains(seq) ? 1 : 0,
        if (failed.contains(seq)) 'error_code': 'COPY_HASH_MISMATCH',
        'target_relative_path': 'BirdBox/${photos[seq - 1]['filename']}',
      },
  ];

  void reset() {
    state = 'created';
    phase = blocker = errorCode = errorMessage = null;
    processed = version = 0;
    cutoff = null;
    recognitionFinished = failNextWrite = false;
    accepted.clear();
    copied.clear();
    failed.clear();
    stopped.clear();
  }

  Map<String, dynamic> toJson() => {
    'state': state,
    'phase': phase,
    'blocker': blocker,
    'version': version,
    'processed': processed,
    'cutoff': cutoff,
    'recognition_finished': recognitionFinished,
    'target_media_id': targetMediaId,
    'error_code': errorCode,
    'error_message': errorMessage,
    'fail_next_write': failNextWrite,
    'accepted': accepted.toList(),
    'copied': copied.toList(),
    'failed': failed.toList(),
    'stopped': stopped.toList(),
  };

  void restore(Map stateJson) {
    state = stateJson['state'] as String;
    phase = stateJson['phase'] as String?;
    blocker = stateJson['blocker'] as String?;
    version = stateJson['version'] as int;
    processed = stateJson['processed'] as int;
    cutoff = stateJson['cutoff'] as int?;
    recognitionFinished = stateJson['recognition_finished'] == true;
    targetMediaId = stateJson['target_media_id'] as String;
    errorCode = stateJson['error_code'] as String?;
    errorMessage = stateJson['error_message'] as String?;
    failNextWrite = stateJson['fail_next_write'] == true;
    for (final entry in {'accepted': accepted, 'copied': copied, 'failed': failed, 'stopped': stopped}.entries) {
      entry.value
        ..clear()
        ..addAll((stateJson[entry.key] as List).cast<int>());
    }
  }
}
