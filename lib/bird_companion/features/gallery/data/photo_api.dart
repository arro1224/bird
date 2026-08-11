import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';

class PhotoApi {
  PhotoApi(this._client);
  final ApiClient _client;
  Future<PhotoPage> page(String batchId, PhotoQuery q) async {
    final data = await _client.get(ApiEndpoints.photos.replaceFirst('{batchId}', batchId), queryParameters: q.parameters);
    final list = data['items'] as List? ?? const [];
    return PhotoPage(
      items: list.whereType<Map>().map((e) => PhotoSummary.fromJson(Map<String, dynamic>.from(e))).toList(),
      hasMore: data['has_more'] == true,
      nextCursor: data['next_cursor']?.toString(),
    );
  }

  Future<List<SceneSummary>> scenes(String batchId) async {
    final data = await _client.get(ApiEndpoints.scenes.replaceFirst('{batchId}', batchId));
    final list = data['items'] as List? ?? const [];
    return list.whereType<Map>().map((item) => SceneSummary.fromJson(Map<String, dynamic>.from(item))).toList();
  }

  Future<List<SpeciesCandidate>> searchSpecies(String query) async {
    final data = await _client.get(ApiEndpoints.speciesSearch, queryParameters: {'search': query, 'page_size': 20});
    final list = data['items'] as List? ?? const [];
    return list.whereType<Map>().map((item) => SpeciesCandidate.fromJson(Map<String, dynamic>.from(item))).toList();
  }

  Future<BatchOperationOutcome> batchOperation(
    String batchId,
    List<String> ids,
    String operation, {
    required int version,
    Object? value,
    String? idempotencyKey,
  }) async {
    if (batchId.trim().isEmpty) {
      throw const ProtocolCompatibilityException('project_id', '不能为空');
    }
    final normalizedIds = ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      throw const ProtocolCompatibilityException('file_ids', '不能为空');
    }
    if (!_batchOperations.contains(operation)) {
      throw const ProtocolCompatibilityException(
        'operation',
        '必须是 birdbox-v1 定义的批量操作',
      );
    }
    if (version < 0) {
      throw const ProtocolCompatibilityException('version', '必须是非负整数');
    }
    final data = await _client.post(
      ApiEndpoints.batchPhotoOperation.replaceFirst('{batchId}', batchId),
      data: {
        'file_ids': normalizedIds,
        'operation': operation,
        'value': value,
        'version': version,
      },
      idempotencyKey: idempotencyKey,
    );
    final failed = <String, String>{};
    for (final item in (data['failed'] as List? ?? const [])) {
      if (item is Map) failed[item['file_id']?.toString() ?? 'unknown'] = item['reason']?.toString() ?? '操作失败';
    }
    final succeeded = (data['succeeded_ids'] as List? ?? normalizedIds.where((id) => !failed.containsKey(id)).toList()).map((id) => id.toString()).toList();
    return BatchOperationOutcome(succeededIds: succeeded, failed: failed);
  }
}

const _batchOperations = <String>{
  'pending',
  'keep',
  'discard',
  'featured',
  'add_tags',
  'remove_tags',
};
