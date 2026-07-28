import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class MockBoxServer {
  MockBoxServer({
    this.photoCount = 1200,
    Directory? assetDirectory,
    this.logRequests = true,
  }) : assetDirectory = assetDirectory ?? Directory('tool/mock_box_server/assets') {
    if (photoCount <= 0) {
      throw ArgumentError.value(photoCount, 'photoCount', '必须大于 0');
    }
    _photos = List.generate(photoCount, _buildPhoto, growable: false);
    _photosById = {for (final photo in _photos) photo['file_id'] as String: photo};
    _scenes = _buildScenes();
    _groups = _buildGroups();
  }

  final int photoCount;
  final Directory assetDirectory;
  final bool logRequests;

  late final List<Map<String, dynamic>> _photos;
  late final Map<String, Map<String, dynamic>> _photosById;
  late final List<Map<String, dynamic>> _scenes;
  late final List<Map<String, dynamic>> _groups;
  final Map<String, Map<String, dynamic>> _decisions = {};
  final Map<String, List<Map<String, dynamic>>> _history = {};

  HttpServer? _server;

  Uri? get baseUri {
    final server = _server;
    if (server == null) return null;
    final host = server.address.type == InternetAddressType.IPv6 ? '[${server.address.address}]' : server.address.address;
    return Uri.parse('http://$host:${server.port}');
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
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (logRequests) {
      stdout.writeln('${request.method} ${request.uri}');
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
    if (method == 'GET' && path == '/api/v1/projects/current') {
      await _json(request, HttpStatus.ok, {'batch': _currentBatch()});
      return;
    }
    if (method == 'GET' && path == '/api/v1/projects') {
      await _json(request, HttpStatus.ok, {
        'items': [_currentBatch(), ..._historyBatches()],
        'has_more': false,
      });
      return;
    }
    if (method == 'GET' && path == '/api/v1/species') {
      await _json(request, HttpStatus.ok, {'items': _speciesSearch(request.uri.queryParameters['search'])});
      return;
    }
    if (method == 'GET' && path.startsWith('/mock/media/')) {
      await _serveMedia(request);
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

  Map<String, dynamic> _deviceStatus() => {
    'connection': {
      'device_id': 'mock-k7-001',
      'device_name': 'K7 模拟盒子',
      'api_version': 'v1',
      'network_mode': 'manual',
      'signal_strength': 92,
      'is_paired': true,
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
      'items': items.sublist(cursor, end),
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
      'file': photo,
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
    final version = ((current['version'] as num?)?.toInt() ?? 0) + 1;
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

  Future<void> _serveMedia(HttpRequest request) async {
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
    'members': (group['member_file_ids'] as List).map((id) => _photosById[id.toString()]).whereType<Map<String, dynamic>>().toList(growable: false),
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
    'thumb_ref': '/mock/media/$asset',
    'preview_ref': '/mock/media/$asset',
    'width': 1024,
    'height': height,
  };

  bool _isKnownBatch(String value) => value == 'mock-batch-current' || value.startsWith('mock-batch-history-');

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
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(envelope ? {'data': payload} : payload));
    await request.response.close();
  }

  void _cors(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS');
    response.headers.set(HttpHeaders.accessControlAllowHeadersHeader, 'Content-Type, Authorization, X-Api-Version, X-Idempotency-Key');
  }
}
