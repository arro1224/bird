import 'package:aves/bird_companion/core/models/json_value.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:equatable/equatable.dart';

class SceneSummary extends Equatable {
  const SceneSummary({
    required this.id,
    required this.batchId,
    required this.name,
    required this.photoCount,
    required this.burstGroupCount,
    this.capturedFrom,
    this.capturedTo,
    this.cover,
  });

  final String id;
  final String batchId;
  final String name;
  final int photoCount;
  final int burstGroupCount;
  final DateTime? capturedFrom;
  final DateTime? capturedTo;
  final PreviewRef? cover;

  factory SceneSummary.fromJson(Map<String, dynamic> json) => SceneSummary(
    id: json.stringOrNull('scene_id') ?? '',
    batchId: json.stringOrNull('project_id') ?? json.stringOrNull('batch_id') ?? '',
    name: json.stringOrNull('name') ?? '未命名场景',
    photoCount: json.intOrNull('photo_count') ?? 0,
    burstGroupCount: json.intOrNull('burst_group_count') ?? 0,
    capturedFrom: DateTime.tryParse(json.stringOrNull('captured_from') ?? ''),
    capturedTo: DateTime.tryParse(json.stringOrNull('captured_to') ?? ''),
    cover: json.mapOrNull('cover') == null ? null : PreviewRef.fromJson(json.mapOrNull('cover')!),
  );

  Map<String, dynamic> toJson() => {
    'scene_id': id,
    'project_id': batchId,
    'name': name,
    'photo_count': photoCount,
    'burst_group_count': burstGroupCount,
    if (capturedFrom != null) 'captured_from': capturedFrom!.toIso8601String(),
    if (capturedTo != null) 'captured_to': capturedTo!.toIso8601String(),
    if (cover != null) 'cover': cover!.toJson(),
  };

  @override
  List<Object?> get props => [id, batchId, name, photoCount, burstGroupCount, capturedFrom, capturedTo, cover];
}
