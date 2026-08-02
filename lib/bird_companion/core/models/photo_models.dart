import 'package:aves/bird_companion/core/models/json_value.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:equatable/equatable.dart';

enum AnalysisState { queued, processing, completed, lowConfidence, skipped, failed, unknown }

extension AnalysisStateWireValue on AnalysisState {
  static AnalysisState fromWire(String? value) => switch (value) {
    'queued' || 'pending' => AnalysisState.queued,
    'processing' || 'analyzing' => AnalysisState.processing,
    'completed' || 'complete' => AnalysisState.completed,
    'low_confidence' => AnalysisState.lowConfidence,
    'skipped' => AnalysisState.skipped,
    'failed' => AnalysisState.failed,
    _ => AnalysisState.unknown,
  };

  String get wireValue => switch (this) {
    AnalysisState.queued => 'queued',
    AnalysisState.processing => 'processing',
    AnalysisState.completed => 'completed',
    AnalysisState.lowConfidence => 'low_confidence',
    AnalysisState.skipped => 'skipped',
    AnalysisState.failed => 'failed',
    AnalysisState.unknown => 'unknown',
  };
}

enum ClarityState { clear, average, blurred, unknown }

extension ClarityStateWireValue on ClarityState {
  static ClarityState fromWire(String? value) => switch (value) {
    'clear' || 'sharp' => ClarityState.clear,
    'average' || 'soft' => ClarityState.average,
    'blurred' || 'blurry' => ClarityState.blurred,
    _ => ClarityState.unknown,
  };

  String get wireValue => switch (this) {
    ClarityState.clear => 'clear',
    ClarityState.average => 'average',
    ClarityState.blurred => 'blurred',
    ClarityState.unknown => 'unknown',
  };
}

class PreviewRef extends Equatable {
  const PreviewRef({this.thumbnailUri, this.previewUri, this.width, this.height});

  final Uri? thumbnailUri;
  final Uri? previewUri;
  final int? width;
  final int? height;

  factory PreviewRef.fromJson(Map<String, dynamic> json) => PreviewRef(
    thumbnailUri: Uri.tryParse(json.stringOrNull('thumb_ref') ?? ''),
    previewUri: Uri.tryParse(json.stringOrNull('preview_ref') ?? ''),
    width: json.intOrNull('width'),
    height: json.intOrNull('height'),
  );

  Map<String, dynamic> toJson() => {
    if (thumbnailUri != null) 'thumb_ref': thumbnailUri.toString(),
    if (previewUri != null) 'preview_ref': previewUri.toString(),
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  };

  @override
  List<Object?> get props => [thumbnailUri, previewUri, width, height];
}

class SubjectBox extends Equatable {
  const SubjectBox({required this.x, required this.y, required this.width, required this.height, this.confidence, this.type});

  final double x;
  final double y;
  final double width;
  final double height;
  final double? confidence;
  final String? type;

  factory SubjectBox.fromJson(Map<String, dynamic> json) {
    final box = json.mapOrNull('bbox') ?? json;
    for (final field in const ['x', 'y', 'width', 'height']) {
      if (!box.containsKey(field)) {
        throw ProtocolCompatibilityException('bbox.$field', '不能为空');
      }
    }
    final x = ProtocolValidation.unitInterval(box, 'x');
    final y = ProtocolValidation.unitInterval(box, 'y');
    final width = ProtocolValidation.unitInterval(box, 'width');
    final height = ProtocolValidation.unitInterval(box, 'height');
    if (x + width > 1 || y + height > 1) {
      throw const ProtocolCompatibilityException(
        'bbox',
        '必须完全位于归一化图像范围内',
      );
    }
    return SubjectBox(
      x: x,
      y: y,
      width: width,
      height: height,
      confidence: json['confidence'] == null ? null : ProtocolValidation.unitInterval(json, 'confidence'),
      type: json.stringOrNull('subject_type'),
    );
  }

  Map<String, dynamic> toJson() => {
    'bbox': {'x': x, 'y': y, 'width': width, 'height': height},
    if (confidence != null) 'confidence': confidence,
    if (type != null) 'subject_type': type,
  };

  @override
  List<Object?> get props => [x, y, width, height, confidence, type];
}

class SpeciesCandidate extends Equatable {
  const SpeciesCandidate({required this.name, this.speciesId, this.englishName, this.latinName, required this.confidence});

  final String name;
  final String? speciesId;
  final String? englishName;
  final String? latinName;
  final double confidence;

  factory SpeciesCandidate.fromJson(Map<String, dynamic> json) => SpeciesCandidate(
    name: json.stringOrNull('name') ?? json.stringOrNull('species_name') ?? '未知鸟种',
    speciesId: json.stringOrNull('species_id') ?? json.stringOrNull('id'),
    englishName: json.stringOrNull('english_name'),
    latinName: json.stringOrNull('latin_name'),
    confidence: ProtocolValidation.unitInterval(json, 'confidence'),
  );

  Map<String, dynamic> toJson() => {
    if (speciesId != null) 'species_id': speciesId,
    'name': name,
    if (englishName != null) 'english_name': englishName,
    if (latinName != null) 'latin_name': latinName,
    'confidence': confidence,
  };

  @override
  List<Object?> get props => [name, speciesId, englishName, latinName, confidence];
}

class RecognitionResult extends Equatable {
  const RecognitionResult({required this.candidates, this.isLowConfidence = false, this.modelVersion});

  final List<SpeciesCandidate> candidates;
  final bool isLowConfidence;
  final String? modelVersion;

  factory RecognitionResult.fromJson(Map<String, dynamic> json) => RecognitionResult(
    candidates: json.listOrEmpty('species_topn').whereType<Map>().map((value) => SpeciesCandidate.fromJson(Map<String, dynamic>.from(value))).toList(),
    isLowConfidence: json.boolOrNull('review_flag') ?? json.boolOrNull('low_confidence') ?? false,
    modelVersion: json.stringOrNull('model_version'),
  );

  Map<String, dynamic> toJson() => {
    'species_topn': candidates.map((candidate) => candidate.toJson()).toList(),
    'low_confidence': isLowConfidence,
    if (modelVersion != null) 'model_version': modelVersion,
  };

  @override
  List<Object?> get props => [candidates, isLowConfidence, modelVersion];
}

class RatingResult extends Equatable {
  const RatingResult({required this.totalScore, this.qualityScore, this.eyeScore, this.compositionScore, this.reasonTags = const []});

  final double totalScore;
  final double? qualityScore;
  final double? eyeScore;
  final double? compositionScore;
  final List<String> reasonTags;

  factory RatingResult.fromJson(Map<String, dynamic> json) => RatingResult(
    totalScore: json.doubleOrNull('total_score') ?? 0,
    qualityScore: json.doubleOrNull('quality_score'),
    eyeScore: json.doubleOrNull('eye_score'),
    compositionScore: json.doubleOrNull('composition_score'),
    reasonTags: json.listOrEmpty('reason_tags').map((value) => value.toString()).toList(),
  );

  Map<String, dynamic> toJson() => {
    'total_score': totalScore,
    if (qualityScore != null) 'quality_score': qualityScore,
    if (eyeScore != null) 'eye_score': eyeScore,
    if (compositionScore != null) 'composition_score': compositionScore,
    'reason_tags': reasonTags,
  };

  @override
  List<Object?> get props => [totalScore, qualityScore, eyeScore, compositionScore, reasonTags];
}

class BirdTag extends Equatable {
  const BirdTag({required this.id, required this.name, required this.source, this.editable = false});

  final String id;
  final String name;
  final String source;
  final bool editable;

  factory BirdTag.fromJson(Map<String, dynamic> json) => BirdTag(
    id: json.stringOrNull('tag_id') ?? json.stringOrNull('id') ?? '',
    name: json.stringOrNull('tag_name') ?? json.stringOrNull('name') ?? '',
    source: json.stringOrNull('source') ?? 'system',
    editable: json.boolOrNull('editable') ?? false,
  );

  Map<String, dynamic> toJson() => {
    'tag_id': id,
    'tag_name': name,
    'source': source,
    'editable': editable,
  };

  @override
  List<Object?> get props => [id, name, source, editable];
}

class PhotoSummary extends Equatable {
  const PhotoSummary({
    required this.id,
    required this.filename,
    required this.format,
    required this.preview,
    required this.analysisState,
    this.recognition,
    this.rating,
    this.groupId,
    this.sceneId,
    this.keepState,
    this.clarityState = ClarityState.unknown,
    this.isRecommended = false,
    this.userTags = const [],
    this.capturedAt,
    this.version,
  });

  final String id;
  final String filename;
  final String format;
  final PreviewRef preview;
  final AnalysisState analysisState;
  final RecognitionResult? recognition;
  final RatingResult? rating;
  final String? groupId;
  final String? sceneId;
  final String? keepState;
  final ClarityState clarityState;
  final bool isRecommended;
  final List<String> userTags;
  final int? version;

  /// Device timestamp used by the gallery's "newest first" ordering.
  final DateTime? capturedAt;

  factory PhotoSummary.fromJson(Map<String, dynamic> json) => PhotoSummary(
    id: ProtocolValidation.requiredId(json, 'file_id'),
    filename: json.stringOrNull('filename') ?? '',
    format: json.stringOrNull('format') ?? '',
    preview: PreviewRef.fromJson(json),
    analysisState: AnalysisStateWireValue.fromWire(json.stringOrNull('analysis_state')),
    recognition: json.mapOrNull('recognition') == null ? null : RecognitionResult.fromJson(json.mapOrNull('recognition')!),
    rating: json.mapOrNull('rating') == null ? null : RatingResult.fromJson(json.mapOrNull('rating')!),
    groupId: json.stringOrNull('group_id'),
    sceneId: json.stringOrNull('scene_id'),
    keepState: json.stringOrNull('keep_state'),
    clarityState: ClarityStateWireValue.fromWire(json.stringOrNull('clarity_state')),
    isRecommended: json.boolOrNull('is_recommended') ?? false,
    userTags: json.listOrEmpty('user_tags').map((value) => value.toString()).toList(),
    capturedAt: json.containsKey('captured_at') ? ProtocolValidation.optionalDateTime(json, 'captured_at') : ProtocolValidation.optionalDateTime(json, 'capturedAt'),
    version: ProtocolValidation.optionalNonNegativeInt(json, 'version'),
  );

  Map<String, dynamic> toJson() => {
    'file_id': id,
    'filename': filename,
    'format': format,
    ...preview.toJson(),
    'analysis_state': analysisState.wireValue,
    if (recognition != null) 'recognition': recognition!.toJson(),
    if (rating != null) 'rating': rating!.toJson(),
    if (groupId != null) 'group_id': groupId,
    if (sceneId != null) 'scene_id': sceneId,
    if (keepState != null) 'keep_state': keepState,
    if (clarityState != ClarityState.unknown) 'clarity_state': clarityState.wireValue,
    'is_recommended': isRecommended,
    'user_tags': userTags,
    if (capturedAt != null) 'captured_at': capturedAt!.toIso8601String(),
    if (version != null) 'version': version,
  };

  /// Returns a local view of this photo after a review decision is saved.
  ///
  /// The review flows update this immediately so their selected-state controls
  /// never wait for a later gallery reload to reflect a successful action.
  PhotoSummary copyWith({String? keepState}) => PhotoSummary(
    id: id,
    filename: filename,
    format: format,
    preview: preview,
    analysisState: analysisState,
    recognition: recognition,
    rating: rating,
    groupId: groupId,
    sceneId: sceneId,
    keepState: keepState ?? this.keepState,
    clarityState: clarityState,
    isRecommended: isRecommended,
    userTags: userTags,
    capturedAt: capturedAt,
    version: version,
  );

  @override
  List<Object?> get props => [
    id,
    filename,
    format,
    preview,
    analysisState,
    recognition,
    rating,
    groupId,
    sceneId,
    keepState,
    clarityState,
    isRecommended,
    userTags,
    capturedAt,
    version,
  ];
}

class PhotoDetail extends Equatable {
  const PhotoDetail({required this.summary, this.subjects = const [], this.tags = const [], this.exif = const {}});

  final PhotoSummary summary;
  final List<SubjectBox> subjects;
  final List<BirdTag> tags;
  final Map<String, dynamic> exif;

  Map<String, dynamic> toJson() => {
    'file': summary.toJson(),
    'subjects': subjects.map((subject) => subject.toJson()).toList(),
    'tags': tags.map((tag) => tag.toJson()).toList(),
    'exif': exif,
  };

  @override
  List<Object?> get props => [summary, subjects, tags, exif];
}
