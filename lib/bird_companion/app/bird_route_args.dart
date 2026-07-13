class GalleryArgs {
  const GalleryArgs(this.batchId);
  final String batchId;
}

class GroupReviewArgs {
  const GroupReviewArgs(this.batchId);
  final String batchId;
}

class PhotoDetailArgs {
  const PhotoDetailArgs(this.fileId);
  final String fileId;
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
