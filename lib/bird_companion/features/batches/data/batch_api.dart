import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';

class BatchApi {
  BatchApi(this._client);
  final ApiClient _client;

  Future<BatchSummary> create(ProjectCreateRequest request) async => BatchSummary.fromJson(
    await _client.post(ApiEndpoints.batches, data: request.toJson(), idempotencyKey: request.idempotencyKey),
  );

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

  /// Uses only existing reads. No speculative project-detail route or write.
  Future<BatchSummary> project(String projectId) async {
    final active = await current();
    if (active?.id == projectId) return active!;
    String? cursor;
    final visited = <String>{};
    for (var index = 0; index < 30; index++) {
      final result = await page(sort: 'created_at_desc', cursor: cursor);
      final found = result.items.where((item) => item.id == projectId).firstOrNull;
      if (found != null) return found;
      if (!result.hasMore || result.nextCursor == null || !visited.add(result.nextCursor!)) break;
      cursor = result.nextCursor;
    }
    throw StateError('无法读取此批次的权威状态，请刷新后重试');
  }
}
