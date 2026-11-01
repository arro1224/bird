class ImportJobRequest {
  const ImportJobRequest({
    this.generateThumbnails = true,
    this.generatePreviews = true,
  });

  final bool generateThumbnails;
  final bool generatePreviews;

  Map<String, dynamic> toJson() => {
    'source': 'card',
    'read_only': true,
    'generate_thumbnails': generateThumbnails,
    'generate_previews': generatePreviews,
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
