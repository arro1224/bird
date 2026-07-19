import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';

class BatchApi {
  BatchApi(this._client);
  final ApiClient _client;

  Future<BatchPage> page({String? state, String? sort, String? cursor}) async {
    final query = <String, dynamic>{'page_size': 30};
    if (state != null) query['state'] = state;
    if (sort != null) query['sort'] = sort;
    if (cursor != null) query['cursor'] = cursor;
    final data = await _client.get(ApiEndpoints.batches, queryParameters: query);
    final items = data['items'] as List? ?? data['batches'] as List? ?? const [];
    return BatchPage(items: items.whereType<Map>().map((item) => BatchSummary.fromJson(Map<String, dynamic>.from(item))).toList(), hasMore: data['has_more'] == true, nextCursor: data['next_cursor']?.toString());
  }

  Future<BatchSummary?> current() async {
    final data = await _client.get(ApiEndpoints.currentBatch);
    return data.isEmpty ? null : BatchSummary.fromJson(data['batch'] is Map ? Map<String, dynamic>.from(data['batch'] as Map) : data);
  }

  Future<void> resume(String batchId) => _client.post(ApiEndpoints.batchResume.replaceFirst('{batchId}', batchId));
}
