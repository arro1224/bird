import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

/// 内存版 SmartFollow 后端（分工任务书 F6）。
///
/// 设计原则：**不用定时器**，状态由测试/演示代码显式推进
/// （`commitPhoto` → `finishRecognition` → `completeChildJobs`），因此 widget
/// 测试可以 `pump()` 精确断言，不会因为真实时钟抖动而 flaky。
///
/// 它只模拟契约里**已经冻结**的语义（九状态、五动作、批封、子任务、信息可
/// 更新），不模拟盒端的文件复制、校验和介质拔插细节——那些用 RC3 的
/// `MockCopyRepository`。
class FakeSmartFollowBackend implements SmartFollowGateway {
  FakeSmartFollowBackend({
    this.batchSize = 8,
    this.sessionId = 'sf_fake',
    this.recognitionJobId = 'rec_fake',
    this.eligibilityAvailable = true,
    this.metadataSupported = true,
  });

  final int batchSize;
  final String sessionId;
  final String recognitionJobId;
  final bool eligibilityAvailable;
  final bool metadataSupported;

  SmartFollowState _state = SmartFollowState.created;
  int _version = 1;
  int _eventSeq = 0;
  int _recognized = 0;
  int _eligible = 0;
  int _sealed = 0;
  int _copiedAssets = 0;
  int _copiedFiles = 0;
  int _failedAssets = 0;
  int? _cutoff;
  bool _started = false;
  bool _metadataAvailable = false;
  String? _activeUpdateId;
  String? _errorCode;
  String? _errorMessage;
  int _childSeq = 0;
  final List<_FakeChild> _children = [];
  String _metadataUpdateState = 'unknown';
  int _updatedFiles = 0;
  int _blockedFiles = 0;
  bool _metadataPartial = false;
  bool metadataBlocked = false;

  int startCalls = 0;
  int sessionCalls = 0;
  int actCalls = 0;
  int childJobCalls = 0;
  int createMetadataCalls = 0;

  int get pendingCount => _eligible - _sealed;
  int get recognizedCount => _recognized;
  int get eligibleCount => _eligible;
  int get copiedAssetCount => _copiedAssets;
  int get copiedFileCount => _copiedFiles;
  SmartFollowState get state => _state;
  List<SmartFollowChildJob> get children => List.unmodifiable(_children.map((child) => child.job));

  /// 当前会话快照（测试断言用）。
  SmartFollowSession get current => _snapshot();
  int get version => _version;

  // ---- 驱动接口（测试/演示用）----

  void start() {
    _started = true;
    if (_state == SmartFollowState.created) _bump(SmartFollowState.following);
  }

  /// 一张照片的识别结果 committed。`eligible=false` 模拟 medium/unknown/reject。
  void commitPhoto({bool eligible = true, int files = 1}) {
    _recognized++;
    _eventSeq++;
    if (eligible) {
      _eligible++;
      _sealFilledBatches();
    }
    _version++;
  }

  /// 识别进入终态：立即封最后一批（联合 §3/§4）。
  void finishRecognition() {
    if (_state.isFinished) return;
    if (_eligible > _sealed) _seal(_eligible - _sealed);
    _bump(SmartFollowState.draining);
  }

  /// 子任务全部收敛：把已封批的照片记为已复制；队列空了且子任务全到终态才完成
  /// （联合 §6.3 的完成三条件）。
  void completeChildJobs() {
    for (final child in _children) {
      _completeChild(child);
    }
    _settle();
  }

  /// 只收敛一个子任务，用来构造"排队中/部分完成"的现场。
  void completeOneChildJob() {
    for (final child in _children) {
      if (!child.done) {
        _completeChild(child);
        break;
      }
    }
    _settle();
  }

  /// 标记目标盘上有副本被外部改过：信息更新将要求"部分确认"。
  void blockMetadataUpdate({int files = 1}) {
    metadataBlocked = true;
    _blockedFiles = files;
  }

  void _completeChild(_FakeChild child) {
    if (child.done) return;
    child.done = true;
    _copiedAssets += child.assets;
    _copiedFiles += child.assets;
  }

  void _settle() {
    final allDone = _children.every((child) => child.done);
    if (_state == SmartFollowState.draining && pendingCount == 0 && allDone) {
      _metadataAvailable = metadataSupported;
      _bump(_failedAssets > 0 ? SmartFollowState.completedPartial : SmartFollowState.completed);
    } else {
      _version++;
    }
  }

  /// 目标盘拔出 / 插错盘：状态切到等待，计数与队列不动（联合 §5、App §7）。
  void waitForTarget({String code = 'SMART_FOLLOW_TARGET_UNAVAILABLE'}) {
    _errorCode = code;
    _errorMessage = code == 'SMART_FOLLOW_TARGET_IDENTITY_CHANGED' ? '插入的目标盘与任务记录不一致' : '目标盘已拔出';
    _bump(SmartFollowState.waitingForTarget);
  }

  void recover({SmartFollowState state = SmartFollowState.following}) {
    _errorCode = null;
    _errorMessage = null;
    _bump(state);
  }

  void fail(String code, String message) {
    _errorCode = code;
    _errorMessage = message;
    _bump(SmartFollowState.failed);
  }

  /// 识别异常但用户选择"完成当前结果"（联合 §5.3）：排空后 completed_partial。
  void finishCurrentResults() {
    _cutoff = _eventSeq;
    if (_eligible > _sealed) _seal(_eligible - _sealed);
    _bump(SmartFollowState.draining);
  }

  void completeMetadataUpdate({bool partial = false, int updatedFiles = 0, int blockedFiles = 0}) {
    _metadataUpdateState = partial ? 'completed_partial' : 'completed';
    _updatedFiles = updatedFiles == 0 ? _copiedFiles : updatedFiles;
    _blockedFiles = blockedFiles;
    _metadataPartial = partial;
    _activeUpdateId = null;
    _version++;
  }

  // ---- SmartFollowGateway ----

  @override
  Future<SmartFollowCapabilities> capabilities() async => SmartFollowCapabilities.fromJson({
    'incremental_recognition_results': {'available': true, 'schema_version': 'birdbox.pipeline_result.v1'},
    'smart_follow_copy': {
      'available': eligibilityAvailable,
      'contract_version': SmartFollowContract.version,
      'eligibility_mode': SmartFollowContract.eligibilityMode,
      'default_batch_size': batchSize,
      'default_collect_window_ms': 2000,
      'batch_size_range': [1, 32],
      'collect_window_ms_range': [250, 10000],
    },
    'smart_follow_metadata_update': {'available': metadataSupported},
  });

  @override
  Future<SmartFollowSession> startOnRecognitionJob(
    String recognitionJobId,
    SmartFollowStartRequest request, {
    String? idempotencyKey,
  }) async {
    startCalls++;
    start();
    return session(sessionId);
  }

  /// 已被占用的识别任务：模拟后端返回 `SMART_FOLLOW_ALREADY_ACTIVE`。
  Future<SmartFollowSession> startRejectedAsActive() async {
    throw const ApiException(message: 'already active', code: 'SMART_FOLLOW_ALREADY_ACTIVE', statusCode: 409);
  }

  @override
  Future<SmartFollowSession> session(String sessionIdValue) async {
    sessionCalls++;
    return _snapshot();
  }

  @override
  Future<SmartFollowChildJobPage> childJobs(String sessionIdValue, {String? cursor, int pageSize = 50}) async {
    childJobCalls++;
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + pageSize).clamp(0, _children.length);
    final items = _children.sublist(start, end).map((child) => child.job).toList(growable: false);
    return SmartFollowChildJobPage(
      items: items,
      hasMore: end < _children.length,
      nextCursor: end < _children.length ? '$end' : null,
    );
  }

  @override
  Future<SmartFollowSession?> act(
    String sessionIdValue,
    SmartFollowAction action, {
    required int expectedStateVersion,
    String? idempotencyKey,
  }) async {
    actCalls++;
    if (expectedStateVersion != _version) {
      throw const ApiException(message: 'state version conflict', code: 'SMART_FOLLOW_STATE_VERSION_CONFLICT', statusCode: 409);
    }
    if (!_actions.contains(action)) {
      throw const ApiException(message: 'action not allowed', code: 'SMART_FOLLOW_ACTION_NOT_ALLOWED', statusCode: 409);
    }
    switch (action) {
      case SmartFollowAction.pause:
        _bump(SmartFollowState.paused);
      case SmartFollowAction.resume:
        _bump(SmartFollowState.following);
      case SmartFollowAction.finishCurrentResults:
        finishCurrentResults();
      case SmartFollowAction.stopFollowing:
        _cutoff = _eventSeq;
        _sealed = _eligible; // 未分配的待复制项标记为 not_copied_stopped，不再新建
        _bump(SmartFollowState.draining);
      case SmartFollowAction.retry:
        _failedAssets = 0;
        _version++;
    }
    return _snapshot();
  }

  @override
  Future<String?> sessionIdForRecognitionJob(String jobId) async => _started && jobId.trim() == recognitionJobId ? sessionId : null;

  @override
  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionIdValue) async => SmartFollowMetadataAvailability(
    available: _metadataAvailable,
    activeUpdateId: _activeUpdateId,
    updatableAssetCount: _metadataAvailable ? _copiedAssets : 0,
    blockedAssetCount: _blockedFiles,
  );

  @override
  Future<SmartFollowMetadataPreview> previewMetadata(String sessionIdValue, {Map<String, dynamic>? data, String? idempotencyKey}) async {
    _metadataPartial = metadataBlocked;
    return SmartFollowMetadataPreview.fromJson({
      'preview_id': 'pv_fake',
      'preview_token': 'tok_fake',
      'expires_at': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
      'target_media_id': _targetMediaId,
      'target_display_name': '测试目标盘',
      'child_job_count': _children.length,
      'updatable_asset_count': _copiedAssets,
      'updatable_file_count': _copiedFiles,
      'blocked_count': _metadataPartial ? 1 : 0,
      'requires_partial_confirmation': _metadataPartial,
      'write_mode': 'safe_embed_first',
      'blocked_reasons': _metadataPartial ? const ['有副本已被外部修改'] : const <String>[],
    });
  }

  @override
  Future<SmartFollowMetadataPreview> previewDetail(String previewId) => previewMetadata(sessionId);

  @override
  Future<SmartFollowMetadataUpdate> createMetadataUpdate(
    String sessionIdValue, {
    required Map<String, dynamic> data,
    String? idempotencyKey,
  }) async {
    createMetadataCalls++;
    if (_metadataPartial && data['confirm_partial'] != true) {
      throw const ApiException(message: 'partial confirmation required', code: 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED', statusCode: 409);
    }
    _metadataUpdateState = 'queued';
    _activeUpdateId = 'mu_fake';
    _metadataAvailable = false;
    _version++;
    return _update();
  }

  @override
  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId) async => _update();

  // ---- 内部 ----

  static const _targetMediaId = 'media_usb_fake';

  void _bump(SmartFollowState next) {
    _state = next;
    _version++;
  }

  List<SmartFollowAction> get _actions => switch (_state.wire) {
    'following' => const [SmartFollowAction.pause, SmartFollowAction.finishCurrentResults, SmartFollowAction.stopFollowing],
    'paused' => const [SmartFollowAction.resume, SmartFollowAction.finishCurrentResults, SmartFollowAction.stopFollowing],
    'waiting_for_target' || 'waiting_for_source' => const [SmartFollowAction.pause, SmartFollowAction.stopFollowing],
    _ => const <SmartFollowAction>[],
  };

  void _sealFilledBatches() {
    while (_eligible - _sealed >= batchSize) {
      _seal(batchSize);
    }
  }

  void _seal(int assets) {
    _sealed += assets;
    _childSeq++;
    _children.add(
      _FakeChild(
        SmartFollowChildJob(
          copyJobId: 'cj_fake_$_childSeq',
          index: _childSeq,
          state: CopyJobState.running,
          assetCount: assets,
          fileCount: assets,
          totalBytes: assets * 1024,
          copiedFileCount: 0,
          skippedFileCount: 0,
          failedFileCount: 0,
          createdAt: DateTime.now(),
        ),
        assets: assets,
      ),
    );
  }

  SmartFollowSession _snapshot() => SmartFollowSession.fromJson({
    'session_id': sessionId,
    'recognition_job_id': recognitionJobId,
    'state': _state.wire,
    'state_version': _version,
    'eligibility_mode': SmartFollowContract.eligibilityMode,
    'target_media_id': _targetMediaId,
    'batch_size': batchSize,
    'collect_window_ms': 2000,
    'last_consumed_event_seq': _eventSeq,
    'cutoff_event_seq': _cutoff,
    'recognized_count': _recognized,
    'eligible_count': _eligible,
    'pending_count': pendingCount,
    'assigned_count': _sealed,
    'copied_asset_count': _copiedAssets,
    'copied_file_count': _copiedFiles,
    'failed_asset_count': _failedAssets,
    'child_job_count': _children.length,
    'metadata_update_available': _metadataAvailable,
    'active_metadata_update_id': _activeUpdateId,
    'allowed_actions': _actions.map((action) => action.wire).toList(),
    'error_code': _errorCode,
    'error_message': _errorMessage,
  });

  SmartFollowMetadataUpdate _update() => SmartFollowMetadataUpdate.fromJson({
    'update_id': 'mu_fake',
    'state': _metadataUpdateState,
    'child_job_count': _children.length,
    'updated_file_count': _updatedFiles,
    'blocked_count': _blockedFiles,
    'child_jobs': [
      {'metadata_update_id': 'm_fake_1', 'copy_job_id': _children.isEmpty ? null : _children.first.job.copyJobId, 'state': _metadataUpdateState, 'updated_files': _updatedFiles},
    ],
  });
}

class _FakeChild {
  _FakeChild(this.job, {required this.assets});

  final SmartFollowChildJob job;
  final int assets;
  bool done = false;
}
