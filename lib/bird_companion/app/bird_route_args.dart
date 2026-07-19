import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

class GalleryArgs {
  const GalleryArgs(this.batchId, {this.batchName, this.totalCount, this.initialQuery = const PhotoQuery()});
  final String batchId;
  final String? batchName;
  final int? totalCount;
  final PhotoQuery initialQuery;
}

class SceneListArgs {
  const SceneListArgs(this.batchId, {this.batchName, this.totalCount, this.burstGroupCount});

  final String batchId;
  final String? batchName;
  final int? totalCount;
  final int? burstGroupCount;
}

class GroupReviewArgs {
  const GroupReviewArgs(this.batchId, {this.sceneId, this.sceneName});
  final String batchId;
  final String? sceneId;
  final String? sceneName;
}

class PhotoDetailArgs {
  const PhotoDetailArgs(this.fileId, {this.displayIndex, this.totalCount, this.sequence = const []});
  final String fileId;
  final int? displayIndex;
  final int? totalCount;
  final List<String> sequence;
}

class CopyConfirmationArgs {
  const CopyConfirmationArgs(this.batchId);
  final String batchId;
}

class JobDetailArgs {
  const JobDetailArgs(this.jobId, {this.sourceBatchId});
  final String jobId;
  final String? sourceBatchId;
}

class ComparisonReviewArgs {
  const ComparisonReviewArgs({required this.groupId, required this.fileIds});
  final String groupId;
  final List<String> fileIds;
}

class ShellArgs {
  const ShellArgs({this.initialIndex = 0});
  final int initialIndex;
}

enum ConnectionEntryMode { initialSetup, addOrSwitch }

class ConnectionArgs {
  const ConnectionArgs({this.entryMode = ConnectionEntryMode.initialSetup});

  final ConnectionEntryMode entryMode;
}
