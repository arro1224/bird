import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

/// 真实后端实现：任务闭环方法直接转发 `CopyApi`（容错模型），
/// 设备/创建流程沿用 `CopyRepository`（发送端严格解析）。
class CopyRepositoryImpl implements CopyRepository, CopyJobRepository {
  CopyRepositoryImpl(this._api);
  final CopyApi _api;

  @override
  Future<CopyDeviceList> devices() => _api.devices();

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

  @override
  Future<CopyCapabilities> capabilities() => _api.capabilities();

  @override
  Future<CopyJobPage> listJobs({String? cursor}) => _api.listJobs(cursor: cursor);

  @override
  Future<CopyJobDetail> getJob(String copyJobId) => _api.getJob(copyJobId);

  @override
  Future<CopyJobItemPage> jobItems(
    String copyJobId, {
    String? cursor,
    String? state,
  }) => _api.jobItems(copyJobId, cursor: cursor, state: state);

  @override
  Future<CopyJobEventPage> jobEvents(String copyJobId, {int? afterSeq}) =>
      _api.jobEvents(copyJobId, afterSeq: afterSeq);

  @override
  Future<CopyReport> jobReport(String copyJobId) => _api.jobReport(copyJobId);

  @override
  Future<CopyJobDetail?> jobAction(
    String copyJobId,
    String actionWire, {
    required int expectedStateVersion,
  }) => _api.jobAction(copyJobId, actionWire, expectedStateVersion: expectedStateVersion);

  @override
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) =>
      _api.previewItems(previewId, cursor: cursor);

  @override
  Future<SafeRemoveResult> safeRemoveDevice(
    String mediaId, {
    required String role,
    String? expectedCopyJobId,
  }) => _api.safeRemoveDevice(
    mediaId,
    role: role,
    expectedCopyJobId: expectedCopyJobId,
  );
}
