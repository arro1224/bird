import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

class CopyRepositoryImpl implements CopyRepository {
  CopyRepositoryImpl(this._api);
  final CopyApi _api;
  @override
  Future<CopyEstimate> estimate(String b, String m) => _api.estimate(b, m);
  @override
  Future<BirdJobStatus> create(
    String b,
    String m,
    String t, {
    required bool xmpEnabled,
    required bool verifyAfterCopy,
    required int version,
  }) => _api.create(
    b,
    m,
    t,
    xmpEnabled: xmpEnabled,
    verifyAfterCopy: verifyAfterCopy,
    version: version,
  );
}
