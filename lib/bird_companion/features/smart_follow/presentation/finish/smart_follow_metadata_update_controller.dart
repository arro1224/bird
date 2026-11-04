import 'package:flutter/foundation.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

String metadataUpdateStateLabel(String state) => switch (state.trim()) {
  'queued' => '等待更新',
  'running' => '正在更新',
  'waiting_for_target' => '等待原目标盘或处理写入问题',
  'completed' => '已完成',
  'completed_partial' => '部分完成',
  'failed' => '更新失败',
  'cancelled' => '已取消',
  _ => '状态待确认',
};

class SmartFollowMetadataUpdateReport {
  SmartFollowMetadataUpdateReport(this.update) {
    final unique = <String, SmartFollowMetadataChildUpdate>{};
    for (final child in update.childUpdates) {
      final previous = unique[child.metadataUpdateId];
      if (previous != null &&
          (previous.copyJobId != child.copyJobId ||
              previous.state != child.state ||
              previous.updatedFileCount != child.updatedFileCount ||
              previous.failedFileCount != child.failedFileCount ||
              !setEquals(previous.knownCounts, child.knownCounts) ||
              previous.errorCode != child.errorCode ||
              previous.errorMessage != child.errorMessage)) {
        issues.add('重复子任务的结果不一致，报告待核对');
      }
      unique[child.metadataUpdateId] = child;
    }
    children = List.unmodifiable(unique.values);
    if (!update.childrenProvided || update.count('child_job_count') != children.length) issues.add('子任务列表未提供完整或数量不符，报告待补齐');
    if (update.isTerminal && children.any((child) => !child.isTerminal)) issues.add('仍有子任务未结束，不能作为完整最终报告');
    if (children.every((child) => child.count('updated_file_count') != null) && update.count('updated_file_count') != null && children.fold<int>(0, (sum, child) => sum + child.updatedFileCount) != update.updatedFileCount) {
      issues.add('父子已更新文件数不一致，报告待核对');
    }
    if (children.isEmpty && ((update.count('updated_asset_count') ?? 0) > 0 || (update.count('updated_file_count') ?? 0) > 0)) issues.add('没有子任务却返回非零更新结果，报告待核对');
  }
  final SmartFollowMetadataUpdate update;
  late final List<SmartFollowMetadataChildUpdate> children;
  final List<String> issues = [];
  bool get complete =>
      update.isTerminal &&
      issues.isEmpty &&
      update.knownCounts.containsAll(SmartFollowMetadataUpdate.countAliases.keys) &&
      children.every((c) => c.copyJobId != null && c.knownCounts.containsAll(SmartFollowMetadataChildUpdate.countAliases.keys));
  bool get partial =>
      update.state.trim() == 'completed_partial' ||
      (update.count('failed_count') ?? 0) > 0 ||
      (update.count('blocked_count') ?? 0) > 0 ||
      children.any((c) => c.state.trim() == 'failed' || c.state.trim() == 'completed_partial' || c.state.trim() == 'cancelled' || (c.count('failed_file_count') ?? 0) > 0);
  String get title {
    final state = update.state.trim();
    if (!update.isTerminal) return metadataUpdateStateLabel(state);
    if (state == 'failed') return '识别信息更新失败';
    if (state == 'cancelled') return '识别信息更新已取消';
    if (partial) return '识别信息部分更新';
    return complete ? '识别信息更新完成' : '更新任务已结束，报告待补齐';
  }
}

/// M3 reads one fixed parent ID. A newer update never replaces this report.
class SmartFollowMetadataUpdateController extends ChangeNotifier {
  SmartFollowMetadataUpdateController({required this.repository, required this.sessionId, this.updateId, this.isCurrent}) : _deviceGeneration = repository.deviceGeneration;
  final SmartFollowRepository repository;
  final String sessionId;
  String? updateId;
  final bool Function()? isCurrent;
  final int _deviceGeneration;
  SmartFollowSession? session;
  SmartFollowMetadataUpdateReport? report;
  SmartFollowMetadataAvailability? availability;
  String? error, availabilityError;
  bool busy = false, metadataEnabled = false;
  bool _disposed = false;
  Future<void>? _loading;
  bool get current => !_disposed && repository.deviceGeneration == _deviceGeneration && (isCurrent?.call() ?? true);
  String? get otherActiveId {
    final id = availability?.activeUpdateId ?? session?.activeMetadataUpdateId;
    return id != null && id != updateId ? id : null;
  }

  bool get canPreview => current && !busy && error == null && availabilityError == null && report?.update.isTerminal == true && report!.update.childrenSettled && metadataEnabled && availability?.available == true && otherActiveId == null;
  List<String> get history => repository.metadataUpdateHistory(sessionId);
  void _check() {
    if (!current) throw StateError('盒子连接已变化');
  }

  Future<void> refresh() => _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    if (_disposed) return;
    busy = true;
    error = null;
    availabilityError = null;
    availability = null;
    metadataEnabled = false;
    notifyListeners();
    try {
      _check();
      final value = await repository.refresh(sessionId);
      _check();
      session = value;
      var active = value.activeMetadataUpdateId;
      final recorded = repository.metadataUpdateHistory(sessionId);
      // Discover a missing identity only through existing session/availability.
      if ((updateId == null && active == null && recorded.isEmpty) || (updateId != null && active != updateId && !recorded.contains(updateId))) {
        final available = await repository.metadataAvailability(sessionId);
        _check();
        active = available.activeUpdateId ?? active;
      }
      final id = updateId ?? active ?? (recorded.isEmpty ? null : recorded.last);
      if (id == null || (id != active && !recorded.contains(id))) throw StateError('无法确认原信息更新任务与此会话的关联');
      final update = await repository.metadataUpdate(id);
      _check();
      await repository.rememberMetadataUpdate(sessionId, id);
      _check();
      updateId = id;
      report = SmartFollowMetadataUpdateReport(update);
      if (update.isTerminal) {
        try {
          final caps = await repository.capabilities(forceRefresh: true);
          _check();
          metadataEnabled = caps.canUpdateMetadata;
          if (metadataEnabled) {
            availability = await repository.metadataAvailability(sessionId);
            _check();
          }
        } catch (_) {
          _check();
          availabilityError = '报告已取得，但暂时无法核对是否有更新信息，请重新读取';
        }
      }
    } catch (_) {
      if (!_disposed) error = current ? '原任务或报告暂不可用，请重新读取；不会重新提交' : '盒子连接已变化，请重新打开原任务';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
