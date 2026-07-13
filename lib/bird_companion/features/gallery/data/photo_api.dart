import 'package:aves/bird_companion/core/models/photo_models.dart';
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

  Future<BatchOperationOutcome> batchOperation(String batchId, List<String> ids, String operation, {Object? value}) async {
    final data = await _client.post(ApiEndpoints.batchPhotoOperation.replaceFirst('{batchId}', batchId), data: {'file_ids': ids, 'operation': operation, 'value': value});
    final failed = <String, String>{};
    for (final item in (data['failed'] as List? ?? const [])) {
      if (item is Map) failed[item['file_id']?.toString() ?? 'unknown'] = item['reason']?.toString() ?? '操作失败';
    }
    final succeeded = (data['succeeded_ids'] as List? ?? ids.where((id) => !failed.containsKey(id)).toList()).map((id) => id.toString()).toList();
    return BatchOperationOutcome(succeededIds: succeeded, failed: failed);
  }
}
