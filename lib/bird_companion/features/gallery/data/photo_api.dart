import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/gallery/domain/gallery_timing.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';

class PhotoApi {
  PhotoApi(this._client);
  final ApiClient _client;

  Future<int> projectVersion(String projectId) async {
    final project = await BatchApi(_client).project(projectId);
    final version = project.projectVersion;
    if (version == null) throw const ProtocolCompatibilityException('project.version', '无法核实批次最新状态，批量修改未提交');
    return version;
  }

  Future<({PhotoSummary photo, Map<String, dynamic> detail})> photoSnapshot(String id) async {
    final data = await _client.get(ApiEndpoints.photoDetail.replaceFirst('{fileId}', Uri.encodeComponent(id)));
    final file = Map<String, dynamic>.from(data['file'] is Map ? data['file'] as Map : data);
    final decision = data['decision'] is Map ? Map<String, dynamic>.from(data['decision'] as Map) : const <String, dynamic>{};
    final version = ProtocolValidation.optionalNonNegativeInt(file, 'version') ?? ProtocolValidation.optionalNonNegativeInt(decision, 'version');
    if (version == null) throw const ProtocolCompatibilityException('photo.version', '照片回包缺少权威版本');
    file['version'] = version;
    final photo = PhotoSummary.fromJson(file);
    if (photo.id != id) throw const ProtocolCompatibilityException('file_id', '照片回包身份不一致');
    return (photo: photo, detail: {...data, 'file': file, 'decision': data['decision']});
  }

  Future<PhotoPage> page(String batchId, PhotoQuery q) async {
    final timing = GalleryTiming.current;
    final request = timing == null ? null : ++timing.requests;
    final started = timing?.elapsedUs ?? 0;
    late final Map<String, dynamic> data;
    try {
      data = await _client.get(ApiEndpoints.photos.replaceFirst('{batchId}', batchId), queryParameters: q.parameters);
    } catch (_) {
      if (timing != null) {
        timing.event('page_request_failed', {'request': request!, 'duration_us': timing.elapsedUs - started});
      }
      rethrow;
    }
    final received = timing?.elapsedUs ?? 0;
    if (timing != null) {
      timing.event('page_response', {'request': request!, 'duration_us': received - started});
    }
    final list = data['items'] as List? ?? const [];
    final parseStarted = timing?.elapsedUs ?? 0;
    final items = list.whereType<Map>().map((e) => PhotoSummary.fromJson(Map<String, dynamic>.from(e))).toList();
    if (timing != null) {
      timing.event('page_parsed', {'request': request!, 'items': items.length, 'duration_us': timing.elapsedUs - parseStarted});
    }
    return PhotoPage(
      items: items,
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
    final trace = {
      ...?_client.httpDiagnostics.context?.call(),
      'project_id': batchId,
      'project_version_sent': version,
      'file_count': normalizedIds.length,
      'batch_operation': operation,
      'batch_operation_id': idempotencyKey,
      'version_scope': 'project',
    };
    _recordBatch({'event': 'batch_review_started', ...trace});
    try {
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
      final outcome = BatchOperationOutcome.fromResponse(normalizedIds, data);
      _recordBatch({'event': 'batch_review_confirmed', ...trace, 'returned_project_version': outcome.projectVersion, 'succeeded_count': outcome.succeededIds.length, 'failed_count': outcome.failed.length});
      return outcome;
    } on ApiException catch (error) {
      _recordBatch({'event': 'batch_review_failed', ...trace, 'http_status': error.statusCode, 'error_code': error.code, 'current_project_version': error.details['current_version'] is int ? error.details['current_version'] : null});
      rethrow;
    }
  }

  void _recordBatch(Map<String, dynamic> event) {
    try {
      _client.httpDiagnostics.record?.call(event);
    } catch (_) {
      /* Recording cannot alter the mutation result. */
    }
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
