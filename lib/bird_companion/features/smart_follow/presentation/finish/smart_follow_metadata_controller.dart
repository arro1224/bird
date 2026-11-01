import 'package:flutter/foundation.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

/// M1/M2: read facts, preview, then one explicit user-authorized submission.
class SmartFollowMetadataController extends ChangeNotifier {
  SmartFollowMetadataController({required this.repository, required this.sessionId, required this.readRecognition, this.isCurrent, DateTime Function()? now}) : now = now ?? DateTime.now, _deviceGeneration = repository.deviceGeneration;
  final SmartFollowRepository repository;
  final String sessionId;
  final Future<BirdJobStatus> Function(String) readRecognition;
  final bool Function()? isCurrent;
  final DateTime Function() now;
  final int _deviceGeneration;
  SmartFollowSession? session;
  BirdJobStatus? recognition;
  SmartFollowMetadataAvailability? availability;
  SmartFollowMetadataPreview? preview;
  SmartFollowMetadataUpdate? createdUpdate;
  String? activeUpdateId, error;
  String? get latestUpdateId => activeUpdateId ?? (repository.metadataUpdateHistory(sessionId).isEmpty ? null : repository.metadataUpdateHistory(sessionId).last);
  bool enabled = false, busy = false, partialConsent = false;
  bool _disposed = false;
  int _invalidation = 0;
  Future<void>? _working;

  bool get current => !_disposed && repository.deviceGeneration == _deviceGeneration && (isCurrent?.call() ?? true);
  bool get recognitionFinished => recognition != null && const {BirdJobState.completed, BirdJobState.failed, BirdJobState.cancelled}.contains(recognition!.state);
  bool get outcomeUnknown => repository.hasPendingMetadata(sessionId);
  bool get canPreview => current && enabled && !busy && error == null && availability?.available == true && recognition != null && activeUpdateId == null && !outcomeUnknown;
  String get actionLabel => recognitionFinished ? '更新识别信息' : '保存当前已有信息';
  String? get previewIssue {
    final value = preview;
    if (value == null) return '请先获取信息更新预览';
    if (!value.ready) return '预览尚未就绪或已失败，请重新获取';
    if (value.expiresAt == null) return '预览未提供有效期，暂不能确认更新';
    if (!now().isBefore(value.expiresAt!)) return '预览已过期，请重新获取并确认';
    if (value.targetMediaId == null || session?.targetMediaId == null || value.targetMediaId != session!.targetMediaId) return '预览目标盘与原复制任务不一致或身份未提供';
    if (CopyJobDeviceSnapshot(mediaId: value.targetMediaId, displayName: value.targetDisplayName).presentationLabel == null) return '目标盘名称未提供或不可用于确认，请重新获取预览';
    if (!value.knownCounts.containsAll(SmartFollowMetadataPreview.countKeys) || !value.partialConfirmationKnown) return '预览统计或确认要求未提供完整，暂不能确认更新';
    if (!value.hasKnownWriteMode) return '预览写入方式暂无法确认';
    if (!value.hasUpdatableItems || value.updatableFileCount == 0 || value.childJobCount == 0) return '当前没有可更新的副本';
    return null;
  }

  bool get canSubmit => canPreview && previewIssue == null && (!preview!.needsPartialConsent || partialConsent);

  void _check() {
    if (!current) throw StateError('盒子连接已变化，请重新打开原任务');
  }

  void setPartialConsent(bool value) {
    if (busy || _disposed) return;
    partialConsent = value;
    notifyListeners();
  }

  void invalidate() {
    if (_disposed) return;
    ++_invalidation;
    preview = null;
    partialConsent = false;
    error = current ? '状态可能已变化，请重新获取预览并确认' : '盒子连接已变化，请重新打开原任务';
    notifyListeners();
  }

  Future<void> refresh() => _run(() async {
    preview = null;
    partialConsent = false;
    await _facts();
  });

  Future<void> prepare() {
    final invalidation = _invalidation;
    return _run(() async {
      preview = null;
      partialConsent = false;
      await _facts();
      _check();
      if (!enabled || availability?.available != true || activeUpdateId != null || outcomeUnknown) return;
      final value = await repository.previewMetadata(sessionId);
      _check();
      if (invalidation != _invalidation) throw StateError('状态已变化，请重新获取预览并确认');
      preview = value;
    });
  }

  Future<void> confirm() {
    if (busy) return _working ?? Future.value();
    if (!canSubmit) return Future.value();
    final shown = preview!;
    final consent = partialConsent;
    final finished = recognitionFinished;
    final invalidation = _invalidation;
    return _run(() async {
      await _facts();
      _check();
      if (!enabled || availability?.available != true || activeUpdateId != null || outcomeUnknown) return;
      if (finished != recognitionFinished) {
        preview = null;
        partialConsent = false;
        throw StateError('识别阶段已变化，请重新获取预览并确认');
      }
      final fresh = await repository.previewDetail(shown.previewId);
      _check();
      if (invalidation != _invalidation) throw StateError('状态已变化，请重新获取预览并确认');
      if (!_samePreview(shown, fresh)) {
        preview = fresh;
        partialConsent = false;
        throw StateError('预览内容已变化，请核对后重新确认');
      }
      if (previewIssue != null) {
        partialConsent = false;
        throw StateError(previewIssue!);
      }
      if (shown.needsPartialConsent && !consent) throw StateError('请先明确确认部分更新');
      createdUpdate = await repository.createMetadataUpdate(sessionId, shown, confirmPartial: shown.needsPartialConsent && consent);
      _check();
      activeUpdateId = createdUpdate!.updateId;
      preview = null;
      partialConsent = false;
    });
  }

  bool _samePreview(SmartFollowMetadataPreview a, SmartFollowMetadataPreview b) =>
      a.previewId == b.previewId &&
      a.ready == b.ready &&
      a.previewToken == b.previewToken &&
      a.targetMediaId == b.targetMediaId &&
      a.targetDisplayName == b.targetDisplayName &&
      a.expiresAt == b.expiresAt &&
      a.writeMode == b.writeMode &&
      a.requiresPartialConfirmation == b.requiresPartialConfirmation &&
      a.partialConfirmationKnown == b.partialConfirmationKnown &&
      SmartFollowMetadataPreview.countKeys.every((key) => a.count(key) == b.count(key)) &&
      listEquals(a.blockedReasons, b.blockedReasons);

  Future<void> _facts() async {
    _check();
    enabled = false;
    availability = null;
    recognition = null;
    activeUpdateId = null;
    final caps = await repository.capabilities(forceRefresh: true);
    _check();
    enabled = caps.canUpdateMetadata;
    if (!enabled) return;
    final value = await repository.refresh(sessionId);
    _check();
    session = value;
    final job = await readRecognition(value.recognitionJobId);
    _check();
    if (job.id != value.recognitionJobId || job.type != BirdJobType.analysis || job.state == BirdJobState.unknown || (job.smartFollowSessionId != null && job.smartFollowSessionId != sessionId)) throw StateError('无法确认本轮识别状态，请刷新重试');
    recognition = job;
    final available = await repository.metadataAvailability(sessionId);
    _check();
    if (value.activeMetadataUpdateId != null && available.activeUpdateId != null && value.activeMetadataUpdateId != available.activeUpdateId) throw StateError('信息更新任务关联不一致，请刷新重试');
    availability = available;
    activeUpdateId = available.activeUpdateId ?? value.activeMetadataUpdateId ?? createdUpdate?.updateId;
    if (activeUpdateId != null) {
      final original = await repository.metadataUpdate(activeUpdateId!);
      _check();
      await repository.rememberMetadataUpdate(sessionId, original.updateId);
      _check();
      if (outcomeUnknown) {
        await repository.resolvePendingMetadata(sessionId);
        _check();
      }
      if (original.isTerminal && original.childrenSettled) {
        activeUpdateId = null;
        createdUpdate = null;
      }
    }
  }

  Future<void> _run(Future<void> Function() action) {
    if (_disposed) return Future.value();
    if (busy) return _working ?? Future.value();
    busy = true;
    error = null;
    notifyListeners();
    final request = () async {
      try {
        await action();
      } catch (failure) {
        if (!_disposed) {
          error = !current
              ? '盒子连接已变化，请重新打开原任务'
              : outcomeUnknown
              ? '上次信息更新结果待确认，请查询原任务；不会重新创建'
              : failure is StateError
              ? failure.message.toString()
              : failure is ApiException && failure.code == 'COPY_PREVIEW_EXPIRED'
              ? '盒子上的预览已过期，请重新获取并确认'
              : failure is ApiException && failure.code == 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED'
              ? '可更新范围已变化，需要重新预览并明确确认部分更新'
              : failure is ApiException && failure.code == 'SMART_FOLLOW_METADATA_NOT_AVAILABLE'
              ? '当前信息不可更新，请重新获取预览'
              : '暂时无法确认信息更新，请刷新重试';
        }
      } finally {
        if (!_disposed) {
          busy = false;
          notifyListeners();
        }
      }
    }();
    _working = request;
    return request.whenComplete(() {
      if (identical(_working, request)) _working = null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
