import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';

class ReviewApi {
  ReviewApi(this._client);
  final ApiClient _client;
  Future<List<BirdGroup>> groups(String id, {String? sceneId}) async {
    final data = await _client.get(
      ApiEndpoints.groups.replaceFirst('{batchId}', id),
      queryParameters: {if (sceneId?.isNotEmpty == true) 'scene_id': sceneId},
    );
    final items = data['items'] as List? ?? const [];
    return items.whereType<Map>().map((x) => BirdGroup.fromJson(Map<String, dynamic>.from(x))).toList();
  }

  Future<ReviewDetail> detail(String id) async {
    final requests = await Future.wait<Object>([
      _client.get(ApiEndpoints.photoDetail.replaceFirst('{fileId}', id)),
      _client.get(ApiEndpoints.photoHistory.replaceFirst('{fileId}', id)).catchError((_) => <String, dynamic>{'items': const []}),
    ]);
    final data = requests[0] as Map<String, dynamic>;
    final photo = PhotoSummary.fromJson(data['file'] is Map ? Map<String, dynamic>.from(data['file'] as Map) : data);
    final subjects = (data['subjects'] as List? ?? const []).whereType<Map>().map((x) => SubjectBox.fromJson(Map<String, dynamic>.from(x))).toList();
    final historyData = requests[1] as Map<String, dynamic>;
    final history = (historyData['items'] as List? ?? const []).whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return VersionHistory(
        version: (map['version'] as num?)?.toInt() ?? 0,
        source: map['source']?.toString() ?? 'box',
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
        summary: map['summary']?.toString(),
      );
    }).toList();
    final decisionMap = data['decision'] is Map ? Map<String, dynamic>.from(data['decision'] as Map) : null;
    final decisionVersion = decisionMap == null ? null : ProtocolValidation.optionalNonNegativeInt(decisionMap, 'version');
    final decision = decisionMap == null
        ? null
        : UserDecision(
            fileId: id,
            keepState: KeepStateWireValue.fromWire(decisionMap['keep_state']?.toString()),
            userScore: (decisionMap['user_score'] as num?)?.toDouble(),
            userSpeciesId: decisionMap['user_species_id']?.toString(),
            userSpecies: decisionMap['user_species']?.toString(),
            userTags: (decisionMap['user_tags'] as List? ?? const []).map((tag) => tag.toString()).toList(),
            version: decisionVersion ?? photo.version,
          );
    return ReviewDetail(
      photo: PhotoDetail(
        summary: photo,
        subjects: subjects,
        tags: (data['tags'] as List? ?? const []).whereType<Map>().map((item) => BirdTag.fromJson(Map<String, dynamic>.from(item))).toList(),
        exif: data['exif'] is Map ? Map<String, dynamic>.from(data['exif'] as Map) : const {},
      ),
      decision: decision,
      history: history,
    );
  }

  Future<void> save(
    UserDecisionPatch value, {
    String? idempotencyKey,
  }) {
    if (value.fileId.trim().isEmpty) {
      throw const ProtocolCompatibilityException('file_id', '不能为空');
    }
    if (value.version == null || value.version! < 0) {
      throw const ProtocolCompatibilityException('version', '必须是非负整数');
    }
    if (!value.hasChanges) {
      throw const ProtocolCompatibilityException(
        'decision',
        '至少包含一个待修改字段',
      );
    }
    return _client
        .post(
          ApiEndpoints.photoDecision.replaceFirst('{fileId}', value.fileId),
          data: value.toJson(),
          idempotencyKey: idempotencyKey,
        )
        .then((_) {});
  }
}
