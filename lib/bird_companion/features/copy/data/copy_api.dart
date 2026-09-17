import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';

/// birdbox-copy-v1 HTTP 接口（主协议 §13）。
///
/// 所有请求携带 `X-BirdBox-Protocol: birdbox-copy-v1`；创建/动作请求由
/// [ApiClient.post] 自动附加 `X-Idempotency-Key`。
class CopyApi {
  CopyApi(this._c);
  final ApiClient _c;

  static const _protocolHeader = {'X-BirdBox-Protocol': 'birdbox-copy-v1'};

  Future<CopyDeviceList> devices() async {
    final raw = await _c.get(ApiEndpoints.storageDevices, headers: _protocolHeader);
    final list = raw['devices'];
    if (list is! List) {
      throw const ProtocolCompatibilityException('devices', '必须是设备列表');
    }
    return CopyDeviceList(
      devices: list.indexed.map((entry) {
        final item = entry.$2;
        if (item is! Map) {
          throw ProtocolCompatibilityException(
            'devices[${entry.$1}]',
            '必须是对象',
          );
        }
        return StorageDeviceSummary.fromJson(Map<String, dynamic>.from(item));
      }).toList(growable: false),
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
    return CopySelectionSnapshot.fromJson(
      await _c.post(
        ApiEndpoints.copySelections.replaceFirst('{batchId}', batch),
        data: {'asset_ids': assetIds, 'client_revision': clientRevision},
        headers: _protocolHeader,
      ),
    );
  }

  Future<CopyPreview> preview(CopyRequestDraft draft) async {
    return CopyPreview.fromJson(
      await _c.post(
        ApiEndpoints.copyJobPreview,
        data: draft.toJson(),
        headers: _protocolHeader,
      ),
    );
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

  /// GET copy-capabilities —— 能力声明；端点未部署时由调用方捕获回退本地推导。
  Future<CopyCapabilities> capabilities() async {
    final raw = await _c.get(ApiEndpoints.copyCapabilities, headers: _protocolHeader);
    return CopyCapabilities.fromJson(raw);
  }

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
  Future<Map<String, dynamic>?> lastSuccessfulTarget(String batchId) async =>
      null;

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
}
