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
  const AnalysisJobRequest({this.includeGrouping = true, this.smartFollow});

  final bool includeGrouping;
  final Map<String, dynamic>? smartFollow;

  Map<String, dynamic> toJson() => {
    'mode': 'standard',
    'include_grouping': includeGrouping,
    if (smartFollow != null) 'smart_follow': smartFollow,
  };
}
