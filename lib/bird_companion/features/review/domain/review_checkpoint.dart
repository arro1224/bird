import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

class ReviewCheckpoint {
  const ReviewCheckpoint({
    required this.deviceId,
    required this.batchId,
    required this.updatedAt,
    this.batchName,
    this.sceneId,
    this.sceneName,
    this.groupId,
    this.groupName,
    this.fileId,
    this.photoIds = const [],
    this.currentIndex = 0,
    this.query = const PhotoQuery(),
  });

  final String deviceId;
  final String batchId;
  final String? batchName;
  final String? sceneId;
  final String? sceneName;
  final String? groupId;
  final String? groupName;
  final String? fileId;
  final List<String> photoIds;
  final int currentIndex;
  final PhotoQuery query;
  final DateTime updatedAt;

  factory ReviewCheckpoint.fromContext({
    required String deviceId,
    required ReviewContext context,
    PhotoQuery query = const PhotoQuery(),
    DateTime? updatedAt,
  }) => ReviewCheckpoint(
    deviceId: deviceId,
    batchId: context.batchId,
    batchName: context.batchName,
    sceneId: context.sceneId,
    sceneName: context.sceneName,
    groupId: context.groupId,
    groupName: context.groupName,
    fileId: context.currentPhotoId,
    photoIds: context.groupId == null ? const [] : context.photoIds,
    currentIndex: context.safeCurrentIndex,
    query: query,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  factory ReviewCheckpoint.fromJson(Map<String, dynamic> json) {
    final rawQuery = json['query'];
    return ReviewCheckpoint(
      deviceId: json['device_id']?.toString() ?? '',
      batchId: json['batch_id']?.toString() ?? '',
      batchName: json['batch_name']?.toString(),
      sceneId: json['scene_id']?.toString(),
      sceneName: json['scene_name']?.toString(),
      groupId: json['group_id']?.toString(),
      groupName: json['group_name']?.toString(),
      fileId: json['file_id']?.toString(),
      photoIds: (json['photo_ids'] as List? ?? const []).map((value) => value.toString()).toList(growable: false),
      currentIndex: (json['current_index'] as num?)?.toInt() ?? 0,
      query: rawQuery is Map ? PhotoQuery.fromJson(Map<String, dynamic>.from(rawQuery)) : const PhotoQuery(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  ReviewContext toReviewContext() => ReviewContext(
    batchId: batchId,
    batchName: batchName,
    sceneId: sceneId,
    sceneName: sceneName,
    groupId: groupId,
    groupName: groupName,
    photoIds: photoIds,
    currentIndex: currentIndex,
  );

  ReviewCheckpoint withQuery(
    PhotoQuery value, {
    DateTime? updatedAt,
  }) => ReviewCheckpoint(
    deviceId: deviceId,
    batchId: batchId,
    batchName: batchName,
    sceneId: sceneId,
    sceneName: sceneName,
    groupId: groupId,
    groupName: groupName,
    fileId: fileId,
    photoIds: photoIds,
    currentIndex: currentIndex,
    query: value,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'batch_id': batchId,
    if (batchName != null) 'batch_name': batchName,
    if (sceneId != null) 'scene_id': sceneId,
    if (sceneName != null) 'scene_name': sceneName,
    if (groupId != null) 'group_id': groupId,
    if (groupName != null) 'group_name': groupName,
    if (fileId != null) 'file_id': fileId,
    'photo_ids': photoIds,
    'current_index': currentIndex,
    'query': query.toJson(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}
