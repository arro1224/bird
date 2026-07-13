import 'package:equatable/equatable.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';

enum KeepState { pending, keep, discard, featured }

extension KeepStateWireValue on KeepState {
  static KeepState fromWire(String? value) => switch (value) {
    'keep' => KeepState.keep,
    'discard' => KeepState.discard,
    'featured' => KeepState.featured,
    _ => KeepState.pending,
  };

  String get wireValue => switch (this) {
    KeepState.pending => 'pending',
    KeepState.keep => 'keep',
    KeepState.discard => 'discard',
    KeepState.featured => 'featured',
  };
}

class BirdGroup extends Equatable {
  const BirdGroup({required this.id, required this.type, required this.representativeFileId, required this.memberFileIds, this.rankOrder = const [], this.members = const [], this.recommendationReasons = const [], this.capturedFrom, this.capturedTo});

  final String id;
  final String type;
  final String representativeFileId;
  final List<String> memberFileIds;
  final List<String> rankOrder;
  final List<PhotoSummary> members;
  final List<String> recommendationReasons;
  final DateTime? capturedFrom;
  final DateTime? capturedTo;

  factory BirdGroup.fromJson(Map<String, dynamic> json) => BirdGroup(
    id: json['group_id']?.toString() ?? '',
    type: json['group_type']?.toString() ?? 'scene',
    representativeFileId: json['representative_file_id']?.toString() ?? '',
    memberFileIds: (json['member_file_ids'] as List? ?? const []).map((value) => value.toString()).toList(),
    rankOrder: (json['rank_order'] as List? ?? const []).map((value) => value.toString()).toList(),
    members: (json['members'] as List? ?? const []).whereType<Map>().map((value) => PhotoSummary.fromJson(Map<String, dynamic>.from(value))).toList(),
    recommendationReasons: (json['recommendation_reasons'] as List? ?? const []).map((value) => value.toString()).toList(),
    capturedFrom: DateTime.tryParse(json['captured_from']?.toString() ?? ''),
    capturedTo: DateTime.tryParse(json['captured_to']?.toString() ?? ''),
  );

  @override
  List<Object?> get props => [id, type, representativeFileId, memberFileIds, rankOrder, members, recommendationReasons, capturedFrom, capturedTo];
}

class UserDecision extends Equatable {
  const UserDecision({required this.fileId, required this.keepState, this.userScore, this.userSpecies, this.userTags = const [], this.updatedAt, this.version});

  final String fileId;
  final KeepState keepState;
  final double? userScore;
  final String? userSpecies;
  final List<String> userTags;
  final DateTime? updatedAt;
  final int? version;

  Map<String, dynamic> toJson() => {
    'file_id': fileId,
    'keep_state': keepState.wireValue,
    'user_score': userScore,
    'user_species': userSpecies,
    'user_tags': userTags,
    'updated_at': updatedAt?.toIso8601String(),
    'version': version,
  };

  @override
  List<Object?> get props => [fileId, keepState, userScore, userSpecies, userTags, updatedAt, version];
}

class VersionHistory extends Equatable {
  const VersionHistory({required this.version, required this.source, required this.updatedAt, this.summary});

  final int version;
  final String source;
  final DateTime updatedAt;
  final String? summary;

  @override
  List<Object?> get props => [version, source, updatedAt, summary];
}
