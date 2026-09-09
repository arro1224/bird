import 'package:equatable/equatable.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';

class BatchSummary extends Equatable {
  const BatchSummary({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.totalFiles,
    required this.analyzedCount,
    required this.reviewCount,
    required this.keepCount,
    required this.discardCount,
    required this.pendingCopyCount,
    required this.copyState,
    this.sceneCount = 0,
    this.burstGroupCount = 0,
    this.cover,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int totalFiles;
  final int analyzedCount;
  final int reviewCount;
  int get pendingReviewCount => reviewCount;
  final int keepCount;
  final int discardCount;
  final int pendingCopyCount;
  final String copyState;
  final int sceneCount;
  final int burstGroupCount;
  final PreviewRef? cover;

  factory BatchSummary.fromJson(Map<String, dynamic> json) => BatchSummary(
    id: ProtocolValidation.requiredId(json, 'project_id'),
    name: json['name']?.toString() ?? json['project_name']?.toString() ?? '未命名拍摄记录',
    createdAt:
        ProtocolValidation.optionalDateTime(json, 'created_at') ??
        (throw const ProtocolCompatibilityException(
          'created_at',
          '不能为空',
        )),
    totalFiles: ProtocolValidation.nonNegativeInt(json, 'total_files'),
    analyzedCount: ProtocolValidation.nonNegativeInt(
      json,
      'analyzed_count',
    ),
    reviewCount: json['pending_review_count'] != null ? ProtocolValidation.nonNegativeInt(json, 'pending_review_count') : ProtocolValidation.nonNegativeInt(json, 'review_count'),
    keepCount: ProtocolValidation.nonNegativeInt(json, 'keep_count'),
    discardCount: ProtocolValidation.nonNegativeInt(
      json,
      'discard_count',
    ),
    pendingCopyCount: ProtocolValidation.nonNegativeInt(
      json,
      'pending_copy_count',
    ),
    copyState: json['copy_state']?.toString() ?? 'unknown',
    sceneCount: (json['scene_count'] as num?)?.toInt() ?? 0,
    burstGroupCount: (json['burst_group_count'] as num?)?.toInt() ?? 0,
    cover: json['cover'] is Map ? PreviewRef.fromJson(Map<String, dynamic>.from(json['cover'] as Map)) : null,
  );

  Map<String, dynamic> toJson() => {
    'project_id': id,
    'name': name,
    'created_at': createdAt.toIso8601String(),
    'total_files': totalFiles,
    'analyzed_count': analyzedCount,
    'pending_review_count': reviewCount,
    // Keep the legacy field while older K7 firmware is still supported.
    'review_count': reviewCount,
    'keep_count': keepCount,
    'discard_count': discardCount,
    'pending_copy_count': pendingCopyCount,
    'copy_state': copyState,
    'scene_count': sceneCount,
    'burst_group_count': burstGroupCount,
    if (cover != null) 'cover': cover!.toJson(),
  };

  BatchSummary copyWith({
    int? reviewCount,
    int? keepCount,
    int? discardCount,
  }) => BatchSummary(
    id: id,
    name: name,
    createdAt: createdAt,
    totalFiles: totalFiles,
    analyzedCount: analyzedCount,
    reviewCount: reviewCount ?? this.reviewCount,
    keepCount: keepCount ?? this.keepCount,
    discardCount: discardCount ?? this.discardCount,
    pendingCopyCount: pendingCopyCount,
    copyState: copyState,
    sceneCount: sceneCount,
    burstGroupCount: burstGroupCount,
    cover: cover,
  );

  @override
  List<Object?> get props => [id, name, createdAt, totalFiles, analyzedCount, reviewCount, keepCount, discardCount, pendingCopyCount, copyState, sceneCount, burstGroupCount, cover];
}
