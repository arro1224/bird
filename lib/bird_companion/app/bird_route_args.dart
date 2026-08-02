import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

class PhotoSequencePage {
  const PhotoSequencePage({required this.ids, required this.hasMore});

  final List<String> ids;
  final bool hasMore;
}

typedef PhotoSequenceLoader = Future<PhotoSequencePage> Function();

/// Carries the user's position through the complete photo-review hierarchy.
///
/// Route argument classes keep their legacy fields for compatibility, while
/// all in-app deep links use this value as the single source of navigation
/// context.
class ReviewContext {
  const ReviewContext({
    required this.batchId,
    this.batchName,
    this.sceneId,
    this.sceneName,
    this.groupId,
    this.groupName,
    this.photoIds = const [],
    this.currentIndex = 0,
  });

  final String batchId;
  final String? batchName;
  final String? sceneId;
  final String? sceneName;
  final String? groupId;
  final String? groupName;
  final List<String> photoIds;
  final int currentIndex;

  int get safeCurrentIndex {
    if (photoIds.isEmpty) return 0;
    return currentIndex.clamp(0, photoIds.length - 1);
  }

  String? get currentPhotoId => photoIds.isEmpty ? null : photoIds[safeCurrentIndex];

  ReviewContext enterScene(String id, {String? name}) => ReviewContext(
    batchId: batchId,
    batchName: batchName,
    sceneId: id,
    sceneName: name,
  );

  ReviewContext enterGroup(
    String id, {
    String? name,
    List<String> photos = const [],
    int initialIndex = 0,
  }) => ReviewContext(
    batchId: batchId,
    batchName: batchName,
    sceneId: sceneId,
    sceneName: sceneName,
    groupId: id,
    groupName: name,
    photoIds: photos,
    currentIndex: initialIndex,
  );

  ReviewContext openPhotos(List<String> photos, {int initialIndex = 0}) => ReviewContext(
    batchId: batchId,
    batchName: batchName,
    sceneId: sceneId,
    sceneName: sceneName,
    groupId: groupId,
    groupName: groupName,
    photoIds: photos,
    currentIndex: initialIndex,
  );

  ReviewContext moveTo(int index) => ReviewContext(
    batchId: batchId,
    batchName: batchName,
    sceneId: sceneId,
    sceneName: sceneName,
    groupId: groupId,
    groupName: groupName,
    photoIds: photoIds,
    currentIndex: photoIds.isEmpty ? 0 : index.clamp(0, photoIds.length - 1),
  );
}

class GalleryArgs {
  const GalleryArgs(
    this.batchId, {
    this.batchName,
    this.createdAt,
    this.totalCount,
    this.pendingCount,
    this.keepCount,
    this.discardCount,
    this.initialQuery = const PhotoQuery(),
    this.restoreSavedView = true,
    this.reviewContext,
  });
  final String batchId;
  final String? batchName;
  final DateTime? createdAt;
  final int? totalCount;
  final int? pendingCount;
  final int? keepCount;
  final int? discardCount;
  final PhotoQuery initialQuery;
  final bool restoreSavedView;
  final ReviewContext? reviewContext;

  ReviewContext get context => reviewContext ?? ReviewContext(batchId: batchId, batchName: batchName);
}

class SceneListArgs {
  const SceneListArgs(
    this.batchId, {
    this.batchName,
    this.totalCount,
    this.burstGroupCount,
    this.reviewContext,
  });

  final String batchId;
  final String? batchName;
  final int? totalCount;
  final int? burstGroupCount;
  final ReviewContext? reviewContext;

  ReviewContext get context => reviewContext ?? ReviewContext(batchId: batchId, batchName: batchName);
}

class GroupReviewArgs {
  const GroupReviewArgs(
    this.batchId, {
    this.sceneId,
    this.sceneName,
    this.reviewContext,
  });
  final String batchId;
  final String? sceneId;
  final String? sceneName;
  final ReviewContext? reviewContext;

  ReviewContext get context =>
      reviewContext ??
      ReviewContext(
        batchId: batchId,
        sceneId: sceneId,
        sceneName: sceneName,
      );
}

class PhotoDetailArgs {
  const PhotoDetailArgs(
    this.fileId, {
    this.displayIndex,
    this.totalCount,
    this.sequence = const [],
    this.hasMoreSequence = false,
    this.loadMoreSequence,
    this.reviewContext,
  });

  factory PhotoDetailArgs.fromReview(
    ReviewContext context, {
    String? fileId,
    int? totalCount,
    bool hasMoreSequence = false,
    PhotoSequenceLoader? loadMoreSequence,
  }) {
    final resolvedId = fileId ?? context.currentPhotoId ?? '';
    final index = context.photoIds.indexOf(resolvedId);
    return PhotoDetailArgs(
      resolvedId,
      displayIndex: index < 0 ? null : index + 1,
      totalCount: totalCount ?? (context.photoIds.isEmpty ? null : context.photoIds.length),
      sequence: context.photoIds,
      hasMoreSequence: hasMoreSequence,
      loadMoreSequence: loadMoreSequence,
      reviewContext: index < 0 ? context : context.moveTo(index),
    );
  }

  final String fileId;
  final int? displayIndex;
  final int? totalCount;
  final List<String> sequence;
  final bool hasMoreSequence;
  final PhotoSequenceLoader? loadMoreSequence;
  final ReviewContext? reviewContext;
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
  const ComparisonReviewArgs({
    required this.groupId,
    required this.fileIds,
    this.reviewContext,
    this.groups = const [],
    this.initialGroupIndex = 0,
  });

  factory ComparisonReviewArgs.fromReview(
    ReviewContext context, {
    List<ReviewContext> groups = const [],
    int initialGroupIndex = 0,
  }) => ComparisonReviewArgs(
    groupId: context.groupId ?? '',
    fileIds: context.photoIds,
    reviewContext: context,
    groups: groups,
    initialGroupIndex: initialGroupIndex,
  );

  final String groupId;
  final List<String> fileIds;
  final ReviewContext? reviewContext;
  final List<ReviewContext> groups;
  final int initialGroupIndex;
}

class ShellArgs {
  const ShellArgs({this.initialIndex = 0, this.initialRoute});
  final int initialIndex;
  final String? initialRoute;
}

enum ConnectionEntryMode { initialSetup, addOrSwitch }

class ConnectionArgs {
  const ConnectionArgs({this.entryMode = ConnectionEntryMode.initialSetup});

  final ConnectionEntryMode entryMode;
}
