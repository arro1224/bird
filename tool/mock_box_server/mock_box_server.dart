import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class MockBoxServer {
  MockBoxServer({
    this.photoCount = 1200,
    Directory? assetDirectory,
    this.logRequests = true,
    this.requireAuthentication = false,
    this.deviceId = 'mock-k7-001',
    this.pairingCode = '2468',
    this.tokenLifetime = const Duration(minutes: 10),
    this.signedUrlLifetime = const Duration(minutes: 2),
    this.stateFile,
    DateTime Function()? clock,
  }) : assetDirectory = assetDirectory ?? Directory('tool/mock_box_server/assets') {
    _clock = clock ?? DateTime.now;
    if (photoCount <= 0) {
      throw ArgumentError.value(photoCount, 'photoCount', '必须大于 0');
    }
    _photos = List.generate(photoCount, _buildPhoto, growable: false);
    _photosById = {for (final photo in _photos) photo['file_id'] as String: photo};
    _scenes = _buildScenes();
    _groups = _buildGroups();
    _restoreState();
  }

  final int photoCount;
  final Directory assetDirectory;
  final bool logRequests;
  final bool requireAuthentication;
  final String deviceId;
  final String pairingCode;
  final Duration tokenLifetime;
  final Duration signedUrlLifetime;
  final File? stateFile;
  late final DateTime Function() _clock;

  late final List<Map<String, dynamic>> _photos;
  late final Map<String, Map<String, dynamic>> _photosById;
  late final List<Map<String, dynamic>> _scenes;
  late final List<Map<String, dynamic>> _groups;
  final Map<String, Map<String, dynamic>> _decisions = {};
  final Map<String, List<Map<String, dynamic>>> _history = {};
  final Map<String, Map<String, dynamic>> _createdProjects = {};
  final Map<String, Map<String, dynamic>> _jobs = {};
  final Map<String, _CachedHttpResponse> _idempotentResponses = {};
  final Map<String, Completer<_CachedHttpResponse>> _idempotentInFlight = {};
  final Map<HttpRequest, String> _idempotencyByRequest = {};
  final Set<WebSocket> _eventSockets = {};
  Future<void> _stateWrite = Future<void>.value();
  String? _currentCreatedProjectId;
  bool _currentProjectAvailable = true;
  int _projectSequence = 0;
  int _jobSequence = 0;
  String? _activeToken;
  DateTime? _tokenExpiresAt;
  String? lastPairAuthorizationHeader;
  String? lastSignedAssetAuthorizationHeader;
  int jobListRequestCount = 0;

  HttpServer? _server;

  Uri? get baseUri {
    final server = _server;
    if (server == null) return null;
    final host = server.address.type == InternetAddressType.IPv6 ? '[${server.address.address}]' : server.address.address;
    return Uri.parse('http://$host:${server.port}');
  }

  void revokeAccessToken() {
    _activeToken = null;
    _tokenExpiresAt = null;
  }

  void setCurrentProjectAvailable(bool value) {
    _currentProjectAvailable = value;
  }

  List<Map<String, dynamic>> get jobs => _jobs.values.map(Map<String, dynamic>.of).toList();

  Future<void> completeJob(String jobId, {bool emitEvent = true}) async {
    final job = _jobs[jobId];
    if (job == null) throw ArgumentError.value(jobId, 'jobId', 'Unknown job');
    job
      ..['job_state'] = 'completed'
      ..['progress'] = 1.0
      ..['finished_count'] = job['total_count']
      ..['available_actions'] = <String>['delete']
      ..['version'] = (job['version'] as int) + 1
      ..['updated_at'] = _clock().toUtc().toIso8601String();
    await _persistState();
    if (emitEvent) await _emitJob(job);
  }

  Future<void> failJob(
    String jobId, {
    int failedCount = 2,
    bool emitEvent = true,
  }) async {
    final job = _jobs[jobId];
    if (job == null) {
      throw ArgumentError.value(jobId, 'jobId', 'Unknown job');
    }
    final total = job['total_count'] as int;
    final failures = failedCount.clamp(1, total);
    job
      ..['job_state'] = 'failed'
      ..['progress'] = 1.0
      ..['finished_count'] = total
      ..['failed_count'] = failures
      ..['available_actions'] = <String>[
        'retry_failed',
        'skip_failed',
        'delete',
      ]
      ..['version'] = (job['version'] as int) + 1
      ..['updated_at'] = _clock().toUtc().toIso8601String();
    await _persistState();
    if (emitEvent) await _emitJob(job);
  }

  Future<Uri> start({
    InternetAddress? address,
    int port = 0,
  }) async {
    if (_server != null) throw StateError('Mock box server is already running.');
    final server = await HttpServer.bind(address ?? InternetAddress.loopbackIPv4, port);
    _server = server;
    unawaited(
      server.forEach((request) async {
        try {
          await _handle(request);
        } catch (error, stackTrace) {
          stderr.writeln('Mock box request failed: $error\n$stackTrace');
          try {
            await _json(
              request,
              HttpStatus.internalServerError,
              {
                'error_code': 'mock_internal_error',
                'error_message': 'Mock box request failed.',
              },
              envelope: false,
            );
          } catch (_) {
            await request.response.close();
          }
        }
      }),
    );
    return baseUri!;
  }

  Future<void> close() async {
    for (final socket in List<WebSocket>.of(_eventSockets)) {
      await socket.close();
    }
    _eventSockets.clear();
    final server = _server;
    _server = null;
    await server?.close(force: true);
    await _stateWrite;
  }

  Future<void> _handle(HttpRequest request) async {
    if (logRequests) {
      // Query strings may contain short-lived signatures. Never print them.
      stdout.writeln('${request.method} ${request.uri.path}');
    }
    _cors(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final method = request.method;
    final path = request.uri.path;

    if (method == 'GET' && path == '/healthz') {
      await _json(request, HttpStatus.ok, {'status': 'ok', 'photos': photoCount});
      return;
    }
    if (method == 'GET' && path == '/api/v1/device/status') {
      await _json(request, HttpStatus.ok, _deviceStatus());
      return;
    }
    if (method == 'POST' && path == '/api/v1/device/pair') {
      if (await _replayOrRegisterIdempotent(request)) return;
      await _pair(request);
      return;
    }
    if (method == 'GET' && path.startsWith('/mock/media/')) {
      await _serveMedia(request);
      return;
    }
    if (method == 'GET' && path.startsWith('/mock/logs/')) {
      await _serveLog(request);
      return;
    }
    if (method == 'GET' && path == '/api/v1/events') {
      if (!await _authorize(request)) return;
      await _serveEvents(request);
      return;
    }
    if (!await _authorize(request)) return;
    if (method == 'POST' && await _replayOrRegisterIdempotent(request)) {
      return;
    }
    if (method == 'POST' && path == '/api/v1/logs/export') {
      final body = await _requestJson(request);
      if (!const {
        'device',
        'jobs',
        'device_and_jobs',
      }.contains(body['scope'])) {
        await _json(
          request,
          HttpStatus.unprocessableEntity,
          {
            'error_code': 'log_export_scope_invalid',
            'error_message': 'A valid log export scope is required.',
          },
          envelope: false,
        );
        return;
      }
      await _json(request, HttpStatus.ok, {
        'export_id': 'mock-log-export',
        'state': 'ready',
        'download_url': _signedPath('/mock/logs/diagnostics.txt'),
        'expires_at': _clock().toUtc().add(signedUrlLifetime).toIso8601String(),
      });
      return;
    }
    if (method == 'GET' && path == '/api/v1/projects/current') {
      if (!_currentProjectAvailable) {
        await _json(request, HttpStatus.ok, const {});
        return;
      }
      await _json(request, HttpStatus.ok, {
        'batch': _currentCreatedProjectId == null ? _currentBatch() : _createdProjects[_currentCreatedProjectId],
      });
      return;
    }
    if (method == 'POST' && path == '/api/v1/projects') {
      await _createProject(request);
      return;
    }
    if (method == 'GET' && path == '/api/v1/projects') {
      await _json(request, HttpStatus.ok, {
        'items': [
          ..._createdProjects.values.toList().reversed,
          _currentBatch(),
          ..._historyBatches(),
        ],
        'has_more': false,
      });
      return;
    }
    if (method == 'GET' && path == '/api/v1/storage/cards/current/scan') {
      await _json(request, HttpStatus.ok, _cardScan());
      return;
    }
    if (method == 'POST' && path == '/api/v1/storage/cards/current/rescan') {
      final job = _newJob('sync', null, workflowStage: 'scanning');
      await _json(request, HttpStatus.accepted, job);
      return;
    }
    if (method == 'GET' && path == '/api/v1/jobs') {
      jobListRequestCount++;
      final query = request.uri.queryParameters;
      var items = _jobs.values.toList().reversed.toList();
      final state = query['state'];
      final type = query['type'];
      if (state?.isNotEmpty == true) {
        items = items.where((job) => job['job_state'] == state).toList();
      }
      if (type?.isNotEmpty == true) {
        items = items.where((job) => job['job_type'] == type).toList();
      }
      final pageSize = (int.tryParse(query['page_size'] ?? '') ?? 50).clamp(1, 100);
      final cursor = (int.tryParse(query['cursor'] ?? '') ?? 0).clamp(0, items.length);
      final end = min(cursor + pageSize, items.length);
      await _json(request, HttpStatus.ok, {
        'items': items.sublist(cursor, end),
        'has_more': end < items.length,
        if (end < items.length) 'next_cursor': '$end',
      });
      return;
    }

    final copyEstimate = RegExp(
      r'^/api/v1/projects/([^/]+)/copy/estimate$',
    ).firstMatch(path);
    if (method == 'GET' && copyEstimate != null) {
      await _serveCopyEstimate(
        request,
        copyEstimate.group(1)!,
      );
      return;
    }
    final copyCreate = RegExp(
      r'^/api/v1/projects/([^/]+)/copy$',
    ).firstMatch(path);
    if (method == 'POST' && copyCreate != null) {
      await _createCopyJob(request, copyCreate.group(1)!);
      return;
    }

    final importJob = RegExp(r'^/api/v1/projects/([^/]+)/imports$').firstMatch(path);
    if (method == 'POST' && importJob != null) {
      await _createWorkflowJob(request, importJob.group(1)!, 'import');
      return;
    }
    final analysisJob = RegExp(
      r'^/api/v1/projects/([^/]+)/analysis-jobs$',
    ).firstMatch(path);
    if (method == 'POST' && analysisJob != null) {
      await _createWorkflowJob(
        request,
        analysisJob.group(1)!,
        'analysis',
      );
      return;
    }
    final jobAction = RegExp(r'^/api/v1/jobs/([^/]+)/actions$').firstMatch(path);
    if (method == 'POST' && jobAction != null) {
      await _controlJob(request, jobAction.group(1)!);
      return;
    }
    final jobFailures = RegExp(
      r'^/api/v1/jobs/([^/]+)/failures$',
    ).firstMatch(path);
    if (method == 'GET' && jobFailures != null) {
      await _serveJobFailures(request, jobFailures.group(1)!);
      return;
    }
    final jobReport = RegExp(r'^/api/v1/jobs/([^/]+)/report$').firstMatch(path);
    if (method == 'GET' && jobReport != null) {
      await _serveJobReport(request, jobReport.group(1)!);
      return;
    }
    final jobDetail = RegExp(r'^/api/v1/jobs/([^/]+)$').firstMatch(path);
    if (method == 'GET' && jobDetail != null) {
      final job = _jobs[jobDetail.group(1)!];
      if (job == null) {
        await _notFound(request, 'Unknown job: ${jobDetail.group(1)}');
      } else {
        await _json(request, HttpStatus.ok, job);
      }
      return;
    }
    if (method == 'GET' && path == '/api/v1/species') {
      await _json(request, HttpStatus.ok, {'items': _speciesSearch(request.uri.queryParameters['search'])});
      return;
    }
    final projectFiles = RegExp(r'^/api/v1/projects/([^/]+)/files$').firstMatch(path);
    if (method == 'GET' && projectFiles != null) {
      if (!_isKnownBatch(projectFiles.group(1)!)) {
        await _notFound(request, 'Unknown project: ${projectFiles.group(1)}');
        return;
      }
      await _json(request, HttpStatus.ok, _photoPage(request.uri.queryParameters));
      return;
    }

    final projectScenes = RegExp(r'^/api/v1/projects/([^/]+)/scenes$').firstMatch(path);
    if (method == 'GET' && projectScenes != null) {
      await _json(request, HttpStatus.ok, {'items': _scenes});
      return;
    }

    final projectGroups = RegExp(r'^/api/v1/projects/([^/]+)/groups$').firstMatch(path);
    if (method == 'GET' && projectGroups != null) {
      final sceneId = request.uri.queryParameters['scene_id'];
      final groups = sceneId == null ? _groups : _groups.where((group) => group['scene_id'] == sceneId);
      await _json(request, HttpStatus.ok, {
        'items': groups.map(_groupWithMembers).toList(growable: false),
      });
      return;
    }

    final projectActions = RegExp(r'^/api/v1/projects/([^/]+)/files/actions$').firstMatch(path);
    if (method == 'POST' && projectActions != null) {
      await _applyBatchAction(request);
      return;
    }

    final projectResume = RegExp(r'^/api/v1/projects/([^/]+)/resume$').firstMatch(path);
    if (method == 'POST' && projectResume != null) {
      await _json(request, HttpStatus.ok, {'project_id': projectResume.group(1), 'resumed': true});
      return;
    }

    final detail = RegExp(r'^/api/v1/files/([^/]+)$').firstMatch(path);
    if (method == 'GET' && detail != null) {
      await _serveDetail(request, detail.group(1)!);
      return;
    }

    final history = RegExp(r'^/api/v1/files/([^/]+)/history$').firstMatch(path);
    if (method == 'GET' && history != null) {
      await _serveHistory(request, history.group(1)!);
      return;
    }

    final decision = RegExp(r'^/api/v1/files/([^/]+)/decision$').firstMatch(path);
    if (method == 'POST' && decision != null) {
      await _saveDecision(request, decision.group(1)!);
      return;
    }

    await _notFound(request, 'Unknown mock endpoint: $path');
  }

  Map<String, dynamic> _cardScan() => {
    'scan_state': 'detected',
    'card_id': 'card-mock-001',
    'card_name': 'MOCK-SD',
    'photo_count': photoCount,
    'raw_count': (photoCount * .68).round(),
    'jpeg_count': photoCount - (photoCount * .68).round(),
    'required_bytes': photoCount * 24 * 1024 * 1024,
  };

  Future<void> _serveCopyEstimate(
    HttpRequest request,
    String projectId,
  ) async {
    if (!_isKnownBatch(projectId)) {
      await _notFound(request, 'Unknown project: $projectId');
      return;
    }
    final mode = request.uri.queryParameters['mode'];
    if (!const {'keep', 'all', 'dual'}.contains(mode)) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'copy_mode_invalid',
          'error_message': 'A valid copy mode is required.',
        },
        envelope: false,
      );
      return;
    }
    final fileCount = switch (mode) {
      'all' => photoCount,
      'dual' => photoCount * 2,
      _ =>
        _photos
            .where(
              (photo) => photo['keep_state'] == 'keep' || photo['keep_state'] == 'featured',
            )
            .length,
    };
    await _json(request, HttpStatus.ok, {
      'mode': mode,
      'file_count': fileCount,
      'required_bytes': fileCount * 24 * 1024 * 1024,
      'pending_count': _photos.where((photo) => photo['keep_state'] == 'pending').length,
      'version': 0,
      'targets': [
        {
          'id': 'mock-usb-1',
          'name': 'MOCK-USB',
          'free_bytes': 256 * 1024 * 1024 * 1024,
          'total_bytes': 512 * 1024 * 1024 * 1024,
          'online': true,
        },
        {
          'id': 'mock-offline',
          'name': 'MOCK-OFFLINE',
          'free_bytes': 0,
          'total_bytes': 512 * 1024 * 1024 * 1024,
          'online': false,
        },
      ],
    });
  }

  Future<void> _createCopyJob(
    HttpRequest request,
    String projectId,
  ) async {
    if (!_isKnownBatch(projectId)) {
      await _notFound(request, 'Unknown project: $projectId');
      return;
    }
    final body = await _requestJson(request);
    final valid = const {'keep', 'all', 'dual'}.contains(body['mode']) && body['target_id'] == 'mock-usb-1' && body['xmp_enabled'] is bool && body['verify_after_copy'] is bool && body['version'] == 0;
    if (!valid) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'copy_request_invalid',
          'error_message': 'The copy request does not match birdbox-v1.',
        },
        envelope: false,
      );
      return;
    }
    final job = _newJob(
      'copy',
      projectId,
      workflowStage: 'copying',
    );
    await _json(request, HttpStatus.accepted, job);
    await _emitJob(job);
  }

  Future<void> _createProject(HttpRequest request) async {
    final body = await _requestJson(request);
    final name = body['name']?.toString().trim() ?? '';
    final cardId = body['card_id']?.toString();
    if (name.isEmpty || cardId != 'card-mock-001') {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'project_invalid',
          'error_message': 'name and the current card_id are required.',
        },
        envelope: false,
      );
      return;
    }
    final id = 'project-${(++_projectSequence).toString().padLeft(4, '0')}';
    final project = <String, dynamic>{
      'project_id': id,
      'name': name,
      'created_at': _clock().toUtc().toIso8601String(),
      'total_files': 0,
      'analyzed_count': 0,
      'pending_review_count': 0,
      'keep_count': 0,
      'discard_count': 0,
      'pending_copy_count': 0,
      'copy_state': 'idle',
      'scene_count': 0,
      'burst_group_count': 0,
    };
    _createdProjects[id] = project;
    _currentCreatedProjectId = id;
    await _json(request, HttpStatus.created, project);
  }

  Future<void> _createWorkflowJob(
    HttpRequest request,
    String projectId,
    String type,
  ) async {
    if (!_createdProjects.containsKey(projectId) && !_isKnownBatch(projectId)) {
      await _notFound(request, 'Unknown project: $projectId');
      return;
    }
    final body = await _requestJson(request);
    final valid = type == 'import' ? body['source'] == 'card' && body['read_only'] == true : body['mode'] == 'standard';
    if (!valid) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'job_request_invalid',
          'error_message': 'The job request does not match birdbox-v1.',
        },
        envelope: false,
      );
      return;
    }
    final existing = _jobs.values.where(
      (job) => job['job_type'] == type && job['source_project_id'] == projectId && job['job_state'] != 'cancelled',
    );
    if (existing.isNotEmpty) {
      await _json(
        request,
        HttpStatus.conflict,
        {
          'error_code': 'job_already_exists',
          'error_message': 'The workflow job already exists.',
        },
        envelope: false,
      );
      return;
    }
    final job = _newJob(
      type,
      projectId,
      workflowStage: type == 'import' ? 'importing' : 'analyzing',
    );
    await _json(request, HttpStatus.accepted, job);
    await _emitJob(job);
  }

  Map<String, dynamic> _newJob(
    String type,
    String? projectId, {
    required String workflowStage,
  }) {
    final id = 'job-$type-${(++_jobSequence).toString().padLeft(4, '0')}';
    final project = projectId == null ? null : _createdProjects[projectId] ?? (projectId == 'mock-batch-current' ? _currentBatch() : null);
    final job = <String, dynamic>{
      'job_id': id,
      'job_type': type,
      'job_state': 'running',
      'workflow_stage': workflowStage,
      'source_project_id': ?projectId,
      'source_project_name': ?project?['name'],
      'progress': 0.0,
      'total_count': photoCount,
      'finished_count': 0,
      'failed_count': 0,
      'skipped_count': 0,
      'estimated_remaining_seconds': 240,
      'available_actions': <String>['pause', 'cancel'],
      'created_at': _clock().toUtc().toIso8601String(),
      'updated_at': _clock().toUtc().toIso8601String(),
      'version': 0,
    };
    _jobs[id] = job;
    return job;
  }

  Future<void> _controlJob(HttpRequest request, String jobId) async {
    final job = _jobs[jobId];
    if (job == null) {
      await _notFound(request, 'Unknown job: $jobId');
      return;
    }
    final body = await _requestJson(request);
    final version = body['version'];
    if (version != job['version']) {
      await _json(
        request,
        HttpStatus.conflict,
        {
          'error_code': 'job_version_conflict',
          'error_message': 'Reload the latest job before controlling it.',
        },
        envelope: false,
      );
      return;
    }
    final action = body['action']?.toString() ?? '';
    final available = (job['available_actions'] as List).cast<String>();
    if (!available.contains(action)) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'job_action_unavailable',
          'error_message': 'The action is not currently available.',
        },
        envelope: false,
      );
      return;
    }
    switch (action) {
      case 'pause':
        job
          ..['job_state'] = 'paused'
          ..['available_actions'] = <String>['resume', 'cancel'];
      case 'resume':
      case 'retry_failed':
        job
          ..['job_state'] = 'running'
          ..['failed_count'] = 0
          ..['available_actions'] = <String>['pause', 'cancel'];
      case 'cancel':
        job
          ..['job_state'] = 'cancelled'
          ..['available_actions'] = <String>['delete'];
      case 'skip_failed':
        final failed = job['failed_count'] as int;
        job
          ..['job_state'] = 'completed'
          ..['progress'] = 1.0
          ..['finished_count'] = job['total_count']
          ..['skipped_count'] = (job['skipped_count'] as int) + failed
          ..['failed_count'] = 0
          ..['available_actions'] = <String>['delete'];
    }
    job
      ..['version'] = (job['version'] as int) + 1
      ..['updated_at'] = _clock().toUtc().toIso8601String();
    await _json(request, HttpStatus.ok, job);
    await _emitJob(job);
  }

  Future<void> _serveJobReport(
    HttpRequest request,
    String jobId,
  ) async {
    final job = _jobs[jobId];
    if (job == null) {
      await _notFound(request, 'Unknown job: $jobId');
      return;
    }
    final total = job['total_count'] as int;
    final failed = job['failed_count'] as int;
    final skipped = job['skipped_count'] as int;
    await _json(request, HttpStatus.ok, {
      'job_id': jobId,
      'result': switch (job['job_state']) {
        'completed' when failed > 0 => 'partial_success',
        'completed' => 'success',
        'cancelled' => 'cancelled',
        _ => 'failed',
      },
      'total_count': total,
      'success_count': (job['finished_count'] as int) - failed - skipped,
      'failed_count': failed,
      'skipped_count': skipped,
      'started_at': job['created_at'],
      'finished_at': job['updated_at'],
    });
  }

  Future<void> _serveJobFailures(
    HttpRequest request,
    String jobId,
  ) async {
    final job = _jobs[jobId];
    if (job == null) {
      await _notFound(request, 'Unknown job: $jobId');
      return;
    }
    final failedCount = job['failed_count'] as int;
    final query = request.uri.queryParameters;
    final pageSize = (int.tryParse(query['page_size'] ?? '') ?? 50).clamp(1, 100);
    final cursor = (int.tryParse(query['cursor'] ?? '') ?? 0).clamp(0, failedCount);
    final end = min(cursor + pageSize, failedCount);
    await _json(request, HttpStatus.ok, {
      'items': List.generate(
        end - cursor,
        (index) => {
          'file_id': 'mock-failed-${cursor + index + 1}',
          'error_code': 'copy_io_error',
          'reason': 'The target rejected this file.',
          'retryable': true,
        },
      ),
      'has_more': end < failedCount,
      if (end < failedCount) 'next_cursor': '$end',
    });
  }

  Future<void> _emitJob(Map<String, dynamic> job) async {
    final message = jsonEncode({
      'event_type': 'job_updated',
      'timestamp': _clock().toUtc().toIso8601String(),
      'payload': job,
    });
    for (final socket in List<WebSocket>.of(_eventSockets)) {
      try {
        socket.add(message);
      } catch (_) {
        _eventSockets.remove(socket);
      }
    }
  }

  Map<String, dynamic> _deviceStatus() => {
    'connection': {
      'device_id': deviceId,
      'device_name': 'K7 模拟盒子',
      'api_version': 'v1',
      'network_mode': 'manual',
      'signal_strength': 92,
      'is_paired': !requireAuthentication || _activeToken != null,
    },
    'card': {
      'inserted': true,
      'readable': true,
      'name': 'MOCK-SD',
    },
    'battery_percent': 78,
    'external_power': true,
    'temperature_celsius': 42.5,
    'storage_total': 512 * 1024 * 1024 * 1024,
    'storage_free': 338 * 1024 * 1024 * 1024,
    'software_version': 'mock-box-1.0.0',
    'model_version': 'bird-demo-1.0',
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  Map<String, dynamic> _currentBatch() {
    final keepCount = _photos.where((photo) => photo['keep_state'] == 'keep' || photo['keep_state'] == 'featured').length;
    final discardCount = _photos.where((photo) => photo['keep_state'] == 'discard').length;
    return {
      'project_id': 'mock-batch-current',
      'name': '2026.07.16 崇明东滩',
      'created_at': '2026-07-16T06:12:00Z',
      'total_files': photoCount,
      'analyzed_count': _photos.where((photo) => photo['analysis_state'] == 'completed').length,
      'pending_review_count': _photos.where((photo) => photo['keep_state'] == 'pending').length,
      'keep_count': keepCount,
      'discard_count': discardCount,
      'pending_copy_count': 0,
      'copy_state': 'idle',
      'scene_count': _scenes.length,
      'burst_group_count': _groups.length,
      'cover': _previewFor('kingfisher.png', height: 1536),
    };
  }

  List<Map<String, dynamic>> _historyBatches() => [
    {
      'project_id': 'mock-batch-history-01',
      'name': '杭州湾湿地',
      'created_at': '2026-07-10T06:30:00Z',
      'total_files': 2184,
      'analyzed_count': 2184,
      'pending_review_count': 0,
      'keep_count': 734,
      'discard_count': 1450,
      'pending_copy_count': 0,
      'copy_state': 'completed',
      'scene_count': 5,
      'burst_group_count': 82,
      'cover': _previewFor('sandpiper.png', height: 1792),
    },
    {
      'project_id': 'mock-batch-history-02',
      'name': '鄱阳湖',
      'created_at': '2026-06-28T05:50:00Z',
      'total_files': 5621,
      'analyzed_count': 5621,
      'pending_review_count': 0,
      'keep_count': 1812,
      'discard_count': 3809,
      'pending_copy_count': 0,
      'copy_state': 'completed',
      'scene_count': 7,
      'burst_group_count': 143,
      'cover': _previewFor('egret.png', height: 1536),
    },
  ];

  Map<String, dynamic> _photoPage(Map<String, String> query) {
    var items = _photos.where((photo) => _matches(photo, query)).toList(growable: false);
    items = [...items]..sort((left, right) => _compare(left, right, query['sort']));
    final pageSize = (int.tryParse(query['page_size'] ?? '') ?? 60).clamp(1, 200);
    final cursor = (int.tryParse(query['cursor'] ?? '') ?? 0).clamp(0, items.length);
    final end = min(cursor + pageSize, items.length);
    return {
      'items': items.sublist(cursor, end).map(_withFreshSignedReferences).toList(growable: false),
      'has_more': end < items.length,
      if (end < items.length) 'next_cursor': '$end',
    };
  }

  bool _matches(Map<String, dynamic> photo, Map<String, String> query) {
    bool same(String key, String field) {
      final expected = query[key];
      return expected == null || expected.isEmpty || photo[field]?.toString() == expected;
    }

    if (!same('keep_state', 'keep_state') || !same('analysis_state', 'analysis_state') || !same('clarity_state', 'clarity_state') || !same('group_id', 'group_id') || !same('scene_id', 'scene_id')) {
      return false;
    }
    final rating = Map<String, dynamic>.from(photo['rating'] as Map);
    final recognition = Map<String, dynamic>.from(photo['recognition'] as Map);
    final candidates = recognition['species_topn'] as List? ?? const [];
    final minScore = double.tryParse(query['min_score'] ?? '');
    if (minScore != null && (rating['total_score'] as num).toDouble() < minScore) return false;
    final minConfidence = double.tryParse(query['min_confidence'] ?? '');
    if (minConfidence != null && (candidates.isEmpty || ((candidates.first as Map)['confidence'] as num).toDouble() < minConfidence)) {
      return false;
    }
    if (query['recommended_only'] == 'true' && photo['is_recommended'] != true) return false;
    final recognitionState = query['recognition_state'];
    if (recognitionState == 'recognized' && (candidates.isEmpty || recognition['low_confidence'] == true)) return false;
    if (recognitionState == 'needs_review' && recognition['low_confidence'] != true) return false;
    if (recognitionState == 'unknown' && candidates.isNotEmpty) return false;

    final tags = (query['tags'] ?? '').split(',').where((tag) => tag.isNotEmpty);
    final photoTags = (photo['user_tags'] as List? ?? const []).map((tag) => tag.toString()).toSet();
    if (!tags.every(photoTags.contains)) return false;

    final search = (query['search'] ?? query['species'] ?? '').trim().toLowerCase();
    if (search.isNotEmpty) {
      final species = candidates.whereType<Map>().map((candidate) => candidate['name']).join(' ');
      final searchable = '${photo['filename']} $species ${photoTags.join(' ')}'.toLowerCase();
      if (!searchable.contains(search)) return false;
    }
    return true;
  }

  int _compare(Map<String, dynamic> left, Map<String, dynamic> right, String? sort) {
    double score(Map<String, dynamic> photo) => ((photo['rating'] as Map)['total_score'] as num).toDouble();
    double confidence(Map<String, dynamic> photo) {
      final candidates = ((photo['recognition'] as Map)['species_topn'] as List? ?? const []);
      return candidates.isEmpty ? -1 : ((candidates.first as Map)['confidence'] as num).toDouble();
    }

    return switch (sort) {
      'score_desc' => score(right).compareTo(score(left)),
      'confidence_desc' => confidence(right).compareTo(confidence(left)),
      'recommended_desc' => ((right['is_recommended'] == true ? 1 : 0).compareTo(left['is_recommended'] == true ? 1 : 0)),
      _ => right['captured_at'].toString().compareTo(left['captured_at'].toString()),
    };
  }

  Future<void> _serveDetail(HttpRequest request, String fileId) async {
    final photo = _photosById[fileId];
    if (photo == null) {
      await _notFound(request, 'Unknown file: $fileId');
      return;
    }
    final decision = _decisions.putIfAbsent(fileId, () => _initialDecision(photo));
    await _json(request, HttpStatus.ok, {
      'file': _withFreshSignedReferences(photo),
      'subjects': [
        {
          'bbox': {'x': .31, 'y': .18, 'width': .42, 'height': .58},
          'confidence': .94,
          'subject_type': 'bird',
        },
      ],
      'tags': [
        {'tag_id': 'wetland', 'tag_name': '湿地', 'source': 'system', 'editable': false},
        {'tag_id': 'bird', 'tag_name': '鸟类', 'source': 'system', 'editable': false},
      ],
      'exif': {
        'camera': 'Mock K7 Camera',
        'lens': '600mm F4',
        'shutter': '1/2000s',
        'aperture': 'f/5.6',
        'iso': 800,
        'focal_length': '600mm',
      },
      'decision': decision,
    });
  }

  Future<void> _serveHistory(HttpRequest request, String fileId) async {
    if (!_photosById.containsKey(fileId)) {
      await _notFound(request, 'Unknown file: $fileId');
      return;
    }
    final items = _history.putIfAbsent(
      fileId,
      () => [
        {
          'version': 1,
          'source': 'box',
          'updated_at': '2026-07-16T08:00:00Z',
          'summary': '盒子完成自动识别与评分',
        },
      ],
    );
    await _json(request, HttpStatus.ok, {'items': items});
  }

  Future<void> _saveDecision(HttpRequest request, String fileId) async {
    final photo = _photosById[fileId];
    if (photo == null) {
      await _notFound(request, 'Unknown file: $fileId');
      return;
    }
    final body = await _requestJson(request);
    final current = _decisions[fileId] ?? _initialDecision(photo);
    final requestedVersion = body['version'];
    final currentVersion = (current['version'] as num?)?.toInt() ?? 0;
    if (requestedVersion is! int) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'decision_version_required',
          'error_message': 'A review decision version is required.',
        },
        envelope: false,
      );
      return;
    }
    if (requestedVersion != currentVersion) {
      await _json(
        request,
        HttpStatus.conflict,
        {
          'error_code': 'decision_version_conflict',
          'error_message': 'The photo decision changed on the box. Reload before saving.',
          'details': {
            'requested_version': requestedVersion,
            'current_version': currentVersion,
          },
        },
        envelope: false,
      );
      return;
    }
    final version = currentVersion + 1;
    final updated = {
      ...current,
      ...body,
      'file_id': fileId,
      'version': version,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    _decisions[fileId] = updated;
    photo['keep_state'] = updated['keep_state'] ?? photo['keep_state'];
    photo['user_tags'] = updated['user_tags'] ?? photo['user_tags'];
    photo['version'] = version;
    final history = _history.putIfAbsent(fileId, () => []);
    history.add({
      'version': version,
      'source': 'app',
      'updated_at': updated['updated_at'],
      'summary': '用户更新照片审阅结果',
    });
    await _json(request, HttpStatus.ok, {'decision': updated});
  }

  Future<void> _applyBatchAction(HttpRequest request) async {
    final body = await _requestJson(request);
    final ids = (body['file_ids'] as List? ?? const []).map((id) => id.toString()).toList();
    final operation = body['operation']?.toString() ?? '';
    final value = body['value'];
    final succeeded = <String>[];
    final failed = <Map<String, dynamic>>[];
    for (final id in ids) {
      final photo = _photosById[id];
      if (photo == null) {
        failed.add({'file_id': id, 'reason': '照片不存在'});
        continue;
      }
      if (const {'pending', 'keep', 'discard', 'featured'}.contains(operation)) {
        photo['keep_state'] = operation;
      } else if (operation == 'add_tags' || operation == 'remove_tags') {
        final tags = (photo['user_tags'] as List? ?? const []).map((tag) => tag.toString()).toSet();
        final changed = (value as List? ?? const []).map((tag) => tag.toString());
        operation == 'add_tags' ? tags.addAll(changed) : tags.removeAll(changed);
        photo['user_tags'] = tags.toList(growable: false);
      } else {
        failed.add({'file_id': id, 'reason': '不支持的操作：$operation'});
        continue;
      }
      succeeded.add(id);
    }
    await _json(request, HttpStatus.ok, {
      'succeeded_ids': succeeded,
      'failed': failed,
    });
  }

  Future<void> _pair(HttpRequest request) async {
    lastPairAuthorizationHeader = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    final body = await _requestJson(request);
    if (body['pairing_code']?.toString() != pairingCode) {
      await _json(
        request,
        HttpStatus.forbidden,
        {
          'error_code': 'pairing_code_invalid',
          'error_message': '配对码无效或已过期。',
          'retryable': false,
        },
        envelope: false,
      );
      return;
    }
    final expiresAt = _clock().toUtc().add(tokenLifetime);
    final token = 'mock-access-$deviceId-${expiresAt.microsecondsSinceEpoch}';
    _activeToken = token;
    _tokenExpiresAt = expiresAt;
    await _json(request, HttpStatus.ok, {
      'access_token': token,
      'expires_at': expiresAt.toIso8601String(),
      'device_id': deviceId,
      'api_version': 'v1',
    });
  }

  Future<bool> _authorize(HttpRequest request) async {
    if (!requireAuthentication) return true;
    final authorization = request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization == null || authorization.isEmpty) {
      await _authenticationError(
        request,
        HttpStatus.unauthorized,
        'authorization_required',
      );
      return false;
    }
    if (authorization != 'Bearer $_activeToken' || _activeToken == null) {
      await _authenticationError(
        request,
        HttpStatus.forbidden,
        'authorization_invalid',
      );
      return false;
    }
    if (!_tokenExpiresAt!.isAfter(_clock().toUtc())) {
      await _authenticationError(
        request,
        HttpStatus.unauthorized,
        'authorization_expired',
      );
      return false;
    }
    return true;
  }

  Future<void> _authenticationError(
    HttpRequest request,
    int statusCode,
    String code,
  ) => _json(
    request,
    statusCode,
    {
      'error_code': code,
      'error_message': '设备授权无效，请重新配对。',
      'retryable': false,
    },
    envelope: false,
  );

  Future<void> _serveEvents(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      await _json(
        request,
        HttpStatus.badRequest,
        {
          'error_code': 'websocket_upgrade_required',
          'error_message': 'WebSocket upgrade required.',
        },
        envelope: false,
      );
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _eventSockets.add(socket);
    socket.add(
      jsonEncode({
        'event_type': 'device.status',
        'timestamp': _clock().toUtc().toIso8601String(),
        'payload': _deviceStatus(),
      }),
    );
    // Keep consuming frames without holding the server's request dispatcher;
    // REST and signed-asset requests must continue while WS is open.
    socket.listen(
      (_) {},
      onError: (_) => _eventSockets.remove(socket),
      onDone: () => _eventSockets.remove(socket),
    );
  }

  String _signedPath(String path) {
    if (!requireAuthentication) return path;
    final expires = _clock().toUtc().add(signedUrlLifetime).millisecondsSinceEpoch ~/ 1000;
    return Uri(
      path: path,
      queryParameters: {
        'expires': '$expires',
        'signature': 'mock-signed-v1',
      },
    ).toString();
  }

  Future<bool> _validateSignedRequest(HttpRequest request) async {
    if (!requireAuthentication) return true;
    final expires = int.tryParse(request.uri.queryParameters['expires'] ?? '');
    final signature = request.uri.queryParameters['signature'];
    if (expires == null || signature != 'mock-signed-v1') {
      await _authenticationError(
        request,
        HttpStatus.forbidden,
        'signed_url_invalid',
      );
      return false;
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expires * 1000,
      isUtc: true,
    );
    if (!expiresAt.isAfter(_clock().toUtc())) {
      await _authenticationError(
        request,
        HttpStatus.unauthorized,
        'signed_url_expired',
      );
      return false;
    }
    return true;
  }

  Future<void> _serveMedia(HttpRequest request) async {
    lastSignedAssetAuthorizationHeader = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (!await _validateSignedRequest(request)) return;
    final name = request.uri.pathSegments.last;
    if (!RegExp(r'^[a-z0-9_-]+\.png$').hasMatch(name)) {
      await _notFound(request, 'Unknown mock media: $name');
      return;
    }
    final file = File('${assetDirectory.path}${Platform.pathSeparator}$name');
    if (!await file.exists()) {
      await _notFound(request, 'Unknown mock media: $name');
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=3600');
    request.response.contentLength = await file.length();
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> _serveLog(HttpRequest request) async {
    lastSignedAssetAuthorizationHeader = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (!await _validateSignedRequest(request)) return;
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.text;
    request.response.headers.set(
      HttpHeaders.contentDisposition,
      'attachment; filename="bird-companion-diagnostics.txt"',
    );
    request.response.write('mock diagnostics\nstatus=ok\n');
    await request.response.close();
  }

  Map<String, dynamic> _buildPhoto(int zeroBasedIndex) {
    final number = zeroBasedIndex + 1;
    const assets = ['kingfisher.png', 'egret.png', 'warbler.png', 'sandpiper.png'];
    const species = [
      ('common-kingfisher', '普通翠鸟', 'Common Kingfisher'),
      ('little-egret', '白鹭', 'Little Egret'),
      ('oriental-reed-warbler', '东方大苇莺', 'Oriental Reed Warbler'),
      ('marsh-sandpiper', '泽鹬', 'Marsh Sandpiper'),
    ];
    final variant = zeroBasedIndex % assets.length;
    final sceneIndex = min(3, zeroBasedIndex * 4 ~/ photoCount);
    final groupIndex = zeroBasedIndex ~/ 14;
    final capturedAt = DateTime.utc(2026, 7, 16, 6, 12).add(Duration(seconds: zeroBasedIndex * 3));
    final totalScore = 3 + (zeroBasedIndex % 20) / 10;
    final confidence = .62 + (zeroBasedIndex % 35) / 100;
    final keepState = switch (zeroBasedIndex % 10) {
      0 => 'featured',
      1 || 2 => 'keep',
      3 => 'discard',
      _ => 'pending',
    };
    final analysisState = switch (zeroBasedIndex % 53) {
      0 => 'processing',
      _ when zeroBasedIndex % 47 == 0 => 'failed',
      _ when zeroBasedIndex % 11 == 0 => 'low_confidence',
      _ => 'completed',
    };
    final clarityState = zeroBasedIndex % 13 == 0
        ? 'blurred'
        : zeroBasedIndex % 7 == 0
        ? 'average'
        : 'clear';
    final noCandidate = zeroBasedIndex % 37 == 0;
    return {
      'file_id': 'photo-${number.toString().padLeft(4, '0')}',
      'filename': 'DSC_${number.toString().padLeft(4, '0')}.JPG',
      'format': 'JPEG',
      ..._previewFor(assets[variant], height: [1536, 1536, 1536, 1792][variant]),
      'analysis_state': analysisState,
      'recognition': {
        'species_topn': noCandidate
            ? const []
            : [
                {
                  'species_id': species[variant].$1,
                  'name': species[variant].$2,
                  'english_name': species[variant].$3,
                  'confidence': double.parse(confidence.toStringAsFixed(2)),
                },
              ],
        'low_confidence': analysisState == 'low_confidence' || confidence < .7,
        'model_version': 'bird-demo-1.0',
      },
      'rating': {
        'total_score': double.parse(totalScore.toStringAsFixed(1)),
        'quality_score': 7.8 + (zeroBasedIndex % 20) / 10,
        'eye_score': 7.6 + (zeroBasedIndex % 23) / 10,
        'composition_score': 7.5 + (zeroBasedIndex % 18) / 10,
        'reason_tags': ['鸟眼清晰', '主体完整', if (zeroBasedIndex.isEven) '构图自然'],
      },
      'group_id': 'group-${(groupIndex + 1).toString().padLeft(2, '0')}',
      'scene_id': 'scene-${sceneIndex + 1}',
      'keep_state': keepState,
      'clarity_state': clarityState,
      'is_recommended': zeroBasedIndex % 9 == 0,
      'user_tags': [if (variant == 0) '翠鸟', '湿地'],
      'captured_at': capturedAt.toIso8601String(),
      'version': 1,
    };
  }

  List<Map<String, dynamic>> _buildScenes() {
    const names = ['清晨芦苇荡', '潮滩水面', '林缘枝头', '返程沿线'];
    return List.generate(4, (index) {
      final photos = _photos.where((photo) => photo['scene_id'] == 'scene-${index + 1}').toList();
      return {
        'scene_id': 'scene-${index + 1}',
        'project_id': 'mock-batch-current',
        'name': names[index],
        'photo_count': photos.length,
        'burst_group_count': photos.map((photo) => photo['group_id']).toSet().length,
        'captured_from': photos.first['captured_at'],
        'captured_to': photos.last['captured_at'],
        'cover': {
          'thumb_ref': photos.first['thumb_ref'],
          'preview_ref': photos.first['preview_ref'],
          'width': photos.first['width'],
          'height': photos.first['height'],
        },
      };
    });
  }

  List<Map<String, dynamic>> _buildGroups() {
    final count = (photoCount / 14).ceil();
    return List.generate(count, (index) {
      final start = index * 14;
      final end = min(start + 14, _photos.length);
      final members = _photos.sublist(start, end);
      final ranked = [...members]
        ..sort(
          (left, right) => (((right['rating'] as Map)['total_score'] as num).compareTo((left['rating'] as Map)['total_score'] as num)),
        );
      return {
        'group_id': 'group-${(index + 1).toString().padLeft(2, '0')}',
        'group_type': 'burst',
        'representative_file_id': ranked.first['file_id'],
        'member_file_ids': members.map((photo) => photo['file_id']).toList(growable: false),
        'rank_order': ranked.map((photo) => photo['file_id']).toList(growable: false),
        'recommendation_reasons': const ['鸟眼清晰', '主体完整', '构图自然'],
        'scene_id': members.first['scene_id'],
        'captured_from': members.first['captured_at'],
        'captured_to': members.last['captured_at'],
      };
    });
  }

  Map<String, dynamic> _groupWithMembers(Map<String, dynamic> group) => {
    ...group,
    'members': (group['member_file_ids'] as List).map((id) => _photosById[id.toString()]).whereType<Map<String, dynamic>>().map(_withFreshSignedReferences).toList(growable: false),
  };

  Map<String, dynamic> _initialDecision(Map<String, dynamic> photo) {
    final candidates = ((photo['recognition'] as Map)['species_topn'] as List? ?? const []);
    final candidate = candidates.isEmpty ? null : Map<String, dynamic>.from(candidates.first as Map);
    return {
      'file_id': photo['file_id'],
      'keep_state': photo['keep_state'],
      'user_score': (photo['rating'] as Map)['total_score'],
      'user_species_id': candidate?['species_id'],
      'user_species': candidate?['name'],
      'user_tags': photo['user_tags'],
      'updated_at': '2026-07-16T08:00:00Z',
      'version': 1,
    };
  }

  List<Map<String, dynamic>> _speciesSearch(String? query) {
    final normalized = query?.trim().toLowerCase() ?? '';
    const items = [
      {'species_id': 'common-kingfisher', 'name': '普通翠鸟', 'english_name': 'Common Kingfisher', 'confidence': 1.0},
      {'species_id': 'little-egret', 'name': '白鹭', 'english_name': 'Little Egret', 'confidence': 1.0},
      {'species_id': 'oriental-reed-warbler', 'name': '东方大苇莺', 'english_name': 'Oriental Reed Warbler', 'confidence': 1.0},
      {'species_id': 'marsh-sandpiper', 'name': '泽鹬', 'english_name': 'Marsh Sandpiper', 'confidence': 1.0},
    ];
    if (normalized.isEmpty) return items;
    return items.where((item) => '${item['name']} ${item['english_name']}'.toLowerCase().contains(normalized)).toList(growable: false);
  }

  Map<String, dynamic> _previewFor(String asset, {required int height}) => {
    'thumb_ref': _signedPath('/mock/media/$asset'),
    'preview_ref': _signedPath('/mock/media/$asset'),
    'width': 1024,
    'height': height,
  };

  Map<String, dynamic> _withFreshSignedReferences(
    Map<String, dynamic> photo,
  ) => {
    ...photo,
    if (photo['thumb_ref'] case final String value) 'thumb_ref': _signedPath(Uri.parse(value).path),
    if (photo['preview_ref'] case final String value) 'preview_ref': _signedPath(Uri.parse(value).path),
  };

  bool _isKnownBatch(String value) => _createdProjects.containsKey(value) || value == 'mock-batch-current' || value.startsWith('mock-batch-history-');

  Future<Map<String, dynamic>> _requestJson(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) return {};
    final value = jsonDecode(raw);
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  Future<void> _notFound(HttpRequest request, String message) => _json(
    request,
    HttpStatus.notFound,
    {
      'error_code': 'not_found',
      'error_message': message,
    },
    envelope: false,
  );

  Future<void> _json(
    HttpRequest request,
    int statusCode,
    Object payload, {
    bool envelope = true,
  }) async {
    final body = jsonEncode(envelope ? {'data': payload} : payload);
    final cacheKey = _idempotencyByRequest.remove(request);
    if (cacheKey != null) {
      final cached = _CachedHttpResponse(statusCode, body);
      _idempotentResponses[cacheKey] = cached;
      _idempotentInFlight.remove(cacheKey)?.complete(cached);
      await _persistState();
    }
    await _sendCachedResponse(
      request,
      _CachedHttpResponse(statusCode, body),
    );
  }

  Future<bool> _replayOrRegisterIdempotent(HttpRequest request) async {
    final key = request.headers.value('X-Idempotency-Key')?.trim();
    if (key == null || key.length < 8) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'idempotency_key_required',
          'error_message': 'X-Idempotency-Key must contain at least 8 characters.',
        },
        envelope: false,
      );
      return true;
    }
    final cacheKey = '${request.method} ${request.uri.path} $key';
    final cached = _idempotentResponses[cacheKey];
    if (cached != null) {
      await _sendCachedResponse(request, cached);
      return true;
    }
    final pending = _idempotentInFlight[cacheKey];
    if (pending != null) {
      await _sendCachedResponse(request, await pending.future);
      return true;
    }
    _idempotentInFlight[cacheKey] = Completer<_CachedHttpResponse>();
    _idempotencyByRequest[request] = cacheKey;
    return false;
  }

  Future<void> _sendCachedResponse(
    HttpRequest request,
    _CachedHttpResponse cached,
  ) async {
    request.response.statusCode = cached.statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(cached.body);
    await request.response.close();
  }

  void _restoreState() {
    final file = stateFile;
    if (file == null || !file.existsSync()) return;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map || decoded['schema_version'] != 1) {
      throw const FormatException('Unsupported mock state schema.');
    }
    final state = Map<String, dynamic>.from(decoded);
    _projectSequence = (state['project_sequence'] as num?)?.toInt() ?? 0;
    _jobSequence = (state['job_sequence'] as num?)?.toInt() ?? 0;
    _currentCreatedProjectId = state['current_created_project_id']?.toString();
    _restoreMapOfMaps(state['created_projects'], _createdProjects);
    _restoreMapOfMaps(state['jobs'], _jobs);
    _restoreMapOfMaps(state['decisions'], _decisions);
    final history = state['history'];
    if (history is Map) {
      for (final entry in history.entries) {
        final items = entry.value;
        if (items is List) {
          _history[entry.key.toString()] = items.whereType<Map>().map(Map<String, dynamic>.from).toList();
        }
      }
    }
    final photoOverrides = state['photo_overrides'];
    if (photoOverrides is Map) {
      for (final entry in photoOverrides.entries) {
        final photo = _photosById[entry.key.toString()];
        final override = entry.value;
        if (photo != null && override is Map) {
          photo.addAll(Map<String, dynamic>.from(override));
        }
      }
    }
    final idempotentResponses = state['idempotent_responses'];
    if (idempotentResponses is Map) {
      for (final entry in idempotentResponses.entries) {
        final value = entry.value;
        if (value is Map && value['status_code'] is num && value['body'] is String) {
          _idempotentResponses[entry.key.toString()] = _CachedHttpResponse(
            (value['status_code'] as num).toInt(),
            value['body'] as String,
          );
        }
      }
    }
  }

  void _restoreMapOfMaps(
    Object? source,
    Map<String, Map<String, dynamic>> target,
  ) {
    if (source is! Map) return;
    for (final entry in source.entries) {
      if (entry.value is Map) {
        target[entry.key.toString()] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }
  }

  Future<void> _persistState() async {
    final file = stateFile;
    if (file == null) return;
    final snapshot = <String, dynamic>{
      'schema_version': 1,
      'project_sequence': _projectSequence,
      'job_sequence': _jobSequence,
      'current_created_project_id': _currentCreatedProjectId,
      'created_projects': _createdProjects,
      'jobs': _jobs,
      'decisions': _decisions,
      'history': _history,
      'photo_overrides': {
        for (final photo in _photos)
          photo['file_id'].toString(): {
            'keep_state': photo['keep_state'],
            'user_tags': photo['user_tags'],
            'version': photo['version'],
          },
      },
      'idempotent_responses': {
        for (final entry in _idempotentResponses.entries)
          if (!entry.key.contains('/api/v1/device/pair'))
            entry.key: {
              'status_code': entry.value.statusCode,
              'body': entry.value.body,
            },
      },
    };
    _stateWrite = _stateWrite.then((_) async {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(snapshot), flush: true);
    });
    await _stateWrite;
  }

  void _cors(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS');
    response.headers.set(HttpHeaders.accessControlAllowHeadersHeader, 'Content-Type, Authorization, X-Api-Version, X-Idempotency-Key');
  }
}

class _CachedHttpResponse {
  const _CachedHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
