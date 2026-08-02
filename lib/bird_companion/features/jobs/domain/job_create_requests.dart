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
  const AnalysisJobRequest({this.includeGrouping = true});

  final bool includeGrouping;

  Map<String, dynamic> toJson() => {
    'mode': 'standard',
    'include_grouping': includeGrouping,
  };
}
