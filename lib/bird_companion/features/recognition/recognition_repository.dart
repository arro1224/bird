import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:flutter/foundation.dart';

/// All business facts come from Python. WS only wakes durable replay.
class RecognitionRepository extends ChangeNotifier {
  RecognitionRepository(this.api, this.cache, this.changes, this.deviceId);
  final ApiClient api;
  final LocalCache cache;
  final AppDataChangeBus changes;
  final String? Function() deviceId;
  final Map<String, Map<String, dynamic>> _snapshots = {};
  final Map<String, Future<void>> _inFlight = {};
  final Set<String> _repeat = {};
  bool _closed = false;

  String _key(String id) => '${deviceId()}:$id';
  Map<String, dynamic>? snapshot(String job) => _snapshots[_key(job)];

  Future<Map<String, dynamic>> capabilities() => api.get('/api/v1/recognition-capabilities');

  Future<void> rememberAnalysisOption(String project, Map<String, dynamic>? config) => cache.write('recognition-option:${_key(project)}', config);
  Map<String, dynamic>? analysisOption(String project) {
    final raw = cache.read<Map>('recognition-option:${_key(project)}');
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  Future<void> sync(String job) {
    final key = _key(job);
    final running = _inFlight[key];
    if (running != null) {
      _repeat.add(key);
      return running;
    }
    final request = _sync(job, key);
    _inFlight[key] = request;
    return request.whenComplete(() {
      _inFlight.remove(key);
      if (_repeat.remove(key) && !_closed && key == _key(job)) unawaited(sync(job).catchError((Object _) {}));
    });
  }

  Future<void> _sync(String job, String key) async {
    final requestedDevice = deviceId();
    final requestedUri = api.baseUri;
    bool current() => !_closed && requestedDevice == deviceId() && requestedUri == api.baseUri;
    var cursor = cache.read<int>('recognition-cursor:$key') ?? 0;
    do {
      final response = await api.get('/api/v1/jobs/$job/recognition-events', queryParameters: {'after_event_seq': cursor, 'page_size': 100});
      if (!current()) return;
      final data = response;
      final rows = (data['items'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      final accepted = <Map<String, dynamic>>[];
      for (final row in rows) {
        final seq = row['event_seq'] as int;
        if (seq <= cursor) continue;
        if (seq != cursor + 1 || row['recognition_job_id'] != job) throw StateError('识别结果序号不连续，请重新加载');
        accepted.add(row);
        cursor = seq;
      }
      final previous = _snapshots[key];
      if (previous == null || (data['last_event_seq'] as int) >= (previous['last_event_seq'] as int)) _snapshots[key] = data;
      if (accepted.isNotEmpty && requestedDevice != null) {
        changes.publishChange(RecognitionFactsChanged(deviceId: requestedDevice, projectId: accepted.first['project_id'] as String, fileIds: accepted.map((e) => e['file_id'] as String).toSet()));
        await cache.write('recognition-cursor:$key', cursor);
      }
      final session = data['smart_follow_session_id'] as String?;
      if (session != null) {
        final sessionData = await api.get('/api/v1/smart-follow-sessions/$session');
        if (!current()) return;
        final old = previous?['smart_follow'] as Map?;
        _snapshots[key]!['smart_follow'] = old == null || (sessionData['state_version'] as int) >= (old['state_version'] as int) ? sessionData : old;
      }
      if (!current()) return;
      notifyListeners();
      if (data['has_more'] != true) return;
    } while (current());
  }

  Future<void> startFollow(String job, Map<String, dynamic> config) async {
    await api.post('/api/v1/jobs/$job/smart-follow-sessions', data: config, idempotencyKey: 'follow-start-$job');
    await sync(job);
  }

  Future<List<Map<String, dynamic>>> childJobs(String session) async {
    final data = await api.get('/api/v1/smart-follow-sessions/$session/copy-jobs');
    return (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> action(String job, String action) async {
    final session = snapshot(job)?['smart_follow'] as Map;
    await api.post(
      '/api/v1/smart-follow-sessions/${session['session_id']}/actions',
      data: {'action': action, 'expected_state_version': session['state_version']},
      idempotencyKey: '${session['session_id']}-$action-${session['state_version']}',
    );
    await sync(job);
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
