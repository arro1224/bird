import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

class CopyApi {
  CopyApi(this._c);
  final ApiClient _c;
  Future<CopyEstimate> estimate(String id, String mode) async {
    final d = await _c.get(ApiEndpoints.copyEstimate.replaceFirst('{batchId}', id), queryParameters: {'mode': mode});
    final t = (d['targets'] as List? ?? const []).whereType<Map>().map((x) => StorageTarget.fromJson(Map<String, dynamic>.from(x))).toList();
    return CopyEstimate(
      mode: mode,
      fileCount: (d['file_count'] as num?)?.toInt() ?? 0,
      requiredBytes: (d['required_bytes'] as num?)?.toInt() ?? 0,
      pendingCount: (d['pending_count'] as num?)?.toInt() ?? 0,
      targets: t,
      version: (d['version'] as num?)?.toInt() ?? 0,
    );
  }

  Future<BirdJobStatus> create(
    String i,
    String m,
    String t, {
    required bool xmpEnabled,
    required bool verifyAfterCopy,
    required int version,
  }) => _c
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
