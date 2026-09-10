import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';

/// birdbox-copy-v1 HTTP 接口（主协议 §13）。
///
/// 所有请求携带 `X-BirdBox-Protocol: birdbox-copy-v1`；创建/动作请求由
/// [ApiClient.post] 自动附加 `X-Idempotency-Key`。
class CopyApi {
  CopyApi(this._c);
  final ApiClient _c;

  static const _protocolHeader = {'X-BirdBox-Protocol': 'birdbox-copy-v1'};

  Future<List<StorageDeviceSummary>> devices() async {
    final raw = await _c.get(ApiEndpoints.storageDevices);
    final list = raw['devices'];
    if (list is! List) {
      throw const ProtocolCompatibilityException('devices', '必须是设备列表');
    }
    return list.indexed.map((entry) {
      final item = entry.$2;
      if (item is! Map) {
        throw ProtocolCompatibilityException(
          'devices[${entry.$1}]',
          '必须是对象',
        );
      }
      return StorageDeviceSummary.fromJson(Map<String, dynamic>.from(item));
    }).toList(growable: false);
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
