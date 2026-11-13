import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/features/copy/domain/copy_device_policy.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:flutter/foundation.dart';

class SmartFollowConfigurationSnapshot {
  SmartFollowConfigurationSnapshot({required this.entry, required this.binding, required this.preferences, required this.copyCapabilities, required List<StorageDeviceSummary> devices}) : devices = List.unmodifiable(devices);

  final SmartFollowEntryDecision entry;
  final SourceBinding binding;
  final CopyPreferences preferences;
  final CopyCapabilities copyCapabilities;
  final List<StorageDeviceSummary> devices;
}

/// Only reads existing APIs. No preview of future files or task POST is made.
class SmartFollowConfigurationReader {
  const SmartFollowConfigurationReader({required this.readSnapshot, required this.isCurrent, required this.contextKey, this.batchId, this.changes});
  final Future<SmartFollowConfigurationSnapshot> Function() readSnapshot;
  final bool Function() isCurrent;
  final String contextKey;
  final String? batchId;
  final Stream<void>? changes;
}

/// Frozen local confirmation for SF-B3. Binding/preferences are local context,
/// not new wire fields: the request uses the existing SmartFollowStartRequest.
class SmartFollowConfiguredIntent {
  const SmartFollowConfiguredIntent({
    required this.request,
    required this.contextKey,
    required this.batchId,
    required this.recognitionJobId,
    required this.sourceMediaId,
    required this.sourceBindingToken,
    required this.sourceBindingExpiresAt,
    required this.preferencesVersion,
    required this.targetName,
    required this.targetIdentityConfidence,
    required this.targetCapacityBytes,
    required this.targetFreeBytes,
  });

  final SmartFollowStartRequest request;
  final String contextKey;
  final String? batchId, recognitionJobId;
  final String sourceMediaId, sourceBindingToken;
  final DateTime sourceBindingExpiresAt;
  final int preferencesVersion;
  final String targetName, targetIdentityConfidence;
  final int targetCapacityBytes, targetFreeBytes;

  SmartFollowConfiguredIntent forBatch(String id) => SmartFollowConfiguredIntent.fromLocalJson({...toLocalJson(), 'batch': id});

  Map<String, dynamic> toLocalJson() => {
    'request': request.toJson(),
    'context': contextKey,
    'batch': batchId,
    'job': recognitionJobId,
    'source': sourceMediaId,
    'binding': sourceBindingToken,
    'expires': sourceBindingExpiresAt.toUtc().toIso8601String(),
    'preferences': preferencesVersion,
    'target_name': targetName,
    'identity': targetIdentityConfidence,
    'capacity': targetCapacityBytes,
    'free': targetFreeBytes,
  };

  factory SmartFollowConfiguredIntent.fromLocalJson(Map<String, dynamic> json) {
    final request = Map<String, dynamic>.from(json['request'] as Map);
    final continuous = request.containsKey('review_export_enabled');
    final export = request['review_export'] is Map ? Map<String, dynamic>.from(request['review_export'] as Map) : const <String, dynamic>{};
    return SmartFollowConfiguredIntent(
      request: SmartFollowStartRequest(
        targetMediaId: request['target_media_id'] as String,
        eligibilityMode: request['eligibility_mode'] as String,
        pairPolicy: request['pair_policy'] as String,
        conflictStrategy: request['conflict_strategy'] as String,
        continuousQueue: continuous,
        reviewExportEnabled: continuous ? request['review_export_enabled'] as bool : export['enabled'] as bool,
        preferEmbedded: export['prefer_embedded'] as bool? ?? true,
      ),
      contextKey: json['context'] as String,
      batchId: json['batch'] as String?,
      recognitionJobId: json['job'] as String?,
      sourceMediaId: json['source'] as String,
      sourceBindingToken: json['binding'] as String,
      sourceBindingExpiresAt: DateTime.parse(json['expires'] as String),
      preferencesVersion: json['preferences'] as int,
      targetName: json['target_name'] as String,
      targetIdentityConfidence: json['identity'] as String,
      targetCapacityBytes: json['capacity'] as int,
      targetFreeBytes: json['free'] as int,
    );
  }
}

class SmartFollowConfigurationController extends ChangeNotifier {
  SmartFollowConfigurationController(this.reader, {DateTime Function()? now, this.expectedRecognitionJobId, this.expectedRecognitionPhase}) : now = now ?? DateTime.now;
  final SmartFollowConfigurationReader reader;
  final String? expectedRecognitionJobId;
  final RecognitionEntryPhase? expectedRecognitionPhase;
  final DateTime Function() now;
  SmartFollowConfigurationSnapshot? snapshot;
  String? targetMediaId;
  PairPolicy pairPolicy = PairPolicy.rawOnly;
  ConflictStrategy? conflictStrategy;
  bool reviewExportEnabled = false;
  bool loading = false, confirming = false;
  Object? error;
  String? notice;
  SmartFollowConfiguredIntent? confirmed;
  bool _disposed = false, _policyChosen = false;
  int _generation = 0, _revision = 0;
  Timer? _expiry;
  bool get canExportInformation => snapshot?.copyCapabilities.reviewExportReady == true && snapshot?.entry.capabilities.copy.continuousQueueAvailable != true;

  StorageDeviceSummary? get target => snapshot?.devices.where((device) => device.mediaId == targetMediaId).firstOrNull;
  List<StorageDeviceSummary> get candidates => snapshot?.devices.where((device) => CopyDevicePolicy.isTargetCandidate(device, snapshot!.binding.sourceMediaId)).toList(growable: false) ?? const [];

  String? targetBlockReason(StorageDeviceSummary device) {
    final policy = CopyDevicePolicy.targetDisabledReason(device, sourceMediaId: snapshot?.binding.sourceMediaId);
    if (policy != null) return policy;
    if (!const {'stable_uuid', 'degraded'}.contains(device.identityConfidence)) return '设备身份尚无法确认，请重新检测。';
    if (device.capacityBytes <= 0 || device.freeBytes < 0 || device.freeBytes > device.capacityBytes) return '设备容量尚无法确认，请重新检测。';
    if (device.freeBytes == 0) return '目标设备空间不足，请释放空间或更换设备。';
    return null;
  }

  String? get blockReason {
    if (!reader.isCurrent()) return '盒子连接或复制上下文已变化，请重新进入配置。';
    if (loading) return '正在重新检测设备，请稍候。';
    final data = snapshot;
    if (error != null || data == null) return '设备状态暂时无法确认，请检查连接后重新检测。';
    if (!data.entry.canChooseFollow) return '本轮识别状态或跟随能力已变化，请返回重新选择。';
    if (expectedRecognitionPhase != null && data.entry.phase != expectedRecognitionPhase) return '识别阶段已变化，请返回重新选择复制方式。';
    if (expectedRecognitionJobId != null && data.entry.job?.id != expectedRecognitionJobId) return '识别任务已变化，请返回确认要跟随的轮次。';
    if (data.entry.capabilities.copy.contractVersion != SmartFollowContract.version || data.entry.capabilities.copy.eligibilityMode != SmartFollowContract.eligibilityMode) return '盒子跟随协议或识别范围不兼容，暂不能确认。';
    if (data.entry.capabilities.copy.continuousQueueAvailable && data.entry.capabilities.copy.continuousContractVersion != SmartFollowContract.continuousVersion) return '盒子持续复制协议版本不兼容，请更新 App 或联系维护人员。';
    if (!data.copyCapabilities.copyReady || data.copyCapabilities.revision != '1.0-rc3') return '盒子复制能力尚未就绪，请重新检测。';
    final binding = data.binding;
    if (binding.batchId != null && reader.batchId != null && binding.batchId != reader.batchId) return '源卡绑定不属于本批次，请重新检测。';
    if (!binding.verifiedReadOnly || binding.token.trim().isEmpty) return '相机卡只读绑定尚未确认，请重新检测。';
    if (!now().isBefore(binding.expiresAt)) return '源卡绑定已过期，请重新检测后确认。';
    final source = data.devices.where((device) => device.mediaId == binding.sourceMediaId).firstOrNull;
    if (source == null || !source.online || !source.canBeSource) return '源卡已断开或不可读取，请重新检测。';
    if (targetMediaId == null) return '请选择目标设备。';
    final selected = target;
    if (selected == null) return '原目标设备已断开，请重新检测或明确选择其他设备。';
    final reason = targetBlockReason(selected);
    if (reason != null) return reason;
    if (conflictStrategy == null) return '请选择同名文件处理方式。';
    return null;
  }

  void _clearConfirmation() {
    confirmed = null;
  }

  void invalidate() {
    if (_disposed) return;
    ++_generation;
    ++_revision;
    _expiry?.cancel();
    loading = false;
    _clearConfirmation();
    error = StateError('configuration invalidated');
    notice = '配置已失效，请重新检测设备后确认。';
    notifyListeners();
  }

  Future<bool> refresh() async {
    if (_disposed) return false;
    final generation = ++_generation;
    _expiry?.cancel();
    _clearConfirmation();
    loading = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      if (!reader.isCurrent()) throw StateError('device changed');
      final next = await reader.readSnapshot();
      if (_disposed || generation != _generation) return false;
      if (!reader.isCurrent()) throw StateError('device changed');
      if (next.devices.map((device) => device.mediaId).toSet().length != next.devices.length) throw StateError('ambiguous device identities');
      snapshot = next;
      if (!_policyChosen) pairPolicy = next.preferences.pairPolicy;
      if (!canExportInformation) reviewExportEnabled = false;
      final delay = next.binding.expiresAt.difference(now());
      _expiry = Timer(delay.isNegative ? Duration.zero : delay, () {
        if (_disposed) return;
        _clearConfirmation();
        notice = '源卡绑定已过期，请重新检测后确认。';
        notifyListeners();
      });
      return true;
    } catch (caught) {
      if (!_disposed && generation == _generation) error = caught;
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void selectTarget(String id) {
    final selected = snapshot?.devices.where((device) => device.mediaId == id).firstOrNull;
    if (_disposed || loading || selected == null || targetBlockReason(selected) != null) return;
    targetMediaId = id;
    _changed();
  }

  void selectPairPolicy(PairPolicy value) {
    if (_disposed || loading) return;
    _policyChosen = true;
    pairPolicy = value;
    _changed();
  }

  void selectConflict(ConflictStrategy value) {
    if (_disposed || loading) return;
    conflictStrategy = value;
    _changed();
  }

  void setReviewExport(bool enabled) {
    if (_disposed || loading || (enabled && !canExportInformation)) return;
    reviewExportEnabled = enabled;
    _changed();
  }

  void _changed() {
    ++_revision;
    _clearConfirmation();
    notice = null;
    notifyListeners();
  }

  String get _signature => jsonEncode([
    reader.contextKey,
    reader.batchId,
    snapshot?.entry.job?.id,
    snapshot?.entry.phase.name,
    snapshot?.binding.sourceMediaId,
    snapshot?.binding.batchId,
    snapshot?.binding.verifiedReadOnly,
    snapshot?.preferences.version,
    targetMediaId,
    target?.identityConfidence,
    target?.capacityBytes,
    target?.freeBytes,
    target?.filesystem,
    target?.presentationName,
    pairPolicy.wireValue,
    conflictStrategy?.wireValue,
    reviewExportEnabled,
    snapshot?.entry.capabilities.copy.continuousQueueAvailable,
  ]);

  Future<bool> confirm() async {
    if (_disposed || confirming || blockReason != null) return false;
    confirming = true;
    final revision = _revision, signature = _signature;
    try {
      if (!await refresh() || _disposed || revision != _revision || blockReason != null) return false;
      if (signature != _signature) {
        notice = '设备或策略已变化，请核对更新后的配置，再次确认。';
        return false;
      }
      final data = snapshot!, selected = target!;
      confirmed = SmartFollowConfiguredIntent(
        request: SmartFollowStartRequest(
          targetMediaId: selected.mediaId,
          reviewExportEnabled: reviewExportEnabled,
          continuousQueue: data.entry.capabilities.copy.continuousQueueAvailable,
          eligibilityMode: SmartFollowContract.eligibilityMode,
          pairPolicy: pairPolicy.wireValue,
          conflictStrategy: conflictStrategy!.wireValue,
        ),
        contextKey: reader.contextKey,
        batchId: reader.batchId,
        recognitionJobId: data.entry.job?.id,
        sourceMediaId: data.binding.sourceMediaId,
        sourceBindingToken: data.binding.token,
        sourceBindingExpiresAt: data.binding.expiresAt,
        preferencesVersion: data.preferences.version,
        targetName: selected.presentationName,
        targetIdentityConfidence: selected.identityConfidence,
        targetCapacityBytes: selected.capacityBytes,
        targetFreeBytes: selected.freeBytes,
      );
      return true;
    } finally {
      confirming = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _expiry?.cancel();
    super.dispose();
  }
}
