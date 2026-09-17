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
    this.pairingSessionId = 'ps_mock_pairing_session',
    this.tokenLifetime = const Duration(minutes: 10),
    this.signedUrlLifetime = const Duration(minutes: 2),
    this.progressiveMedia = false,
    this.emitAssetReadyEvents = true,
    this.stateFile,
    void Function(String message)? requestLogSink,
    DateTime Function()? clock,
  }) : assetDirectory = assetDirectory ?? Directory('tool/mock_box_server/assets'),
       requestLogSink = requestLogSink ?? ((message) => stdout.writeln(message)) {
    _clock = clock ?? DateTime.now;
    _assetEventsEnabled = emitAssetReadyEvents;
    if (photoCount <= 0) {
      throw ArgumentError.value(photoCount, 'photoCount', '必须大于 0');
    }
    _photos = List.generate(photoCount, _buildPhoto, growable: false);
    _photosById = {for (final photo in _photos) photo['file_id'] as String: photo};
    _photoAssetNames = {
      for (final photo in _photos) photo['file_id'] as String: Uri.parse(photo['thumb_ref'] as String).pathSegments.last,
    };
    if (progressiveMedia) _initializeProgressiveMedia();
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
  final String pairingSessionId;
  final Duration tokenLifetime;
  final Duration signedUrlLifetime;
  final bool progressiveMedia;
  final bool emitAssetReadyEvents;
  final File? stateFile;
  final void Function(String message) requestLogSink;
  late final DateTime Function() _clock;

  late final List<Map<String, dynamic>> _photos;
  late final Map<String, Map<String, dynamic>> _photosById;
  late final Map<String, String> _photoAssetNames;
  late final List<Map<String, dynamic>> _scenes;
  late final List<Map<String, dynamic>> _groups;
  final Map<String, Map<String, dynamic>> _decisions = {};
  final Map<String, List<Map<String, dynamic>>> _history = {};
  final Map<String, Map<String, dynamic>> _createdProjects = {};
  final Map<String, Map<String, dynamic>> _jobs = {};
  // birdbox-copy-v1 RC3 任务闭环内存态（§13.5/§13.6）：copy 任务不进通用
  // /api/v1/jobs 表（审计 P0-3），独立存储、惰性时间推进。
  final Map<String, Map<String, dynamic>> _copyJobsV1 = {};
  final Map<String, List<Map<String, dynamic>>> _previewItemsByToken = {};
  final Map<String, String> _safeRemovedDevicesV1 = {};
  final Map<String, _CachedHttpResponse> _idempotentResponses = {};
  final Map<String, Completer<_CachedHttpResponse>> _idempotentInFlight = {};
  final Map<HttpRequest, String> _idempotencyByRequest = {};
  final Set<WebSocket> _eventSockets = {};
  final Map<String, int> _assetRevisions = {};
  Future<void> _stateWrite = Future<void>.value();
  String? _currentCreatedProjectId;
  bool _currentProjectAvailable = true;
  int _projectSequence = 0;
  int _jobSequence = 0;
  String? _activeToken;
  DateTime? _tokenExpiresAt;
  String? lastPairAuthorizationHeader;
  String? lastRc4PairingClientId;
  bool lastRc4PairingIncludedCode = false;
  String? lastSignedAssetAuthorizationHeader;
  int jobListRequestCount = 0;
  int _eventSequence = 0;
  late bool _assetEventsEnabled;
  bool _pairingSessionConsumed = false;

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

  Future<void> setMediaAssetStatus(
    String fileId,
    String kind,
    String status, {
    bool emitEvent = true,
  }) async {
    if (!progressiveMedia) {
      throw StateError('Progressive media is not enabled.');
    }
    if (!const {'thumbnail', 'preview'}.contains(kind)) {
      throw ArgumentError.value(kind, 'kind', 'Unknown media kind.');
    }
    if (!const {
      'not_requested',
      'pending',
      'ready',
      'failed',
    }.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Unknown media status.');
    }
    final photo = _photosById[fileId];
    if (photo == null) {
      throw ArgumentError.value(fileId, 'fileId', 'Unknown photo.');
    }
    photo[_statusField(kind)] = status;
    if (status == 'ready') {
      final key = _assetKey(fileId, kind);
      _assetRevisions[key] = (_assetRevisions[key] ?? 0) + 1;
      if (emitEvent && _assetEventsEnabled) {
        await _emitAssetReady(fileId, kind);
      }
    }
  }

  Future<void> setAssetEventsEnabled(bool enabled) async {
    _assetEventsEnabled = enabled;
    if (enabled) return;
    for (final socket in List<WebSocket>.of(_eventSockets)) {
      await socket.close();
    }
    _eventSockets.clear();
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
          // Never print the raw exception value. URI and decoding exceptions can
          // contain request material, including short-lived credentials.
          stderr.writeln(
            'Mock box request failed: ${error.runtimeType}\n$stackTrace',
          );
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
      requestLogSink('${request.method} ${request.uri.path}');
    }
    _cors(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final method = request.method;
    final path = request.uri.path;

    if (method == 'GET' && path == '/health') {
      await _json(
        request,
        HttpStatus.ok,
        {
          'status': 'ok',
          'device_id': deviceId,
          'protocol_version': '1.0-rc4',
          'api_version': 'v1',
          'active_mode': 'direct_ap',
          'server_time': _clock().toUtc().toIso8601String(),
        },
        envelope: false,
      );
      return;
    }
    if (method == 'GET' && path == '/healthz') {
      await _json(request, HttpStatus.ok, {
        'status': 'ok',
        'photos': photoCount,
        'progressive_media': progressiveMedia,
      });
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
    if (method == 'POST' && path == '/api/v1/pairing') {
      if (await _replayOrRegisterIdempotent(request)) return;
      await _exchangePairingSession(request);
      return;
    }
    if (method == 'POST' && path == '/mock/control/assets' && progressiveMedia) {
      await _controlMediaAsset(request);
      return;
    }
    if (method == 'POST' && path == '/mock/control/events' && progressiveMedia) {
      final body = await _requestJson(request);
      final enabled = body['enabled'];
      if (enabled is! bool) {
        await _json(
          request,
          HttpStatus.unprocessableEntity,
          {
            'error_code': 'mock_control_invalid',
            'error_message': 'enabled must be a boolean.',
          },
          envelope: false,
        );
        return;
      }
      await setAssetEventsEnabled(enabled);
      await _json(request, HttpStatus.ok, {'enabled': enabled});
      return;
    }
    if (method == 'GET' && path.startsWith('/mock/media/')) {
      await _serveMedia(request);
      return;
    }
    final progressiveAsset = RegExp(
      r'^/api/v1/files/([^/]+)/(thumbnail|preview)$',
    ).firstMatch(path);
    if (method == 'GET' && progressiveAsset != null && progressiveMedia) {
      await _serveProgressiveMedia(
        request,
        progressiveAsset.group(1)!,
        progressiveAsset.group(2)!,
      );
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
      await _json(
        request,
        HttpStatus.ok,
        _projectPage(request.uri.queryParameters),
      );
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
    // birdbox-copy-v1 endpoints (拍鸟盒子_复制全量备份与多存储设备三端协议).
    if (method == 'GET' && path == '/api/v1/storage/devices') {
      await _serveStorageDevices(request);
      return;
    }
    if (method == 'POST' && path == '/api/v1/copy-jobs/preview') {
      await _serveCopyJobPreview(request);
      return;
    }
    if (method == 'POST' && path == '/api/v1/copy-jobs') {
      await _createCopyV1Job(request);
      return;
    }
    // RC3 任务闭环（§13.5/§13.6）。
    if (method == 'GET' && path == '/api/v1/copy-capabilities') {
      await _serveCopyCapabilities(request);
      return;
    }
    if (method == 'GET' && path == '/api/v1/copy-jobs') {
      await _serveCopyJobList(request);
      return;
    }
    final copyPreviewItems = RegExp(
      r'^/api/v1/copy-previews/([^/]+)/items$',
    ).firstMatch(path);
    if (method == 'GET' && copyPreviewItems != null) {
      await _serveCopyPreviewItems(request, copyPreviewItems.group(1)!);
      return;
    }
    final copyJobItems = RegExp(r'^/api/v1/copy-jobs/([^/]+)/items$').firstMatch(path);
    if (method == 'GET' && copyJobItems != null) {
      await _serveCopyJobItems(request, copyJobItems.group(1)!);
      return;
    }
    final copyJobEvents = RegExp(r'^/api/v1/copy-jobs/([^/]+)/events$').firstMatch(path);
    if (method == 'GET' && copyJobEvents != null) {
      await _serveCopyJobEvents(request, copyJobEvents.group(1)!);
      return;
    }
    final copyJobReport = RegExp(r'^/api/v1/copy-jobs/([^/]+)/report$').firstMatch(path);
    if (method == 'GET' && copyJobReport != null) {
      await _serveCopyJobReport(request, copyJobReport.group(1)!);
      return;
    }
    final copyJobAction = RegExp(
      r'^/api/v1/copy-jobs/([^/]+)/actions/([^/]+)$',
    ).firstMatch(path);
    if (method == 'POST' && copyJobAction != null) {
      await _copyJobActionV1(request, copyJobAction.group(1)!, copyJobAction.group(2)!);
      return;
    }
    final safeRemove = RegExp(
      r'^/api/v1/storage/devices/([^/]+)/safe-remove$',
    ).firstMatch(path);
    if (method == 'POST' && safeRemove != null) {
      await _serveSafeRemove(request, safeRemove.group(1)!);
      return;
    }
    final copyJobDetailV1 = RegExp(r'^/api/v1/copy-jobs/([^/]+)$').firstMatch(path);
    if (method == 'GET' && copyJobDetailV1 != null) {
      await _serveCopyJobDetail(request, copyJobDetailV1.group(1)!);
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

  Future<void> _serveStorageDevices(HttpRequest request) async {
    await _json(request, HttpStatus.ok, {
      'devices': [
        {
          'media_id': 'media_2d6dee77bb5ecc73e3d34787',
          'display_name': '相机卡（读卡器）',
          'kind': 'card_reader',
          'kind_confidence': 'high',
          'detail': '双逻辑槽位读卡器 · 119.2 GB · EXFAT',
          'capacity_bytes': 128000000000,
          'free_bytes': 96400000000,
          'filesystem': 'exfat',
          'label': '',
          'role_state': 'available',
          'can_be_source': true,
          'can_be_target': false,
          'target_block_reasons': ['当前任务源设备'],
          'identity_confidence': 'stable_uuid',
          'last_seen_at': _clock().toIso8601String(),
        },
        {
          'media_id': 'media_7f9a76e6c97690b61aedf6fd',
          'display_name': 'U 盘 Ee',
          'kind': 'usb_flash',
          'kind_confidence': 'medium',
          'detail': 'SanDisk Ultra USB 3.0 · 28.7 GB · EXFAT',
          'capacity_bytes': 30765203456,
          'free_bytes': 30500000000,
          'filesystem': 'exfat',
          'label': 'Ee',
          'role_state': 'available',
          'can_be_source': false,
          'can_be_target': true,
          'target_block_reasons': <String>[],
          'identity_confidence': 'stable_uuid',
          'last_seen_at': _clock().toIso8601String(),
        },
      ],
    });
  }

  Future<void> _serveCopyJobPreview(HttpRequest request) async {
    final body = await _requestJson(request);
    final scope = body['scope']?.toString();
    if (!const {
      'selected_assets',
      'filtered_assets',
      'recognized_assets',
      'kept_assets',
      'batch_all_assets',
      'media_full_backup',
    }.contains(scope)) {
      await _copyV1Error(request, HttpStatus.unprocessableEntity, 'COPY_SCOPE_INVALID');
      return;
    }
    // 镜像真实后端（联调 01 §二 P0-2）：全量备份未开放，预检直接拒绝。
    if (scope == 'media_full_backup') {
      await _copyV1Error(request, HttpStatus.unprocessableEntity, 'COPY_SCOPE_UNSUPPORTED');
      return;
    }
    if (body['conflict_strategy'] == null) {
      await _copyV1Error(request, HttpStatus.unprocessableEntity, 'COPY_CONFLICT_STRATEGY_REQUIRED');
      return;
    }
    final logical = switch (scope) {
      'kept_assets' => 34,
      'batch_all_assets' => 120,
      'filtered_assets' => 21,
      'recognized_assets' => 47,
      _ => (body['selection_id']?.toString().length ?? 4) % 9 + 2,
    };
    final files = logical * 2 - 1;
    final previewToken = 'preview_mock_${_clock().millisecondsSinceEpoch}';
    _previewItemsByToken[previewToken] = [
      for (var i = 0; i < files; i++)
        {
          'copy_item_id': 'item_${i.toString().padLeft(4, '0')}',
          'source_relative_path': 'DCIM/100MSDCF/DSC0${5000 + i}',
          'source_size': 28 * 1024 * 1024,
          'source_mtime_ns': 1726000000000000000 + i * 1000000000,
          'target_relative_directory': '20260901',
          'target_filename': 'DSC0${5000 + i}${i.isEven ? '.ARW' : '.JPG'}',
          'state': 'pending',
          if (i < 3) 'conflict_decision': 'skip',
        },
    ];
    await _json(request, HttpStatus.ok, {
      'preview_token': previewToken,
      'expires_at': _clock().add(const Duration(minutes: 15)).toIso8601String(),
      'source': _mockCameraDevice(),
      'target': _mockUsbDevice(),
      'logical_photo_count': logical,
      'actual_file_count': files,
      'total_bytes': files * 24 * 1024 * 1024,
      'raw_count': logical,
      'jpeg_count': logical - 1,
      'video_count': 0,
      'companion_count': 2,
      'estimated_date_directories': 2,
      'conflict_count': 3,
      'target_free_bytes': 30500000000,
      'safety_reserve_bytes': 1538260172,
      'unsupported_count': 0,
      'missing_count': 1,
    });
  }

  Future<void> _createCopyV1Job(HttpRequest request) async {
    final body = await _requestJson(request);
    if (body['conflict_strategy'] == null) {
      await _copyV1Error(request, HttpStatus.unprocessableEntity, 'COPY_CONFLICT_STRATEGY_REQUIRED');
      return;
    }
    final previewToken = body['preview_token']?.toString();
    if (previewToken == null || body['scope'] == null) {
      // 协议 §15：COPY_PREVIEW_EXPIRED 为 409 可重试（非 422）。
      await _copyV1Error(request, HttpStatus.conflict, 'COPY_PREVIEW_EXPIRED');
      return;
    }
    // RC3 任务固定 2 个文件项（第 2 项校验失败），演示「部分完成 + 失败项重试」。
    final now = _clock();
    final jobId = 'copy_job_${now.millisecondsSinceEpoch}';
    final job = <String, dynamic>{
      'copy_job_id': jobId,
      'state': 'queued',
      'state_version': 1,
      'event_seq': 1,
      'scope': body['scope']?.toString(),
      'batch_id': body['batch_id']?.toString(),
      'selection_id': body['selection_id']?.toString(),
      'created_at': now.toIso8601String(),
      'started_at': null,
      'finished_at': null,
      'phase_started_at': now.toIso8601String(),
      'running_active_ms': 0,
      'running_last_tick': null,
      'source_device': _mockCameraDevice(),
      'target_device': _mockUsbDevice(),
      'items': <Map<String, dynamic>>[
        _copyJobItemWire('copy_item_0001', 'DSC05001.ARW', willFail: false),
        _copyJobItemWire('copy_item_0002', 'DSC05002.JPG', willFail: true),
      ],
      'events': <Map<String, dynamic>>[
        {
          'seq': 1,
          'type': 'job_created',
          'message': '复制任务已创建',
          'created_at': now.toIso8601String(),
        },
      ],
    };
    _copyJobsV1[jobId] = job;
    await _json(request, HttpStatus.accepted, {
      'copy_job_id': jobId,
      'state': job['state'],
      'event_seq': job['event_seq'],
      'created_at': job['created_at'],
    });
  }

  Map<String, dynamic> _mockCameraDevice() => {
    'media_id': 'media_2d6dee77bb5ecc73e3d34787',
    'display_name': '相机卡（读卡器）',
    'kind': 'card_reader',
    'kind_confidence': 'high',
    'detail': '双逻辑槽位读卡器 · 119.2 GB · EXFAT',
    'capacity_bytes': 128000000000,
    'free_bytes': 96400000000,
    'filesystem': 'exfat',
    'label': '',
    'role_state': 'available',
    'can_be_source': true,
    'can_be_target': false,
    'target_block_reasons': ['当前任务源设备'],
    'identity_confidence': 'stable_uuid',
  };

  Map<String, dynamic> _mockUsbDevice() => {
    'media_id': 'media_7f9a76e6c97690b61aedf6fd',
    'display_name': 'U 盘 Ee',
    'kind': 'usb_flash',
    'kind_confidence': 'medium',
    'detail': 'SanDisk Ultra USB 3.0 · 28.7 GB · EXFAT',
    'capacity_bytes': 30765203456,
    'free_bytes': 30500000000,
    'filesystem': 'exfat',
    'label': 'Ee',
    'role_state': 'available',
    'can_be_source': false,
    'can_be_target': true,
    'target_block_reasons': <String>[],
    'identity_confidence': 'stable_uuid',
  };

  /// 协议 §13.1 错误包络：{"request_id","error":{code,message,details}}。
  Future<void> _copyV1Error(
    HttpRequest request,
    int status,
    String code,
  ) => _json(
    request,
    status,
    {
      'request_id': 'req_${_clock().millisecondsSinceEpoch}',
      'error': {
        'code': code,
        'message': 'The copy request does not match birdbox-copy-v1.',
        'details': <String, dynamic>{},
      },
    },
    envelope: false,
  );

  // ---- RC3 任务闭环（§13.5/§13.6，惰性时间推进，与 MockCopyRepository 同节奏）----

  Map<String, dynamic> _copyJobItemWire(
    String id,
    String filename, {
    required bool willFail,
  }) => {
    'copy_item_id': id,
    'source_relative_path': 'DCIM/100MSDCF/${filename.replaceAll(RegExp(r'\.\w+$'), '')}',
    'source_size': 28 * 1024 * 1024,
    'source_mtime_ns': 1726000000000000000,
    'target_relative_directory': '20260901',
    'target_filename': filename,
    'state': 'pending',
    'will_fail': willFail,
  };

  Future<void> _serveCopyCapabilities(HttpRequest request) async {
    await _json(request, HttpStatus.ok, {
      'revision': '1.0-rc3',
      'copy_ready': true,
      'supported_scopes': [
        'selected_assets',
        'filtered_assets',
        'recognized_assets',
        'batch_all_assets',
        'media_full_backup',
      ],
      'recognition_policy_version': 'recognized-assets-v1',
      'missing_requirements': <String>[],
    });
  }

  Future<void> _serveCopyJobList(HttpRequest request) async {
    final jobs = _copyJobsV1.values.toList()
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    await _json(request, HttpStatus.ok, {
      'items': [
        for (final job in jobs) _copyJobListEntry(job),
      ],
      'has_more': false,
    });
  }

  Map<String, dynamic> _copyJobListEntry(Map<String, dynamic> job) => {
    'copy_job_id': job['copy_job_id'],
    'state': job['state'],
    'scope': job['scope'],
    'stats': _copyJobStatsWire(job),
    'created_at': job['created_at'],
  };

  Future<void> _serveCopyJobDetail(HttpRequest request, String copyJobId) async {
    final job = _requireCopyJobV1(request, copyJobId);
    if (job == null) return;
    await _json(request, HttpStatus.ok, _copyJobDetailWire(job));
  }

  Future<void> _serveCopyJobItems(HttpRequest request, String copyJobId) async {
    final job = _requireCopyJobV1(request, copyJobId);
    if (job == null) return;
    final state = request.uri.queryParameters['state'];
    var items = (job['items'] as List<Map<String, dynamic>>).toList();
    if (state != null && state.isNotEmpty) {
      items = items.where((item) => item['state'] == state).toList();
    }
    final cursor = int.tryParse(request.uri.queryParameters['cursor'] ?? '') ?? 0;
    final page = items.skip(cursor).take(20).toList();
    final hasMore = cursor + page.length < items.length;
    await _json(request, HttpStatus.ok, {
      'items': [for (final item in page) _copyItemPublicWire(item)],
      'has_more': hasMore,
      if (hasMore) 'next_cursor': '${cursor + page.length}',
    });
  }

  Future<void> _serveCopyPreviewItems(HttpRequest request, String previewId) async {
    final items = _previewItemsByToken[previewId];
    if (items == null) {
      await _copyV1Error(request, HttpStatus.notFound, 'COPY_PREVIEW_EXPIRED');
      return;
    }
    final cursor = int.tryParse(request.uri.queryParameters['cursor'] ?? '') ?? 0;
    final page = items.skip(cursor).take(20).toList();
    final hasMore = cursor + page.length < items.length;
    await _json(request, HttpStatus.ok, {
      'items': page,
      'has_more': hasMore,
      if (hasMore) 'next_cursor': '${cursor + page.length}',
    });
  }

  Future<void> _serveCopyJobEvents(HttpRequest request, String copyJobId) async {
    final job = _requireCopyJobV1(request, copyJobId);
    if (job == null) return;
    final afterSeq = int.tryParse(request.uri.queryParameters['after_seq'] ?? '') ?? 0;
    final events = (job['events'] as List<Map<String, dynamic>>)
        .where((event) => (event['seq'] as int) > afterSeq)
        .toList();
    await _json(request, HttpStatus.ok, {'events': events, 'has_more': false});
  }

  Future<void> _serveCopyJobReport(HttpRequest request, String copyJobId) async {
    final job = _requireCopyJobV1(request, copyJobId);
    if (job == null) return;
    if (!_copyJobIsTerminal(job['state'] as String)) {
      await _copyV1Error(request, HttpStatus.conflict, 'COPY_REPORT_NOT_READY');
      return;
    }
    final stats = _copyJobStatsWire(job);
    await _json(request, HttpStatus.ok, {
      'copy_job_id': job['copy_job_id'],
      'selection_id': job['selection_id'],
      'actual_file_count': stats['total_files'],
      'copied_files': stats['copied_files'],
      'failed_files': stats['failed_files'],
      'skipped_files': stats['skipped_files'],
      'not_applicable_files': stats['not_applicable_files'],
      'total_bytes': stats['total_bytes'],
      'copied_bytes': stats['copied_bytes'],
      'elapsed_seconds': stats['elapsed_seconds'],
      'bytes_per_second': stats['bytes_per_second'],
      'source_device': job['source_device'],
      'target_device': job['target_device'],
      'generated_at': _clock().toIso8601String(),
    });
  }

  Future<void> _copyJobActionV1(
    HttpRequest request,
    String copyJobId,
    String action,
  ) async {
    final job = _requireCopyJobV1(request, copyJobId);
    if (job == null) return;
    final body = await _requestJson(request);
    final expected = body['expected_state_version'];
    if (expected is! int || expected != job['state_version']) {
      await _copyV1Error(request, HttpStatus.conflict, 'COPY_STATE_VERSION_CONFLICT');
      return;
    }
    final now = _clock();
    final state = job['state'] as String;
    switch (action) {
      case 'pause':
        if (state == 'running' || state == 'acquiring_target') {
          _copyJobTransition(job, 'pause_requested', now, '已请求暂停，当前文件完成后暂停');
        }
      case 'resume':
        if (state == 'paused') {
          _copyJobTransition(job, 'running', now, '任务已继续');
          job['running_last_tick'] = now.toIso8601String();
        }
      case 'cancel':
        if (!_copyJobIsTerminal(state)) {
          _copyJobTransition(job, 'cancel_requested', now, '已请求取消，已完成的副本不会删除');
        }
      case 'retry_failed':
        if (state == 'failed' || state == 'completed_with_errors') {
          for (final item in job['items'] as List<Map<String, dynamic>>) {
            if (item['state'] == 'failed') {
              item['state'] = 'pending';
              item['entered_at_ms'] = 0;
            }
          }
          job['running_active_ms'] = 0;
          job['item_start_ms'] = 0;
          _copyJobTransition(job, 'running', now, '已开始重试失败项');
          job['running_last_tick'] = now.toIso8601String();
        }
      case 'safe_remove_source' || 'safe_remove_target':
        // App 走 safe-remove 端点；动作路由仅做版本校验兜底。
        break;
      default:
        await _copyV1Error(request, HttpStatus.unprocessableEntity, 'COPY_ACTION_UNSUPPORTED');
        return;
    }
    await _json(request, HttpStatus.ok, {'copy_job': _copyJobDetailWire(job)});
  }

  Future<void> _serveSafeRemove(HttpRequest request, String mediaId) async {
    final body = await _requestJson(request);
    final role = body['role']?.toString() ?? 'target';
    // 有进行中的任务占用该设备时不得拔出（§4.5 安全移除条件）。
    final busy = _copyJobsV1.values.any((job) {
      if (_copyJobIsTerminal(job['state'] as String)) return false;
      final source = (job['source_device'] as Map<String, dynamic>)['media_id'];
      final target = (job['target_device'] as Map<String, dynamic>)['media_id'];
      return source == mediaId || target == mediaId;
    });
    if (busy) {
      await _json(request, HttpStatus.ok, {
        'safe_to_remove': false,
        'reason': '有复制任务正在使用该设备，任务结束后再移除',
      });
      return;
    }
    _safeRemovedDevicesV1[mediaId] = role;
    await _json(request, HttpStatus.ok, {
      'safe_to_remove': true,
      'keep_until': _clock().add(const Duration(seconds: 60)).toIso8601String(),
    });
  }

  Map<String, dynamic>? _requireCopyJobV1(HttpRequest request, String copyJobId) {
    final job = _copyJobsV1[copyJobId];
    if (job == null) {
      _copyV1Error(request, HttpStatus.notFound, 'COPY_JOB_NOT_FOUND');
      return null;
    }
    _advanceCopyJob(job, _clock());
    return job;
  }

  Map<String, dynamic> _copyJobDetailWire(Map<String, dynamic> job) => {
    'copy_job_id': job['copy_job_id'],
    'state': job['state'],
    'state_version': job['state_version'],
    'event_seq': job['event_seq'],
    'scope': job['scope'],
    'batch_id': job['batch_id'],
    'selection_id': job['selection_id'],
    'stats': _copyJobStatsWire(job),
    'source_device': job['source_device'],
    'target_device': job['target_device'],
    'allowed_actions': _copyJobAllowedActions(job['state'] as String)
        .map((action) => action)
        .toList(growable: false),
    'created_at': job['created_at'],
    'started_at': job['started_at'],
    'finished_at': job['finished_at'],
  };

  List<String> _copyJobAllowedActions(String state) => switch (state) {
    'running' || 'acquiring_target' => ['pause', 'cancel'],
    'paused' => ['resume', 'cancel'],
    'pause_requested' || 'cancel_requested' => <String>[],
    'failed' || 'completed_with_errors' => ['retry_failed'],
    'cancelled' || 'completed' => ['safe_remove_target'],
    _ => ['cancel'],
  };

  Map<String, dynamic> _copyJobStatsWire(Map<String, dynamic> job) {
    var copied = 0;
    var failed = 0;
    for (final item in job['items'] as List<Map<String, dynamic>>) {
      if (item['state'] == 'copied') copied++;
      if (item['state'] == 'failed') failed++;
    }
    final total = (job['items'] as List).length;
    const itemBytes = 28 * 1024 * 1024;
    final state = job['state'] as String;
    final startedAt = job['started_at'] as String?;
    final now = _clock();
    return {
      'total_files': total,
      'copied_files': copied,
      'failed_files': failed,
      'skipped_files': 0,
      'not_applicable_files': 0,
      'total_bytes': total * itemBytes,
      'copied_bytes': copied * itemBytes,
      'elapsed_seconds': startedAt == null ? null : now.difference(DateTime.parse(startedAt)).inSeconds,
      'eta_seconds': _copyJobIsTerminal(state) || total == 0 ? null : max(total - copied - failed, 1) * 2,
      'bytes_per_second': state == 'running' ? itemBytes ~/ 2 : null,
      'current_file': state == 'running'
          ? (job['items'] as List<Map<String, dynamic>>)
              .firstWhere(
                (item) => item['state'] == 'copying' || item['state'] == 'verifying',
                orElse: () => (job['items'] as List<Map<String, dynamic>>).first,
              )['target_filename']
          : null,
      'progress_percent': total == 0 ? null : (copied + failed) / total,
    };
  }

  bool _copyJobIsTerminal(String state) =>
      state == 'completed' || state == 'completed_with_errors' || state == 'cancelled' || state == 'failed';

  void _copyJobTransition(
    Map<String, dynamic> job,
    String next,
    DateTime now,
    String message,
  ) {
    job['state'] = next;
    job['state_version'] = (job['state_version'] as int) + 1;
    job['phase_started_at'] = now.toIso8601String();
    if (next == 'running' && job['started_at'] == null) job['started_at'] = now.toIso8601String();
    if (_copyJobIsTerminal(next)) job['finished_at'] = now.toIso8601String();
    final events = job['events'] as List<Map<String, dynamic>>;
    job['event_seq'] = (job['event_seq'] as int) + 1;
    events.add({
      'seq': job['event_seq'],
      'type': 'state_changed',
      'message': message,
      'created_at': now.toIso8601String(),
    });
  }

  /// 惰性推进：queued(1.2s) → acquiring_target(1.2s) → running（文件项串行
  /// 1.8s/个，第 2 项校验失败）→ completed_with_errors，总计约 6.4s。
  /// 循环追赶直到该时刻不再有可推进的转移（读大幅跳跃时一次追平）。
  void _advanceCopyJob(Map<String, dynamic> job, DateTime now) {
    var progressed = true;
    while (progressed && !_copyJobIsTerminal(job['state'] as String)) {
      progressed = _advanceCopyJobOnce(job, now);
    }
  }

  bool _advanceCopyJobOnce(Map<String, dynamic> job, DateTime now) {
    final state = job['state'] as String;
    final phaseStart = DateTime.parse(job['phase_started_at'] as String);
    switch (state) {
      case 'queued':
        final due = phaseStart.add(const Duration(milliseconds: 1200));
        if (now.isBefore(due)) return false;
        _copyJobTransitionTimed(job, 'acquiring_target', due, '正在获取目标盘');
        return true;
      case 'acquiring_target':
        final due = phaseStart.add(const Duration(milliseconds: 1200));
        if (now.isBefore(due)) return false;
        _copyJobTransitionTimed(job, 'running', due, '开始复制文件');
        job['running_last_tick'] = due.toIso8601String();
        return true;
      case 'running':
        final lastTick = job['running_last_tick'] as String?;
        job['running_active_ms'] =
            (job['running_active_ms'] as int) +
            (lastTick == null ? 0 : now.difference(DateTime.parse(lastTick)).inMilliseconds);
        job['running_last_tick'] = now.toIso8601String();
        _advanceCopyJobItems(job);
        if ((job['items'] as List<Map<String, dynamic>>).every((item) => const {
          'copied',
          'failed',
          'skipped_conflict',
          'not_applicable',
        }.contains(item['state']))) {
          _copyJobTransitionTimed(job, 'completed_with_errors', now, '任务部分完成：1 个文件失败');
          return true;
        }
        return false;
      case 'pause_requested':
        final due = phaseStart.add(const Duration(milliseconds: 800));
        if (now.isBefore(due)) return false;
        _copyJobTransitionTimed(job, 'paused', due, '任务已暂停');
        return true;
      case 'cancel_requested':
        final due = phaseStart.add(const Duration(milliseconds: 800));
        if (now.isBefore(due)) return false;
        _copyJobTransitionTimed(job, 'cancelled', due, '任务已取消，已完成的副本不会删除');
        return true;
      default:
        return false;
    }
  }

  /// 时间驱动的转移：phaseStart 回溯到「本应发生的时刻」。
  void _copyJobTransitionTimed(
    Map<String, dynamic> job,
    String next,
    DateTime at,
    String message,
  ) {
    job['state'] = next;
    job['state_version'] = (job['state_version'] as int) + 1;
    job['phase_started_at'] = at.toIso8601String();
    if (next == 'running' && job['started_at'] == null) job['started_at'] = at.toIso8601String();
    if (_copyJobIsTerminal(next)) job['finished_at'] = at.toIso8601String();
    final events = job['events'] as List<Map<String, dynamic>>;
    job['event_seq'] = (job['event_seq'] as int) + 1;
    events.add({
      'seq': job['event_seq'],
      'type': 'state_changed',
      'message': message,
      'created_at': at.toIso8601String(),
    });
  }

  void _advanceCopyJobItems(Map<String, dynamic> job) {
    final activeMs = job['running_active_ms'] as int;
    var itemStartMs = job['item_start_ms'] as int? ?? 0;
    var progressed = true;
    while (progressed) {
      progressed = false;
      for (final item in job['items'] as List<Map<String, dynamic>>) {
        switch (item['state'] as String) {
          case 'pending':
            if (activeMs >= itemStartMs) {
              item['state'] = 'copying';
              item['entered_at_ms'] = itemStartMs;
              progressed = true;
            }
          case 'copying':
            if (activeMs >= (item['entered_at_ms'] as int) + 1200) {
              item['state'] = 'verifying';
              item['entered_at_ms'] = (item['entered_at_ms'] as int) + 1200;
              progressed = true;
            }
          case 'verifying':
            if (activeMs >= (item['entered_at_ms'] as int) + 600) {
              final willFail = item['will_fail'] == true;
              item['state'] = willFail ? 'failed' : 'copied';
              itemStartMs = (item['entered_at_ms'] as int) + 600;
              job['item_start_ms'] = itemStartMs;
              final events = job['events'] as List<Map<String, dynamic>>;
              job['event_seq'] = (job['event_seq'] as int) + 1;
              events.add({
                'seq': job['event_seq'],
                'type': willFail ? 'item_failed' : 'item_copied',
                'message': willFail
                    ? '文件 ${item['target_filename']} 校验失败（COPY_HASH_MISMATCH）'
                    : '文件 ${item['target_filename']} 已复制并通过校验',
                'created_at': _clock().toIso8601String(),
              });
              progressed = true;
            }
          default:
            break;
        }
        if (progressed) break; // 串行：同一时刻只推进一个文件项
      }
    }
  }

  Map<String, dynamic> _copyItemPublicWire(Map<String, dynamic> item) => {
    'copy_item_id': item['copy_item_id'],
    'source_relative_path': item['source_relative_path'],
    'source_size': item['source_size'],
    'source_mtime_ns': item['source_mtime_ns'],
    'target_relative_directory': item['target_relative_directory'],
    'target_filename': item['target_filename'],
    'state': item['state'],
  };

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
      'state': 'created',
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
    'software_version': progressiveMedia ? 'mock-box-0.6.2' : 'mock-box-1.0.0',
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
      'state': 'ready_to_review',
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
      'state': 'completed',
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
      'state': 'failed',
      'total_files': 5621,
      'analyzed_count': 5621,
      'pending_review_count': 0,
      'keep_count': 1812,
      'discard_count': 3809,
      'pending_copy_count': 0,
      'copy_state': 'failed',
      'scene_count': 7,
      'burst_group_count': 143,
      'cover': _previewFor('egret.png', height: 1536),
    },
    {
      'project_id': 'mock-batch-history-03',
      'name': '江苏盐城湿地',
      'created_at': '2026-06-20T05:40:00Z',
      'state': 'analyzing',
      'total_files': 896,
      'analyzed_count': 412,
      'pending_review_count': 0,
      'keep_count': 0,
      'discard_count': 0,
      'pending_copy_count': 0,
      'copy_state': 'idle',
      'scene_count': 3,
      'burst_group_count': 32,
      'cover': _previewFor('warbler.png', height: 1536),
    },
  ];

  Map<String, dynamic> _projectPage(Map<String, String> query) {
    var items = <Map<String, dynamic>>[
      ..._createdProjects.values.toList().reversed,
      _currentBatch(),
      ..._historyBatches(),
    ];
    final requestedState = query['state']?.trim().toLowerCase();
    if (requestedState?.isNotEmpty == true) {
      items = items.where((project) => _matchesProjectState(project, requestedState!)).toList(growable: false);
    }
    if (query['sort'] == 'created_at_desc') {
      items = [...items]
        ..sort(
          (left, right) => right['created_at'].toString().compareTo(
            left['created_at'].toString(),
          ),
        );
    }
    final pageSize = (int.tryParse(query['page_size'] ?? '') ?? 30).clamp(
      1,
      100,
    );
    final cursor = (int.tryParse(query['cursor'] ?? '') ?? 0).clamp(
      0,
      items.length,
    );
    final end = min(cursor + pageSize, items.length);
    return {
      'items': items.sublist(cursor, end),
      'has_more': end < items.length,
      if (end < items.length) 'next_cursor': '$end',
    };
  }

  bool _matchesProjectState(
    Map<String, dynamic> project,
    String requestedState,
  ) {
    final state = _normalizeProjectState(project['state']);
    final copyState = _normalizeProjectState(project['copy_state']);
    const failedStates = {'failed', 'error', 'errored'};
    const inProgressStates = {
      'created',
      'scanning',
      'importing',
      'analyzing',
      'processing',
      'running',
      'resuming',
    };
    const reviewStates = {'ready_to_review', 'review', 'pending_review'};

    return switch (_normalizeProjectState(requestedState)) {
      'failed' => failedStates.contains(state) || failedStates.contains(copyState),
      'in_progress' => inProgressStates.contains(state) || copyState == 'running',
      'review' =>
        reviewStates.contains(state) || (!failedStates.contains(state) && !failedStates.contains(copyState) && !inProgressStates.contains(state) && copyState != 'running' && ((project['pending_review_count'] as num?)?.toInt() ?? 0) > 0),
      final value => state == value,
    };
  }

  String _normalizeProjectState(Object? value) =>
      value?.toString().trim().toLowerCase().replaceAll(
        RegExp(r'[\s-]+'),
        '_',
      ) ??
      '';

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

  Future<void> _exchangePairingSession(HttpRequest request) async {
    final body = await _requestJson(request);
    lastRc4PairingIncludedCode = body.containsKey('pairing_code');
    lastRc4PairingClientId = body['client_id']?.toString();
    const expected = {
      'device_id',
      'client_id',
      'client_name',
      'pairing_session_id',
    };
    if (!body.keys.toSet().containsAll(expected) || !expected.containsAll(body.keys.toSet())) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'code': 'INVALID_REQUEST',
          'message': 'The rc4 pairing request shape is invalid.',
          'retryable': false,
          'retry_after_ms': 0,
        },
        envelope: false,
      );
      return;
    }
    if (body['device_id'] != deviceId || body['pairing_session_id'] != pairingSessionId) {
      await _json(
        request,
        HttpStatus.forbidden,
        {
          'code': 'PAIRING_SESSION_INVALID',
          'message': 'The pairing session is invalid.',
          'retryable': false,
          'retry_after_ms': 0,
        },
        envelope: false,
      );
      return;
    }
    if (_pairingSessionConsumed) {
      await _json(
        request,
        HttpStatus.conflict,
        {
          'code': 'PAIRING_SESSION_USED',
          'message': 'The pairing session was already consumed.',
          'retryable': false,
          'retry_after_ms': 0,
        },
        envelope: false,
      );
      return;
    }
    final clientId = body['client_id'];
    if (clientId is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(clientId)) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'code': 'INVALID_REQUEST',
          'message': 'client_id must be a UUID v4.',
          'retryable': false,
          'retry_after_ms': 0,
        },
        envelope: false,
      );
      return;
    }
    _pairingSessionConsumed = true;
    const expiresIn = 2592000;
    final expiresAt = _clock().toUtc().add(
      const Duration(seconds: expiresIn),
    );
    final token = 'mock-rc4-access-${expiresAt.microsecondsSinceEpoch}';
    _activeToken = token;
    _tokenExpiresAt = expiresAt;
    await _json(
      request,
      HttpStatus.created,
      {
        'token_type': 'Bearer',
        'access_token': token,
        'expires_in': expiresIn,
        'device_id': deviceId,
        'client_id': clientId,
      },
      envelope: false,
    );
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

  Future<void> _serveProgressiveMedia(
    HttpRequest request,
    String fileId,
    String kind,
  ) async {
    lastSignedAssetAuthorizationHeader = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (!await _validateSignedRequest(request)) return;
    final photo = _photosById[fileId];
    final assetName = _photoAssetNames[fileId];
    if (photo == null || assetName == null) {
      await _json(
        request,
        HttpStatus.notFound,
        {
          'error_code': 'file_not_found',
          'error_message': 'Unknown file: $fileId',
          'retryable': false,
          'details': {'file_id': fileId},
        },
        envelope: false,
      );
      return;
    }
    final status = photo[_statusField(kind)]?.toString() ?? 'pending';
    if (status == 'not_requested' || status == 'pending') {
      request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
      await _json(
        request,
        HttpStatus.notFound,
        {
          'error_code': 'asset_not_ready',
          'error_message': '图片仍在生成，请稍后重试',
          'retryable': true,
          'details': {
            'file_id': fileId,
            'kind': kind,
            'status': status,
          },
        },
        envelope: false,
      );
      return;
    }
    if (status == 'failed') {
      await _json(
        request,
        HttpStatus.conflict,
        {
          'error_code': 'asset_failed',
          'error_message': '图片生成失败',
          'retryable': false,
          'details': {
            'file_id': fileId,
            'kind': kind,
            'status': status,
          },
        },
        envelope: false,
      );
      return;
    }
    final etag = _etag(fileId, kind);
    request.response.headers.set(HttpHeaders.etagHeader, etag);
    request.response.headers.set(
      HttpHeaders.cacheControlHeader,
      'public, max-age=60',
    );
    if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      request.response.statusCode = HttpStatus.notModified;
      await request.response.close();
      return;
    }
    final file = File(
      '${assetDirectory.path}${Platform.pathSeparator}$assetName',
    );
    if (!await file.exists()) {
      await _json(
        request,
        HttpStatus.notFound,
        {
          'error_code': 'file_not_found',
          'error_message': 'Mock media bytes are missing.',
          'retryable': false,
          'details': {'file_id': fileId},
        },
        envelope: false,
      );
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.contentLength = await file.length();
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> _controlMediaAsset(HttpRequest request) async {
    final body = await _requestJson(request);
    final fileId = body['file_id']?.toString() ?? '';
    final kind = body['kind']?.toString() ?? '';
    final status = body['status']?.toString() ?? '';
    final emitEvent = body['emit_event'] != false;
    try {
      await setMediaAssetStatus(
        fileId,
        kind,
        status,
        emitEvent: emitEvent,
      );
    } on ArgumentError catch (error) {
      await _json(
        request,
        HttpStatus.unprocessableEntity,
        {
          'error_code': 'mock_control_invalid',
          'error_message': error.message?.toString() ?? 'Invalid control.',
        },
        envelope: false,
      );
      return;
    }
    await _json(request, HttpStatus.ok, {
      'file_id': fileId,
      'kind': kind,
      'status': status,
      if (status == 'ready') 'etag': _etag(fileId, kind),
    });
  }

  void _initializeProgressiveMedia() {
    for (var index = 0; index < _photos.length; index++) {
      final photo = _photos[index];
      final fileId = photo['file_id'] as String;
      photo
        ..['thumb_ref'] = '/api/v1/files/$fileId/thumbnail'
        ..['preview_ref'] = '/api/v1/files/$fileId/preview'
        ..['thumbnail_status'] = switch (index % 8) {
          0 => 'ready',
          1 => 'failed',
          _ => 'pending',
        }
        ..['preview_status'] = index % 8 == 0 ? 'ready' : 'not_requested';
      _assetRevisions[_assetKey(fileId, 'thumbnail')] = 1;
      _assetRevisions[_assetKey(fileId, 'preview')] = 1;
    }
  }

  String _statusField(String kind) => kind == 'thumbnail' ? 'thumbnail_status' : 'preview_status';

  String _assetKey(String fileId, String kind) => '$fileId:$kind';

  String _etag(String fileId, String kind) => '"mock-$fileId-$kind-v${_assetRevisions[_assetKey(fileId, kind)] ?? 1}"';

  Future<void> _emitAssetReady(String fileId, String kind) async {
    final photo = _photosById[fileId]!;
    final message = jsonEncode({
      'event_id': 'evt-asset-${(++_eventSequence).toString().padLeft(6, '0')}',
      'event_type': 'asset_ready',
      'timestamp': _clock().toUtc().toIso8601String(),
      'payload': {
        'job_id': 'job-analysis-mock',
        'project_id': 'mock-batch-current',
        'file_id': fileId,
        'kind': kind,
        'status': 'ready',
        'etag': _etag(fileId, kind),
        'width': photo['width'],
        'height': photo['height'],
        'generation_mode': kind == 'thumbnail' ? 'embedded_thumbnail' : 'rendered_preview',
      },
    });
    for (final socket in List<WebSocket>.of(_eventSockets)) {
      try {
        socket.add(message);
      } catch (_) {
        _eventSockets.remove(socket);
      }
    }
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
          if (!entry.key.contains('/api/v1/device/pair') && !entry.key.contains('/api/v1/pairing'))
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
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Content-Type, Authorization, X-Api-Version, X-Idempotency-Key, '
      'If-None-Match',
    );
    response.headers.set(
      HttpHeaders.accessControlExposeHeadersHeader,
      'ETag, Retry-After',
    );
  }
}

class _CachedHttpResponse {
  const _CachedHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
