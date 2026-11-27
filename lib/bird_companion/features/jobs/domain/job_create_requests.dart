import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

class AutoAnalysisRequest {
  const AutoAnalysisRequest({this.includeGrouping = true, this.smartFollow});
  final bool includeGrouping;
  final SmartFollowStartRequest? smartFollow;
  Map<String, dynamic> toJson() => {
    'mode': 'new_only',
    'existing_result_policy': 'skip',
    'include_grouping': includeGrouping,
    'smart_follow': smartFollow == null
        ? null
        : {
            'target_media_id': smartFollow!.targetMediaId,
            'eligibility_mode': smartFollow!.eligibilityMode,
            'pair_policy': smartFollow!.pairPolicy,
            'conflict_strategy': smartFollow!.conflictStrategy,
            'review_export_enabled': smartFollow!.reviewExportEnabled,
          },
  };
}

class ImportJobRequest {
  const ImportJobRequest({
    this.generateThumbnails = true,
    this.generatePreviews = true,
    this.autoAnalysis,
    this.idempotencyKey,
  });

  final bool generateThumbnails;
  final bool generatePreviews;
  final AutoAnalysisRequest? autoAnalysis;
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => {
    'source': 'card',
    'read_only': true,
    'generate_thumbnails': generateThumbnails,
    'generate_previews': generatePreviews,
    if (autoAnalysis != null) 'auto_analysis': autoAnalysis!.toJson(),
  };
}

class AnalysisJobRequest {
  const AnalysisJobRequest({this.includeGrouping = true, this.smartFollow, this.idempotencyKey});

  final bool includeGrouping;
  final Map<String, dynamic>? smartFollow;
  // Transport-only. Never add this value to the analysis request body.
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => {
    'mode': 'standard',
    'include_grouping': includeGrouping,
    if (smartFollow != null) 'smart_follow': smartFollow,
  };
}
