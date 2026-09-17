import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';

/// birdbox-copy-v1 HTTP 接口（主协议 §13）。
///
/// 所有请求携带 `X-BirdBox-Protocol: birdbox-copy-v1`；创建/动作请求由
/// [ApiClient.post] 自动附加同值的 `Idempotency-Key` 与兼容头
/// `X-Idempotency-Key`。
class CopyApi {
  CopyApi(this._c);
  final ApiClient _c;
  final Map<String, StorageDeviceSummary> _deviceCache = {};

  static const _protocolHeader = {
    'X-BirdBox-Protocol': 'birdbox-copy-v1',
    'X-BirdBox-Copy-Revision': '1.0-rc3',
  };

  Future<CopyCapabilities> capabilities() async => CopyCapabilities.fromJson(
    await _c.get(ApiEndpoints.copyCapabilities, headers: _protocolHeader),
  );

  Future<SourceBinding> source({String? batchId}) async => SourceBinding.fromJson(
    await _c.get(
      ApiEndpoints.storageSource,
      queryParameters: batchId == null ? null : {'batch_id': batchId},
      headers: _protocolHeader,
    ),
  );

  Future<CopyPreferences> preferences() async => CopyPreferences.fromJson(
    await _c.get(ApiEndpoints.copyPreferences, headers: _protocolHeader),
  );

  Future<CopyPreferences> savePreferences(
    PairPolicy pairPolicy, {
    required int expectedVersion,
  }) async => CopyPreferences.fromJson(
    await _c.post(
      ApiEndpoints.copyPreferences,
      data: {
        'pair_policy': pairPolicy.wireValue,
        'expected_preferences_version': expectedVersion,
      },
      headers: _protocolHeader,
    ),
  );

  Future<List<CopyScopeOption>> scopeOptions({
    String? batchId,
    String? selectionId,
    Map<String, dynamic>? filter,
  }) async {
    final raw = await _c.post(
      ApiEndpoints.copyScopeOptions,
      data: {
        'batch_id': batchId,
        'selection_id': selectionId,
        'filter': filter,
      },
      headers: _protocolHeader,
    );
    final options = raw['options'];
    if (options is! List || options.length != 5) {
      throw const ProtocolCompatibilityException(
        'options',
        'rc3 必须返回且只返回五个复制范围',
      );
    }
    return options
        .map(
          (item) => CopyScopeOption.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<CopyDeviceList> devices() async {
    final raw = await _c.get(
      ApiEndpoints.storageDevices,
      headers: _protocolHeader,
    );
    final list = raw['devices'];
    if (list is! List) {
      throw const ProtocolCompatibilityException('devices', '必须是设备列表');
    }
    final parsed = list.indexed
        .map((entry) {
          final item = entry.$2;
          if (item is! Map) {
            throw ProtocolCompatibilityException(
              'devices[${entry.$1}]',
              '必须是对象',
            );
          }
          return StorageDeviceSummary.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
    _deviceCache
      ..clear()
      ..addEntries(parsed.map((device) => MapEntry(device.mediaId, device)));
    return CopyDeviceList(
      devices: parsed,
      recommendedTargetMediaId:
          (raw['last_successful_target_media_id'] ?? raw['recommended_target_media_id'])
              ?.toString(),
    );
  }

  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  }) async {
    final batch = batchId.trim();
    if (batch.isEmpty) {
      throw ArgumentError.value(batchId, 'batchId', 'must not be empty');
    }
    if (assetIds.isEmpty) {
      throw ArgumentError.value(assetIds, 'assetIds', 'must not be empty');
    }
    final manifest = await _c.get(
      ApiEndpoints.batchCopyAssets.replaceFirst('{batchId}', batch),
      headers: _protocolHeader,
    );
    final manifestRevision = ProtocolValidation.nonNegativeInt(
      manifest,
      'manifest_revision',
    );
    final session = await _c.post(
      ApiEndpoints.copySelectionSessions.replaceFirst('{batchId}', batch),
      data: {
        'client_revision': clientRevision,
        'manifest_revision': manifestRevision,
      },
      headers: _protocolHeader,
    );
    final sessionId = ProtocolValidation.requiredId(session, 'session_id');
    for (var offset = 0, chunkIndex = 0; offset < assetIds.length; offset += 1000, chunkIndex++) {
      final end = offset + 1000 < assetIds.length ? offset + 1000 : assetIds.length;
      await _c.post(
        ApiEndpoints.copySelectionSessionChunks.replaceFirst(
          '{sessionId}',
          sessionId,
        ),
        data: {
          'chunk_index': chunkIndex,
          'asset_ids': assetIds.sublist(offset, end),
        },
        headers: _protocolHeader,
      );
    }
    return CopySelectionSnapshot.fromJson(
      await _c.post(
        ApiEndpoints.copySelectionSessionSeal.replaceFirst(
          '{sessionId}',
          sessionId,
        ),
        data: {'expected_unique_count': assetIds.toSet().length},
        headers: _protocolHeader,
      ),
    );
  }

  Future<CopyPreview> preview(CopyRequestDraft draft) async {
    var raw = await _c.post(
      ApiEndpoints.copyJobPreview,
      data: draft.toJson(),
      headers: _protocolHeader,
    );
    if (raw['state'] == 'building') {
      final previewId = ProtocolValidation.requiredId(raw, 'preview_id');
      for (var attempt = 0; attempt < 20; attempt++) {
        raw = await _c.get(
          ApiEndpoints.copyPreviewDetail.replaceFirst(
            '{previewId}',
            previewId,
          ),
          headers: _protocolHeader,
        );
        if (raw['state'] == 'ready') break;
        if (raw['state'] == 'failed') {
          throw StateError('复制预检失败，请检查源卡和目标盘状态');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (raw['state'] != 'ready') {
        throw StateError('复制预检超时，请稍后重试');
      }
    }
    final source = _deviceCache[draft.sourceMediaId];
    final target = _deviceCache[draft.targetMediaId];
    if (source == null || target == null) {
      throw const ProtocolCompatibilityException(
        'source/target',
        '设备快照已过期，请重新加载复制页面',
      );
    }
    final counts = raw['category_counts'];
    final categories = counts is Map ? Map<String, dynamic>.from(counts) : const <String, dynamic>{};
    return CopyPreview.fromJson({
      ...raw,
      'source': _deviceToJson(source),
      'target': _deviceToJson(target),
      'logical_photo_count': raw['logical_assets'] ?? raw['logical_photo_count'],
      'actual_file_count': raw['planned_files'] ?? raw['actual_file_count'],
      'total_bytes': raw['planned_bytes'] ?? raw['total_bytes'],
      'raw_count': categories['raw'] ?? raw['raw_count'] ?? 0,
      'jpeg_count': categories['photo'] ?? categories['jpeg'] ?? raw['jpeg_count'] ?? 0,
      'video_count': categories['video'] ?? raw['video_count'] ?? 0,
      'companion_count': categories['companion'] ?? raw['companion_count'] ?? 0,
      'estimated_date_directories': raw['date_directory_count'] ?? raw['estimated_date_directories'],
      'safety_reserve_bytes': raw['reserved_free_bytes'] ?? raw['safety_reserve_bytes'],
      'unsupported_count': raw['unsupported_count'] ?? 0,
      'missing_count': raw['missing_count'] ?? 0,
      'permission_error_count': raw['permission_error_count'] ?? 0,
    });
  }

  Future<CopyJobSummary> createJob(
    CopyRequestDraft draft,
    String previewToken,
  ) async {
    return CopyJobSummary.fromJson(
      await _c.post(
        ApiEndpoints.copyJobs,
        data: {
          ...draft.toJson(),
          'preview_token': previewToken,
        },
        headers: _protocolHeader,
      ),
    );
  }

  // ---- RC3 任务闭环（§13.5/§13.6，响应解析容错，模型见 copy_job_models.dart）----
  // capabilities() 沿用上方 rc3 契约实现（copy_models.dart 的 CopyCapabilities）。

  /// GET copy-jobs —— 任务列表（契约未冻结，容错分页）。
  Future<CopyJobPage> listJobs({String? cursor}) async {
    final raw = await _c.get(
      ApiEndpoints.copyJobs,
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
      headers: _protocolHeader,
    );
    return CopyJobPage.fromJson(raw);
  }

  Future<CopyJobDetail> getJob(String copyJobId) async {
    return CopyJobDetail.fromJson(
      await _c.get(
        ApiEndpoints.copyJobDetail.replaceFirst('{copyJobId}', copyJobId),
        headers: _protocolHeader,
      ),
    );
  }

  /// GET copy-jobs/{id}/items —— `state=failed` 过滤失败项（§13.5）。
  Future<CopyJobItemPage> jobItems(
    String copyJobId, {
    String? cursor,
    String? state,
  }) async {
    final raw = await _c.get(
      ApiEndpoints.copyJobItems.replaceFirst('{copyJobId}', copyJobId),
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (state != null && state.isNotEmpty) 'state': state,
      },
      headers: _protocolHeader,
    );
    return CopyJobItemPage.fromJson(raw);
  }

  Future<CopyJobEventPage> jobEvents(
    String copyJobId, {
    int? afterSeq,
  }) async {
    final raw = await _c.get(
      ApiEndpoints.copyJobEvents.replaceFirst('{copyJobId}', copyJobId),
      queryParameters: {
        if (afterSeq != null && afterSeq > 0) 'after_seq': afterSeq,
      },
      headers: _protocolHeader,
    );
    return CopyJobEventPage.fromJson(raw);
  }

  Future<CopyReport> jobReport(String copyJobId) async {
    return CopyReport.fromJson(
      await _c.get(
        ApiEndpoints.copyJobReport.replaceFirst('{copyJobId}', copyJobId),
        headers: _protocolHeader,
      ),
    );
  }

  /// POST copy-jobs/{id}/actions/{action}（§13.6）。
  ///
  /// 2xx 响应可能不带 copy_job_id（契约未冻结）；返 null，调用方统一重拉详情。
  Future<CopyJobDetail?> jobAction(
    String copyJobId,
    String actionWire, {
    required int expectedStateVersion,
  }) async {
    final raw = await _c.post(
      ApiEndpoints.copyJobAction
          .replaceFirst('{copyJobId}', copyJobId)
          .replaceFirst('{action}', actionWire),
      data: {
        'expected_state_version': expectedStateVersion,
        'reason': 'user_requested',
      },
      headers: _protocolHeader,
    );
    final rawJob = raw['copy_job'];
    if (rawJob is Map) {
      return CopyJobDetail.fromJson(Map<String, dynamic>.from(rawJob));
    }
    return null;
  }

  /// GET copy-previews/{id}/items —— 预检文件明细（§10.2）。
  /// preview_id 与 preview_token 的关系契约未冻结，暂按同值传递。
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) async {
    final raw = await _c.get(
      ApiEndpoints.copyPreviewItems.replaceFirst('{previewId}', previewId),
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
      headers: _protocolHeader,
    );
    return CopyJobItemPage.fromJson(raw);
  }

  /// POST storage/devices/{media_id}/safe-remove（§4.5/§13.6）。
  Future<SafeRemoveResult> safeRemoveDevice(
    String mediaId, {
    required String role,
    String? expectedCopyJobId,
  }) async {
    final id = mediaId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(mediaId, 'mediaId', 'must not be empty');
    }
    return SafeRemoveResult.fromJson(
      await _c.post(
        ApiEndpoints.storageDeviceSafeRemove.replaceFirst('{mediaId}', id),
        data: {
          'role': role,
          if (expectedCopyJobId != null && expectedCopyJobId.isNotEmpty)
            'expected_copy_job_id': expectedCopyJobId,
        },
        headers: _protocolHeader,
      ),
    );
  }

  /// 同批次上次成功目标设备的读取端点由后端交付契约确认（§4.4 仅规定保存）。
  Future<Map<String, dynamic>?> lastSuccessfulTarget(String batchId) async => null;

  Future<void> setDeviceAlias(String mediaId, String alias) async {
    final id = mediaId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(mediaId, 'mediaId', 'must not be empty');
    }
    await _c.post(
      ApiEndpoints.storageDeviceAlias.replaceFirst('{mediaId}', id),
      data: {'alias': alias.trim()},
      headers: _protocolHeader,
    );
  }

  Map<String, dynamic> _deviceToJson(StorageDeviceSummary device) => {
    'media_id': device.mediaId,
    'display_name': device.displayName,
    'kind': device.kind,
    'kind_confidence': device.kindConfidence,
    'detail': device.detail,
    'capacity_bytes': device.capacityBytes,
    'free_bytes': device.freeBytes,
    'filesystem': device.filesystem,
    'label': device.label,
    'role_state': device.roleState,
    'can_be_source': device.canBeSource,
    'can_be_target': device.canBeTarget,
    'target_block_reasons': device.targetBlockReasons,
    'identity_confidence': device.identityConfidence,
    'last_seen_at': device.lastSeenAt?.toIso8601String(),
    'user_alias': device.userAlias,
  };
}
