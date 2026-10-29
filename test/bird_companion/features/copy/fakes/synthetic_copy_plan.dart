import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';

/// Synthetic test data only. Counts/bytes are explicit, never inferred in App.
mixin SyntheticCopyPlan implements CopyJobRepository {
  int get syntheticFileCount;
  int get syntheticBytes;
  Future<CopyJobItemPage> Function(String, String?)? readPlan;

  @override
  Future<CopyJobItemPage> previewItems(String id, {String? cursor}) async {
    if (readPlan != null) return readPlan!(id, cursor);
    return CopyJobItemPage(
      items: [
        for (var i = 0; i < syntheticFileCount; i++)
          CopyJobItem(
            copyItemId: 'item-$i',
            sourceRelativePath: 'DCIM/$i.ARW',
            sourceSize: syntheticBytes ~/ syntheticFileCount + (i < syntheticBytes % syntheticFileCount ? 1 : 0),
            targetRelativeDirectory: '20261023',
            targetFilename: '$i.ARW',
            planState: CopyPlanState.copy,
          ),
      ],
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
