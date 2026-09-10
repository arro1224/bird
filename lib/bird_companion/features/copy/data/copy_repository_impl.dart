import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

class CopyRepositoryImpl implements CopyRepository {
  CopyRepositoryImpl(this._api);
  final CopyApi _api;

  @override
  Future<List<StorageDeviceSummary>> devices() => _api.devices();

  @override
  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  }) => _api.createSelection(
    batchId,
    assetIds,
    clientRevision: clientRevision,
  );

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) => _api.preview(draft);

  @override
  Future<CopyJobSummary> createJob(
    CopyRequestDraft draft,
    String previewToken,
  ) => _api.createJob(draft, previewToken);

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async {
    final data = await _api.lastSuccessfulTarget(batchId);
    if (data == null) return null;
    return BatchTargetPreference.fromJson(data);
  }

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) =>
      _api.setDeviceAlias(mediaId, alias);
}
