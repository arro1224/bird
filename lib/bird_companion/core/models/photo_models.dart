import 'package:aves/bird_companion/core/models/json_value.dart';
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
    return SubjectBox(
      x: box.doubleOrNull('x') ?? 0,
      y: box.doubleOrNull('y') ?? 0,
      width: box.doubleOrNull('width') ?? 0,
      height: box.doubleOrNull('height') ?? 0,
      confidence: json.doubleOrNull('confidence'),
      type: json.stringOrNull('subject_type'),
    );
  }

  @override
  List<Object?> get props => [x, y, width, height, confidence, type];
}

class SpeciesCandidate extends Equatable {
  const SpeciesCandidate({required this.name, this.englishName, this.latinName, required this.confidence});

  final String name;
  final String? englishName;
  final String? latinName;
  final double confidence;

  factory SpeciesCandidate.fromJson(Map<String, dynamic> json) => SpeciesCandidate(
    name: json.stringOrNull('name') ?? json.stringOrNull('species_name') ?? '未知鸟种',
    englishName: json.stringOrNull('english_name'),
    latinName: json.stringOrNull('latin_name'),
    confidence: json.doubleOrNull('confidence') ?? 0,
  );

  @override
  List<Object?> get props => [name, englishName, latinName, confidence];
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

  @override
  List<Object?> get props => [candidates, isLowConfidence, modelVersion];
}

class RatingResult extends Equatable {
  const RatingResult({required this.totalScore, this.qualityScore, this.compositionScore, this.reasonTags = const []});

  final double totalScore;
  final double? qualityScore;
  final double? compositionScore;
  final List<String> reasonTags;

  factory RatingResult.fromJson(Map<String, dynamic> json) => RatingResult(
    totalScore: json.doubleOrNull('total_score') ?? 0,
    qualityScore: json.doubleOrNull('quality_score'),
    compositionScore: json.doubleOrNull('composition_score'),
    reasonTags: json.listOrEmpty('reason_tags').map((value) => value.toString()).toList(),
  );

  @override
  List<Object?> get props => [totalScore, qualityScore, compositionScore, reasonTags];
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
    this.keepState,
    this.userTags = const [],
    this.capturedAt,
  });

  final String id;
  final String filename;
  final String format;
  final PreviewRef preview;
  final AnalysisState analysisState;
  final RecognitionResult? recognition;
  final RatingResult? rating;
  final String? groupId;
  final String? keepState;
  final List<String> userTags;

  /// Device timestamp used by the gallery's "newest first" ordering.
  final DateTime? capturedAt;

  factory PhotoSummary.fromJson(Map<String, dynamic> json) => PhotoSummary(
    id: json.stringOrNull('file_id') ?? '',
    filename: json.stringOrNull('filename') ?? '',
    format: json.stringOrNull('format') ?? '',
    preview: PreviewRef.fromJson(json),
    analysisState: AnalysisStateWireValue.fromWire(json.stringOrNull('analysis_state')),
    recognition: json.mapOrNull('recognition') == null ? null : RecognitionResult.fromJson(json.mapOrNull('recognition')!),
    rating: json.mapOrNull('rating') == null ? null : RatingResult.fromJson(json.mapOrNull('rating')!),
    groupId: json.stringOrNull('group_id'),
    keepState: json.stringOrNull('keep_state'),
    userTags: json.listOrEmpty('user_tags').map((value) => value.toString()).toList(),
    capturedAt: DateTime.tryParse(json.stringOrNull('captured_at') ?? json.stringOrNull('capturedAt') ?? ''),
  );

  @override
  List<Object?> get props => [id, filename, format, preview, analysisState, recognition, rating, groupId, keepState, userTags, capturedAt];
}

class PhotoDetail extends Equatable {
  const PhotoDetail({required this.summary, this.subjects = const [], this.tags = const [], this.exif = const {}});

  final PhotoSummary summary;
  final List<SubjectBox> subjects;
  final List<BirdTag> tags;
  final Map<String, dynamic> exif;

  @override
  List<Object?> get props => [summary, subjects, tags, exif];
}
