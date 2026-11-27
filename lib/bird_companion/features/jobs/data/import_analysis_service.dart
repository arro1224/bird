import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:aves/bird_companion/features/jobs/domain/import_analysis_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';

class ImportAnalysisPending implements Exception {
  const ImportAnalysisPending({this.cancel = false});
  final bool cancel;
  @override
  String toString() => cancel ? '取消待确认，请查询原任务；不会将离线操作显示为已取消。' : '上次开始结果待确认，请查询并恢复原请求；不要新建批次或更换参数。';
}

/// Durable user intent and box ownership, never a phone-side workflow worker.
/// Both POST bodies/keys survive an unknown result. GET is always authoritative
/// after replay; a missing local analysis is never permission to create one.
class ImportAnalysisService {
  ImportAnalysisService({required this.repository, required this.batches, required this.cache, required this.readCapabilities, required this.deviceId, required this.contextKey, String Function()? newKey})
    : newKey = newKey ?? SecureRequestIdFactory().create;
  final ImportWorkflowRepository repository;
  final BatchRepository batches;
  final LocalCache cache;
  final Future<Map<String, dynamic>> Function() readCapabilities;
  final String? Function() deviceId, contextKey;
  final String Function() newKey;
  final Map<String, Future<ImportStartResult>> _starting = {}, _reading = {};
  final Map<String, String> _startBodies = {};
  final Map<String, ImportAnalysisCapability> _capabilities = {};
  Future<void> _writes = Future.value();
  late final String _defaultIntent = newKey();

  String _context() => contextKey() ?? (throw StateError('请先连接原盒子'));
  void _check(String context) {
    if (contextKey() != context) throw StateError('盒子连接已变化，请返回原盒子恢复流程');
  }

  String _slot(String device) => 'import-analysis-intents:v1:$device';
  Map<String, Map<String, dynamic>> _records() {
    final device = deviceId();
    if (device == null) return {};
    final raw = cache.read<Map>(_slot(device));
    if (raw == null) return {};
    if (raw['format'] != 1 || raw['records'] is! Map) throw const ProtocolCompatibilityException('import-analysis-intents', '流程记录格式无法识别，保留原记录');
    return {for (final entry in (raw['records'] as Map).entries) entry.key.toString(): Map<String, dynamic>.from(entry.value as Map)};
  }

  Future<void> _save(Map<String, dynamic> record, String context, {bool authoritativeSnapshot = false}) {
    final immutable = _clone(record);
    final operation = _writes.catchError((Object _) {}).then((_) async {
      _check(context);
      if (deviceId() != immutable['device_id']) throw StateError('流程不属于当前盒子');
      final records = _records();
      final latest = records[immutable['id']];
      final saved = <String, dynamic>{...?latest, ...immutable};
      final project = saved['project_id'];
      if (project is String && latest?['snapshot'] is Map && immutable['snapshot'] is Map) {
        final before = ImportStartResult.fromSnapshot(Map<String, dynamic>.from(latest!['snapshot'] as Map), projectId: project);
        final incoming = ImportStartResult.fromSnapshot(Map<String, dynamic>.from(immutable['snapshot'] as Map), projectId: project);
        if (before.workflow.importJobId != incoming.workflow.importJobId || before.workflow.analysisJobId != incoming.workflow.analysisJobId || before.workflow.sessionId != incoming.workflow.sessionId) {
          throw const ProtocolCompatibilityException('workflow', '原流程任务标识发生变化，停止自动恢复');
        }
        saved['snapshot'] = ImportStartResult(
          workflow: incoming.workflow,
          importJob: incoming.importJob.canReplace(before.importJob) ? incoming.importJob : before.importJob,
          analysisJob: incoming.analysisJob.canReplace(before.analysisJob) ? incoming.analysisJob : before.analysisJob,
        ).toSnapshot();
        if (latest['phase'] == 'ready' && saved['phase'] == 'query_pending') saved['phase'] = 'ready';
      }
      final previousControl = latest?['cancel'], incomingControl = immutable['cancel'];
      if (previousControl is Map && incomingControl is Map) {
        if (previousControl['key'] == incomingControl['key'] && previousControl['confirmed'] == true) {
          saved['cancel'] = previousControl;
        } else if (previousControl['key'] != incomingControl['key'] && previousControl['confirmed'] != true) {
          throw const ImportAnalysisPending(cancel: true);
        }
      }
      final control = saved['cancel'];
      if (project is String && control is Map && saved['snapshot'] is Map) {
        final job = ImportStartResult.fromSnapshot(Map<String, dynamic>.from(saved['snapshot'] as Map), projectId: project).analysisJob;
        if (job.isTerminal || authoritativeSnapshot && job.version != null && job.version! > (control['version'] as int)) {
          saved['cancel'] = {...control, 'confirmed': true, 'outcome': job.state.name};
        }
      }
      records[immutable['id'] as String] = saved;
      await cache.write(_slot(immutable['device_id'] as String), {'format': 1, 'records': records});
      _check(context);
    });
    _writes = operation;
    return operation;
  }

  Map<String, dynamic>? _record(String project) {
    final rows = _records().values.where((row) => row['project_id'] == project).toList();
    return rows.where((row) => row['project_request'] is Map).lastOrNull ?? rows.lastOrNull;
  }

  bool owns(String project) => _record(project)?['managed'] == true;
  bool get hasPendingStart => _records().values.any((r) => r['phase'] != 'ready' && r['phase'] != 'rejected' && r['project_request'] is Map);
  bool cancelPending(String job) => _records().values.any((r) => (r['cancel'] as Map?)?['job_id'] == job && (r['cancel'] as Map?)?['action'] == 'cancel' && (r['cancel'] as Map?)?['confirmed'] != true);
  ImportStartResult? snapshot(String project) {
    final raw = _record(project)?['snapshot'];
    return raw is Map ? ImportStartResult.fromSnapshot(Map<String, dynamic>.from(raw), projectId: project) : null;
  }

  List<ImportStartResult> get snapshots => [
    for (final row in _records().values)
      if (row['snapshot'] is Map) ImportStartResult.fromSnapshot(Map<String, dynamic>.from(row['snapshot'] as Map), projectId: row['project_id'] as String),
  ];

  Future<ImportAnalysisCapability> capability() async {
    final context = _context();
    if (_capabilities[context] != null) return _capabilities[context]!;
    ImportAnalysisCapability value;
    try {
      value = ImportAnalysisCapability.fromJson(await readCapabilities());
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      value = const ImportAnalysisCapability(available: false);
    }
    _check(context);
    return _capabilities[context] = value;
  }

  Future<ImportStartResult> start({required String name, required String cardId, required AutoAnalysisRequest analysis, String? intentId}) async {
    final context = _context(), device = deviceId()!;
    final cap = await capability();
    _check(context);
    if (!cap.available) throw StateError('当前盒子不支持自动导入识别');
    if (analysis.smartFollow != null && !cap.smartFollowAvailable) throw const ApiException(message: '盒子不支持所选持续复制', code: 'smart_follow_unavailable', statusCode: 409);
    final projectRequest = ProjectCreateRequest(name: name, cardId: cardId).toJson();
    final importRequest = ImportJobRequest(autoAnalysis: analysis).toJson();
    final body = _canonical({'project': projectRequest, 'import': importRequest});
    final logicalIntent = intentId ?? _defaultIntent;
    if (_starting[device] != null) {
      if (_startBodies[device] != body) throw const ImportAnalysisPending();
      return _starting[device]!;
    }
    final pending = _records().values.where((r) => r['phase'] != 'ready' && r['phase'] != 'rejected' && r['project_request'] is Map).firstOrNull;
    if (pending != null && pending['body'] != body) throw const ImportAnalysisPending();
    final completed = _records().values.where((r) => r['phase'] == 'ready' && r['body'] == body && r['logical_intent'] == logicalIntent).lastOrNull;
    if (pending == null && completed != null) return refresh(completed['project_id'] as String);
    final rejected = _records().values.where((r) => r['phase'] == 'rejected' && r['body'] == body).lastOrNull;
    if (pending == null && rejected != null) throw ApiException(message: '原请求已被拒绝，请按错误原因修正参数', code: rejected['error_code'] as String?);
    final id = newKey();
    final record =
        pending ??
        <String, dynamic>{
          'id': id,
          'device_id': device,
          'managed': true,
          'phase': 'project_pending',
          'project_key': 'import-project-$id',
          'import_key': 'import-start-$id',
          'project_request': projectRequest,
          'import_request': importRequest,
          'body': body,
          'sent': false,
          'logical_intent': logicalIntent,
        };
    _startBodies[device] = body;
    final request = _start(record, context);
    _starting[device] = request;
    try {
      return await request;
    } finally {
      if (identical(_starting[device], request)) {
        final _ = _starting.remove(device);
        _startBodies.remove(device);
      }
    }
  }

  Future<ImportStartResult> resumePending() async {
    final context = _context(), device = deviceId()!;
    if (_starting[device] != null) return _starting[device]!;
    final pending = _records().values.where((r) => r['phase'] != 'ready' && r['phase'] != 'rejected' && r['project_request'] is Map).firstOrNull;
    if (pending == null) throw StateError('没有待恢复的开始请求');
    final request = _start(pending, context);
    _starting[device] = request;
    _startBodies[device] = pending['body'] as String;
    try {
      return await request;
    } finally {
      if (identical(_starting[device], request)) {
        final _ = _starting.remove(device);
        _startBodies.remove(device);
      }
    }
  }

  Future<ImportStartResult> _start(Map<String, dynamic> record, String context) async {
    await _save(record, context); // No POST may precede this durable boundary.
    try {
      if (record['project_id'] == null) {
        final data = Map<String, dynamic>.from(record['project_request'] as Map);
        final project = await batches.create(ProjectCreateRequest(name: data['name'] as String, cardId: data['card_id'] as String, idempotencyKey: record['project_key'] as String));
        _check(context);
        record.addAll({'project_id': project.id, 'phase': 'import_pending'});
        await _save(record, context);
      }
      final project = record['project_id'] as String;
      if (record['sent'] == true) {
        try {
          return await refresh(project);
        } on ApiException catch (error) {
          if (error.statusCode != 404 || error.code != 'import_analysis_not_found') rethrow;
        }
      }
      record['sent'] = true;
      await _save(record, context);
      final receipt = await repository.startImportWorkflow(project, _clone(record['import_request'] as Map), record['import_key'] as String);
      _check(context);
      await _accept(record, receipt, context, phase: 'query_pending');
      return await refresh(project); // Replay returns first snapshot, not current progress.
    } catch (error) {
      _check(context);
      if (error is ApiException && const {'import_analysis_owned', 'import_analysis_conflict'}.contains(error.code) && record['project_id'] is String) {
        try {
          return await refresh(record['project_id'] as String);
        } catch (_) {
          _check(context);
        }
      }
      if (error is ApiException && (error.statusCode == 422 || const {'source_card_changed', 'smart_follow_unavailable'}.contains(error.code))) {
        record.addAll({'phase': 'rejected', 'error_code': error.code});
        await _save(record, context);
        rethrow;
      }
      if (error is ProtocolCompatibilityException) rethrow;
      throw const ImportAnalysisPending();
    }
  }

  Future<ImportStartResult> refresh(String project) {
    final context = _context(), key = '${deviceId()}:$project';
    final existing = _reading[key];
    if (existing != null) return existing;
    final request = _refresh(project, context);
    _reading[key] = request;
    return request.whenComplete(() {
      if (identical(_reading[key], request)) _reading.remove(key);
    });
  }

  Future<ImportStartResult> _refresh(String project, String context) async {
    final result = await repository.importWorkflow(project);
    _check(context);
    final record = _record(project) ?? <String, dynamic>{'id': 'known:$project', 'device_id': deviceId(), 'project_id': project, 'managed': true};
    return _accept(record, result, context, phase: 'ready');
  }

  Future<ImportStartResult> _accept(Map<String, dynamic> record, ImportStartResult result, String context, {required String phase, bool controlReceipt = false}) async {
    final project = record['project_id'] as String;
    final previous = snapshot(project);
    if (result.workflow.projectId != project ||
        (previous != null && (previous.workflow.importJobId != result.workflow.importJobId || previous.workflow.analysisJobId != result.workflow.analysisJobId || previous.workflow.sessionId != result.workflow.sessionId))) {
      throw const ProtocolCompatibilityException('workflow', '原流程任务标识发生变化，停止自动恢复');
    }
    final automatic = (record['import_request'] as Map?)?['auto_analysis'];
    if (automatic is Map && automatic['smart_follow'] != null && result.workflow.sessionId == null) throw const ProtocolCompatibilityException('smart_follow_session_id', '盒子没有登记已选择的复制会话');
    final merged = ImportStartResult(
      workflow: result.workflow,
      importJob: previous != null && !result.importJob.canReplace(previous.importJob) ? previous.importJob : result.importJob,
      analysisJob: previous != null && !result.analysisJob.canReplace(previous.analysisJob) ? previous.analysisJob : result.analysisJob,
    );
    record.addAll({'managed': true, 'phase': phase, 'snapshot': merged.toSnapshot()});
    final cancel = record['cancel'];
    if (cancel is Map && (merged.analysisJob.isTerminal || (!controlReceipt && merged.analysisJob.version != null && merged.analysisJob.version! > (cancel['version'] as int)))) {
      record['cancel'] = {...cancel, 'confirmed': true, 'outcome': merged.analysisJob.state.name};
    }
    await _save(record, context, authoritativeSnapshot: phase == 'ready' && !controlReceipt);
    return snapshot(project)!;
  }

  Future<bool> ensureOwner(String project) async {
    if (owns(project)) {
      try {
        await refresh(project);
      } on ApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
      return true;
    }
    if (!(await capability()).available) return false;
    try {
      await refresh(project);
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 404 && error.code == 'import_analysis_not_found') return false;
      rethrow;
    }
  }

  Future<void> reconcileOwned(String project) async {
    final context = _context();
    await _save(_record(project) ?? {'id': 'known:$project', 'device_id': deviceId(), 'project_id': project, 'managed': true, 'phase': 'query_pending'}, context);
    await refresh(project);
  }

  Future<void> restoreActive() async {
    final projects = _records().values.where((r) => r['project_id'] is String && r['phase'] != 'rejected').map((r) => r['project_id'] as String).toList();
    for (final project in projects) {
      final prior = snapshot(project);
      if (prior?.analysisJob.isTerminal == true && prior?.importJob.isTerminal == true && !cancelPending(prior!.analysisJob.id)) continue;
      await refresh(project);
    }
  }

  Future<BirdJobStatus> controlAnalysis(String project, String action, int version) async {
    final context = _context();
    var record = _record(project), current = snapshot(project);
    if (record == null || current == null) throw StateError('请刷新原识别任务后再操作');
    final pendingBeforeRead = cancelPending(current.analysisJob.id) ? Map<String, dynamic>.from(record['cancel'] as Map) : null;
    try {
      current = await refresh(project);
    } catch (_) {
      _check(context);
      if (pendingBeforeRead != null) throw const ImportAnalysisPending(cancel: true);
      rethrow;
    }
    record = _record(project)!;
    if (pendingBeforeRead != null) {
      if (current.analysisJob.isTerminal) return current.analysisJob;
      if (current.analysisJob.version != pendingBeforeRead['version']) throw const ApiException(message: '任务状态已变化，请重新确认取消', code: 'VERSION_CONFLICT', statusCode: 409);
    }
    if (current.analysisJob.version != version) throw const ApiException(message: '任务状态已变化，请重新确认操作', code: 'VERSION_CONFLICT', statusCode: 409);
    if (!current.analysisJob.allowsControl(action)) throw StateError('请刷新原识别任务后再操作');
    var cancel = record['cancel'] as Map?;
    if (cancel != null && cancel['confirmed'] != true && (cancel['version'] != version || cancel['action'] != action)) throw const ImportAnalysisPending(cancel: true);
    cancel = {'job_id': current.analysisJob.id, 'action': action, 'version': version, 'key': 'import-analysis-${current.analysisJob.id}-$action-$version', 'confirmed': false};
    record['cancel'] = cancel;
    await _save(record, context);
    try {
      final updated = await repository.controlWorkflowJob(current.analysisJob.id, action, version, cancel['key'] as String);
      _check(context);
      final merged = ImportStartResult(workflow: current.workflow, importJob: current.importJob, analysisJob: updated);
      await _accept(record, merged, context, phase: 'ready', controlReceipt: true);
      // A command ACK that still says queued is not proof of cancellation.
      if (action == 'cancel' && updated.state != BirdJobState.cancelled) {
        final refreshed = await refresh(project);
        if (refreshed.analysisJob.isTerminal) return refreshed.analysisJob;
        if (!cancelPending(refreshed.analysisJob.id)) throw const ApiException(message: '任务状态已变化，请重新确认取消', code: 'VERSION_CONFLICT', statusCode: 409);
        if (refreshed.analysisJob.state != BirdJobState.cancelled) throw const ImportAnalysisPending(cancel: true);
        return refreshed.analysisJob;
      }
      record['cancel'] = {...cancel, 'confirmed': true};
      await _save(record, context);
      return snapshot(project)!.analysisJob;
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          await refresh(project);
        } catch (_) {
          _check(context);
        }
        rethrow;
      }
      if (error.statusCode != null && error.statusCode! >= 400 && error.statusCode! < 500 && !const {408, 429}.contains(error.statusCode)) {
        record['cancel'] = {...cancel, 'confirmed': true, 'outcome': 'rejected', 'error_code': error.code};
        await _save(record, context);
        rethrow;
      }
      throw const ImportAnalysisPending(cancel: true);
    } catch (_) {
      _check(context);
      throw const ImportAnalysisPending(cancel: true);
    }
  }

  static Map<String, dynamic> _clone(Map value) => Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  static String _canonical(Object? value) {
    Object? sorted(Object? v) => v is Map
        ? {for (final key in v.keys.map((k) => k.toString()).toList()..sort()) key: sorted(v[key])}
        : v is List
        ? v.map(sorted).toList()
        : v;
    return jsonEncode(sorted(value));
  }
}
