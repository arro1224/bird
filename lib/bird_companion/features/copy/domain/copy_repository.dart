import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';

/// 复制功能仓库接口（主协议 birdbox-copy-v1 第 13 节）。
///
/// 旧的 `estimate?mode=` / `POST /projects/{batchId}/copy` 已从协议中移除，
/// App 不得再调用旧接口（迁移对照文档 §4.1）。
abstract interface class CopyRepository {
  /// GET storage/devices —— 实时设备列表，App 只认 `media_id`。
  Future<List<StorageDeviceSummary>> devices();

  /// POST batches/{batchId}/copy-selections —— 创建不可变选择快照。
  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  });

  /// POST copy-jobs/preview —— 预检，返回 `preview_token`。
  Future<CopyPreview> preview(CopyRequestDraft draft);

  /// POST copy-jobs —— 创建复制任务。
  Future<CopyJobSummary> createJob(CopyRequestDraft draft, String previewToken);

  /// 同批次上次成功目标设备（§4.4），仅作为可修改的预选。
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId);

  /// POST storage/devices/{media_id}/alias —— 设置设备用户别名。
  Future<void> setDeviceAlias(String mediaId, String alias);
}
