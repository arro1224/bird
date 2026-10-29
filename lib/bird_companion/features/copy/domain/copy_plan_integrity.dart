import 'dart:async';
import 'dart:convert';
import 'package:aves/bird_companion/core/network/api_exception.dart';

import 'copy_job_models.dart';
import 'copy_job_repository.dart';
import 'copy_models.dart';

enum CopyPlanIntegrityStatus { pending, verified, inconsistent, unavailable, expired }

/// A complete, immutable snapshot tied to one preflight token. No guessed wire
/// aggregates: totals below are derived only after exhausting the item pages.
class CopyPlanIntegrity {
  const CopyPlanIntegrity(this.status, {this.token, this.items = const [], this.message, this.signature});
  final CopyPlanIntegrityStatus status;
  final String? token, message, signature;
  final List<CopyJobItem> items;
  bool get verified => status == CopyPlanIntegrityStatus.verified;
  int count(CopyPlanState state) => items.where((item) => item.planState == state).length;
  int get copyCount => count(CopyPlanState.copy);
  int get skippedCount => count(CopyPlanState.skipConflict);
  int get notApplicableCount => count(CopyPlanState.notApplicable);
  int get blockedCount => count(CopyPlanState.blocked);
  int get copyBytes => items.where((item) => item.planState == CopyPlanState.copy).fold(0, (total, item) => total + item.sourceSize!);
  String get summary => '${items.length} 条明细（$copyCount 个将复制 · $skippedCount 个将跳过 · $notApplicableCount 个不适用 · $blockedCount 个已阻止）';
}

class CopyPlanVerifier {
  const CopyPlanVerifier({this.maxPages = 200, this.maxItems = 50000, this.pageTimeout = const Duration(seconds: 15)});
  // App memory/time safeguards, not assertions about backend limits.
  final int maxPages, maxItems;
  final Duration pageTimeout;

  Future<CopyPlanIntegrity> verify(CopyPreview preview, CopyJobRepository? repository, {required bool Function() isCurrent}) async {
    CopyPlanIntegrity failure(CopyPlanIntegrityStatus status, String message) => CopyPlanIntegrity(status, token: preview.previewToken, message: message);
    if (repository == null) return failure(CopyPlanIntegrityStatus.unavailable, '预检明细暂不可用，请重新预检后再创建任务。');
    final items = <CopyJobItem>[], ids = <String>{}, cursors = <String>{};
    String? cursor;
    try {
      for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
        if (!isCurrent()) return failure(CopyPlanIntegrityStatus.unavailable, '核对已取消，请重新预检。');
        if (!DateTime.now().isBefore(preview.expiresAt)) return failure(CopyPlanIntegrityStatus.expired, '核对期间预检已过期，请重新预检。');
        final interrupt = Completer<CopyJobItemPage>();
        final watch = Timer.periodic(const Duration(milliseconds: 50), (_) {
          if ((!isCurrent() || !DateTime.now().isBefore(preview.expiresAt)) && !interrupt.isCompleted) interrupt.completeError(StateError('preflight interrupted'));
        });
        late CopyJobItemPage page;
        try {
          page = await Future.any([repository.previewItems(preview.itemsId, cursor: cursor), interrupt.future]).timeout(pageTimeout);
        } finally {
          watch.cancel();
        }
        if (!isCurrent()) return failure(CopyPlanIntegrityStatus.unavailable, '核对已取消，请重新预检。');
        if (!DateTime.now().isBefore(preview.expiresAt)) return failure(CopyPlanIntegrityStatus.expired, '核对期间预检已过期，请重新预检。');
        if (!page.protocolComplete) return failure(CopyPlanIntegrityStatus.unavailable, '明细分页信息不完整，请重新预检。');
        if (items.length + page.items.length > maxItems) return failure(CopyPlanIntegrityStatus.unavailable, '计划明细过多，无法完成核对，请缩小范围后重新预检。');
        for (final item in page.items) {
          if (item.copyItemId.trim().isEmpty || !ids.add(item.copyItemId)) return failure(CopyPlanIntegrityStatus.inconsistent, '计划明细标识重复或缺失，请重新预检。');
          if (!item.planMetadataValid ||
              item.planState == CopyPlanState.unknown ||
              item.sourceRelativePath?.trim().isNotEmpty != true ||
              item.sourceSize == null ||
              item.sourceSize! < 0 ||
              (item.sourceMediaId != null && item.sourceMediaId != preview.source.mediaId)) {
            return failure(CopyPlanIntegrityStatus.unavailable, '计划状态或文件信息不完整，请重新预检后再创建任务。');
          }
          if (item.planState == CopyPlanState.copy && (item.targetFilename?.trim().isNotEmpty != true || item.targetRelativeDirectory == null)) return failure(CopyPlanIntegrityStatus.unavailable, '计划目标路径不完整，请重新预检。');
          items.add(item);
        }
        if (page.hasMore) {
          final next = page.nextCursor;
          if (page.items.isEmpty || next == null || next.trim().isEmpty || !cursors.add(next)) return failure(CopyPlanIntegrityStatus.inconsistent, '计划分页未继续前进，请重新预检。');
          cursor = next;
          continue;
        }
        if (page.nextCursor != null) return failure(CopyPlanIntegrityStatus.inconsistent, '计划分页状态不一致，请重新预检。');
        final copies = items.where((item) => item.planState == CopyPlanState.copy).toList();
        final bytes = copies.fold<int>(0, (sum, item) => sum + item.sourceSize!);
        if (preview.logicalPhotoCount < 0 || preview.plannedFileCount < 0 || preview.totalBytes < 0 || copies.length != preview.plannedFileCount || bytes != preview.totalBytes || (items.isEmpty && preview.logicalPhotoCount > 0)) {
          return failure(CopyPlanIntegrityStatus.inconsistent, '预检统计与完整计划不一致，请重新预检后再创建任务。');
        }
        if (!isCurrent()) return failure(CopyPlanIntegrityStatus.unavailable, '核对已取消，请重新预检。');
        if (!DateTime.now().isBefore(preview.expiresAt)) return failure(CopyPlanIntegrityStatus.expired, '核对期间预检已过期，请重新预检。');
        // Item IDs may be regenerated per preview. Compare the actual decisions,
        // paths and file identities, independent of pagination order and token.
        final rows =
            items
                .map(
                  (item) => jsonEncode([
                    item.assetId,
                    item.sourceMediaId ?? preview.source.mediaId,
                    item.sourceRelativePath,
                    item.sourceSize,
                    item.sourceMtimeNs,
                    item.targetRelativeDirectory,
                    item.targetFilename,
                    item.planState.name,
                    item.conflictDecision,
                  ]),
                )
                .toList()
              ..sort();
        return CopyPlanIntegrity(
          CopyPlanIntegrityStatus.verified,
          token: preview.previewToken,
          items: List.unmodifiable(items),
          signature: jsonEncode([
            preview.logicalPhotoCount,
            preview.plannedFileCount,
            preview.totalBytes,
            preview.source.mediaId,
            preview.target.mediaId,
            preview.rawCount,
            preview.jpegCount,
            preview.videoCount,
            preview.companionCount,
            preview.unsupportedCount,
            preview.missingCount,
            preview.permissionErrorCount,
            preview.conflictCount,
            rows,
          ]),
        );
      }
      return failure(CopyPlanIntegrityStatus.unavailable, '计划分页超过核对上限，请缩小范围后重新预检。');
    } catch (error) {
      final expired = !DateTime.now().isBefore(preview.expiresAt) || (error is ApiException && error.code == 'COPY_PREVIEW_EXPIRED');
      return failure(expired ? CopyPlanIntegrityStatus.expired : CopyPlanIntegrityStatus.unavailable, '计划明细读取未完成或已过期，请重新预检后再创建任务。');
    }
  }
}
