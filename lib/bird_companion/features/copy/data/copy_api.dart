import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

class CopyApi {
  CopyApi(this._c);
  final ApiClient _c;
  Future<CopyEstimate> estimate(String id, String mode) async {
    _validateRequest(id, mode);
    final d = await _c.get(ApiEndpoints.copyEstimate.replaceFirst('{batchId}', id), queryParameters: {'mode': mode});
    return CopyEstimate.fromJson(d, requestedMode: mode);
  }

  Future<BirdJobStatus> create(
    String i,
    String m,
    String t, {
    required bool xmpEnabled,
    required bool verifyAfterCopy,
    required int version,
  }) {
    _validateRequest(i, m);
    if (t.trim().isEmpty) {
      throw ArgumentError.value(t, 'targetId', 'must not be empty');
    }
    if (version < 0) {
      throw ArgumentError.value(version, 'version', 'must be non-negative');
    }
    return _c
        .post(
          ApiEndpoints.copyCreate.replaceFirst('{batchId}', i),
          data: {
            'mode': m,
            'target_id': t,
            'xmp_enabled': xmpEnabled,
            'verify_after_copy': verifyAfterCopy,
            'version': version,
          },
        )
        .then(BirdJobStatus.fromJson);
  }

  static void _validateRequest(String projectId, String mode) {
    if (projectId.trim().isEmpty) {
      throw ArgumentError.value(projectId, 'projectId', 'must not be empty');
    }
    if (!copyModes.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'must match birdbox-v1');
    }
  }
}
