import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';

/// RC3 复制任务闭环仓库接口（§13.5/§13.6）。
///
/// 刻意独立于 `CopyRepository`：既有测试 fake（如
/// `production_copy_r3_flow_test.dart` 的 `_CopyRepository implements
/// CopyRepository`）不应因新增任务闭环方法而破裂。
abstract interface class CopyJobRepository {
  /// GET copy-capabilities —— 能力声明；未部署/失败由调用方回退本地推导。
  Future<CopyCapabilities> capabilities();

  /// GET copy-jobs —— 任务列表（契约未冻结，cursor 容错分页）。
  Future<CopyJobPage> listJobs({String? cursor});

  /// GET copy-jobs/{id} —— 任务详情。
  Future<CopyJobDetail> getJob(String copyJobId);

  /// GET copy-jobs/{id}/items —— 文件明细；`state=failed` 过滤失败项。
  Future<CopyJobItemPage> jobItems(String copyJobId, {String? cursor, String? state});

  /// GET copy-jobs/{id}/events —— 增量事件（after_seq）。
  Future<CopyJobEventPage> jobEvents(String copyJobId, {int? afterSeq});

  /// GET copy-jobs/{id}/report —— 终态报告（非终态后端应 409）。
  Future<CopyReport> jobReport(String copyJobId);

  /// POST copy-jobs/{id}/actions/{action}（§13.6）。
  ///
  /// 响应可能不带任务快照（契约未冻结）→ 返 null，调用方统一重拉详情。
  Future<CopyJobDetail?> jobAction(
    String copyJobId,
    String actionWire, {
    required int expectedStateVersion,
  });

  /// GET copy-previews/{id}/items —— 预检文件明细（preview_id 暂同 preview_token）。
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor});

  /// POST storage/devices/{media_id}/safe-remove —— 安全移除（§4.5）。
  Future<SafeRemoveResult> safeRemoveDevice(
    String mediaId, {
    required String role,
    String? expectedCopyJobId,
  });
}
