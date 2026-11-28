import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';

/// Freezes the album's keep+featured union using the existing selection API.
/// Sending keep_state=keep as a copy filter would silently exclude featured.
Future<CopySelectionSnapshot> createRetainedCopySelection({
  required String batchId,
  required PhotoQuery query,
  required PhotoRepository photos,
  required CopyRepository copies,
  required bool Function() isCurrent,
}) async {
  final ids = <String>{};
  final seenCursors = <String>{};
  String? cursor;
  var revision = 0;
  do {
    if (!isCurrent()) throw StateError('盒子或筛选已变化，请重新选择复制范围');
    final page = await photos.page(batchId, query.copyWith(pageSize: 200, cursor: cursor, clearCursor: cursor == null));
    if (!isCurrent()) throw StateError('盒子或筛选已变化，请重新选择复制范围');
    if (!page.resultComplete) throw StateError('筛选结果尚不完整，请连接盒子并刷新后再复制');
    for (final photo in page.items) {
      ids.add(photo.assetId ?? photo.id);
      if ((photo.version ?? 0) > revision) revision = photo.version!;
    }
    if (!page.hasMore) break;
    cursor = page.nextCursor;
    if (cursor == null || !seenCursors.add(cursor)) throw StateError('筛选分页未完成，请刷新后重试');
  } while (true);
  if (ids.isEmpty) throw StateError('当前筛选没有可复制的照片');
  final selection = await copies.createSelection(batchId, ids.toList(growable: false), clientRevision: revision);
  if (!isCurrent()) throw StateError('盒子或筛选已变化，请重新选择复制范围');
  if (selection.assetCount != ids.length) throw StateError('照片范围已变化，请刷新后重试');
  return selection;
}
