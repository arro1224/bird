import 'package:equatable/equatable.dart';

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
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int totalFiles;
  final int analyzedCount;
  final int reviewCount;
  final int keepCount;
  final int discardCount;
  final int pendingCopyCount;
  final String copyState;

  factory BatchSummary.fromJson(Map<String, dynamic> json) => BatchSummary(
    id: json['project_id']?.toString() ?? '',
    name: json['name']?.toString() ?? json['project_name']?.toString() ?? '未命名批次',
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
    analyzedCount: (json['analyzed_count'] as num?)?.toInt() ?? 0,
    reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
    keepCount: (json['keep_count'] as num?)?.toInt() ?? 0,
    discardCount: (json['discard_count'] as num?)?.toInt() ?? 0,
    pendingCopyCount: (json['pending_copy_count'] as num?)?.toInt() ?? 0,
    copyState: json['copy_state']?.toString() ?? 'unknown',
  );

  @override
  List<Object?> get props => [id, name, createdAt, totalFiles, analyzedCount, reviewCount, keepCount, discardCount, pendingCopyCount, copyState];
}
