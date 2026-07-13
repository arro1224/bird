/// Query values are kept in one serialisable object so the gallery can restore
/// its exact filter state after returning from a photo detail page.
class PhotoQuery {
  const PhotoQuery({
    this.cursor,
    this.pageSize = 60,
    this.sort = 'captured_at_desc',
    this.species,
    this.search,
    this.minScore,
    this.minConfidence,
    this.tags = const [],
    this.keepState,
    this.analysisState,
    this.groupId,
  });

  final String? cursor;
  final int pageSize;
  final String sort;
  final String? species;
  final String? search;
  final double? minScore;
  final double? minConfidence;
  final List<String> tags;
  final String? keepState;
  final String? analysisState;
  final String? groupId;

  Map<String, dynamic> get parameters => {
    'page_size': pageSize,
    'sort': sort,
    if (cursor != null) 'cursor': cursor,
    if (species?.isNotEmpty == true) 'species': species,
    if (search?.isNotEmpty == true) 'search': search,
    if (minScore != null) 'min_score': minScore,
    if (minConfidence != null) 'min_confidence': minConfidence,
    if (tags.isNotEmpty) 'tags': tags.join(','),
    if (keepState?.isNotEmpty == true) 'keep_state': keepState,
    if (analysisState?.isNotEmpty == true) 'analysis_state': analysisState,
    if (groupId?.isNotEmpty == true) 'group_id': groupId,
  };

  List<String> get activeLabels => [
    if (species?.isNotEmpty == true) '鸟种：$species',
    if (search?.isNotEmpty == true) '搜索：$search',
    if (minScore != null) '评分 ≥ $minScore',
    if (minConfidence != null) '置信度 ≥ $minConfidence',
    if (tags.isNotEmpty) ...tags.map((tag) => '#$tag'),
    if (keepState?.isNotEmpty == true) '保留：$keepState',
    if (analysisState?.isNotEmpty == true) '分析：$analysisState',
    if (groupId?.isNotEmpty == true) '分组：$groupId',
  ];

  PhotoQuery next(String? nextCursor) => copyWith(cursor: nextCursor);

  PhotoQuery copyWith({
    String? cursor,
    int? pageSize,
    String? sort,
    String? species,
    String? search,
    double? minScore,
    double? minConfidence,
    List<String>? tags,
    String? keepState,
    String? analysisState,
    String? groupId,
    bool clearCursor = false,
  }) => PhotoQuery(
    cursor: clearCursor ? null : cursor ?? this.cursor,
    pageSize: pageSize ?? this.pageSize,
    sort: sort ?? this.sort,
    species: species ?? this.species,
    search: search ?? this.search,
    minScore: minScore ?? this.minScore,
    minConfidence: minConfidence ?? this.minConfidence,
    tags: tags ?? this.tags,
    keepState: keepState ?? this.keepState,
    analysisState: analysisState ?? this.analysisState,
    groupId: groupId ?? this.groupId,
  );
}
