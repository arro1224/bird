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
    this.clarityState,
    this.recognitionState,
    this.recommendedOnly = false,
    this.groupId,
    this.sceneId,
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
  final String? clarityState;
  final String? recognitionState;
  final bool recommendedOnly;
  final String? groupId;
  final String? sceneId;

  factory PhotoQuery.fromJson(Map<String, dynamic> json) => PhotoQuery(
    pageSize: (json['page_size'] as num?)?.toInt() ?? 60,
    sort: json['sort']?.toString() ?? 'captured_at_desc',
    species: json['species']?.toString(),
    search: json['search']?.toString(),
    minScore: (json['min_score'] as num?)?.toDouble(),
    minConfidence: (json['min_confidence'] as num?)?.toDouble(),
    tags: (json['tags'] as List? ?? const []).map((value) => value.toString()).toList(),
    keepState: json['keep_state']?.toString(),
    analysisState: json['analysis_state']?.toString(),
    clarityState: json['clarity_state']?.toString(),
    recognitionState: json['recognition_state']?.toString(),
    recommendedOnly: json['recommended_only'] == true,
    groupId: json['group_id']?.toString(),
    sceneId: json['scene_id']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'page_size': pageSize,
    'sort': sort,
    if (species?.isNotEmpty == true) 'species': species,
    if (search?.isNotEmpty == true) 'search': search,
    if (minScore != null) 'min_score': minScore,
    if (minConfidence != null) 'min_confidence': minConfidence,
    if (tags.isNotEmpty) 'tags': tags,
    if (keepState?.isNotEmpty == true) 'keep_state': keepState,
    if (analysisState?.isNotEmpty == true) 'analysis_state': analysisState,
    if (clarityState?.isNotEmpty == true) 'clarity_state': clarityState,
    if (recognitionState?.isNotEmpty == true) 'recognition_state': recognitionState,
    if (recommendedOnly) 'recommended_only': true,
    if (groupId?.isNotEmpty == true) 'group_id': groupId,
    if (sceneId?.isNotEmpty == true) 'scene_id': sceneId,
  };

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
    if (clarityState?.isNotEmpty == true) 'clarity_state': clarityState,
    if (recognitionState?.isNotEmpty == true) 'recognition_state': recognitionState,
    if (recommendedOnly) 'recommended_only': true,
    if (groupId?.isNotEmpty == true) 'group_id': groupId,
    if (sceneId?.isNotEmpty == true) 'scene_id': sceneId,
  };

  List<String> get activeLabels => [
    if (species?.isNotEmpty == true) '鸟种：$species',
    if (search?.isNotEmpty == true) '搜索：$search',
    if (minScore != null) '照片质量 ≥ $minScore 星',
    if (minConfidence != null) '识别度至少 ${(minConfidence! * 100).round()}%',
    if (tags.isNotEmpty) ...tags.map((tag) => '#$tag'),
    if (keepState?.isNotEmpty == true) '照片状态：${_keepStateLabel(keepState!)}',
    if (analysisState?.isNotEmpty == true) '处理状态：${_analysisStateLabel(analysisState!)}',
    if (clarityState?.isNotEmpty == true) '清晰度：${_clarityStateLabel(clarityState!)}',
    if (recognitionState?.isNotEmpty == true) '识别结果：${_recognitionStateLabel(recognitionState!)}',
    if (recommendedOnly) '系统推荐',
    if (groupId?.isNotEmpty == true) '分组：$groupId',
    if (sceneId?.isNotEmpty == true) '场景：$sceneId',
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
    String? clarityState,
    String? recognitionState,
    bool? recommendedOnly,
    String? groupId,
    String? sceneId,
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
    clarityState: clarityState ?? this.clarityState,
    recognitionState: recognitionState ?? this.recognitionState,
    recommendedOnly: recommendedOnly ?? this.recommendedOnly,
    groupId: groupId ?? this.groupId,
    sceneId: sceneId ?? this.sceneId,
  );
}

String _keepStateLabel(String value) => switch (value.toLowerCase()) {
  'keep' => '已保留',
  'pending' => '待确认',
  'discard' => '已弃用',
  'featured' => '精选',
  _ => '其他',
};

String _analysisStateLabel(String value) => switch (value.toLowerCase()) {
  'pending' || 'queued' => '等待处理',
  'processing' || 'analyzing' => '正在处理',
  'done' || 'completed' => '已完成',
  'failed' || 'error' => '处理失败',
  _ => '其他',
};

String _clarityStateLabel(String value) => switch (value.toLowerCase()) {
  'sharp' || 'clear' => '清晰',
  'average' => '一般',
  'blurred' || 'blurry' => '模糊',
  _ => '其他',
};

String _recognitionStateLabel(String value) => switch (value.toLowerCase()) {
  'recognized' || 'matched' => '已识别',
  'uncertain' || 'pending' => '需要确认',
  'unknown' || 'unrecognized' => '暂未识别',
  _ => '其他',
};
