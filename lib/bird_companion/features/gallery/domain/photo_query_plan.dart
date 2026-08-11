import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

/// Splits a gallery query into the frozen server contract and App-local work.
///
/// The server query deliberately keeps using [PhotoQuery.parameters], whose
/// fields are frozen by birdbox-v1. Local-only filters are never promoted to
/// HTTP query parameters.
class PhotoQueryPlan {
  const PhotoQueryPlan(this.query);

  static const int scanPageSize = 200;
  static const String localCursorPrefix = 'local-v1-';

  final PhotoQuery query;

  bool get requiresLocalScan =>
      _hasText(query.species) || _hasText(query.search) || query.minScore != null || query.minConfidence != null || query.tags.isNotEmpty || _hasText(query.clarityState) || _hasText(query.recognitionState) || query.recommendedOnly;

  bool get hasLocalCursor => isLocalCursor(query.cursor);

  PhotoQuery serverQuery({String? cursor}) => query.copyWith(
    cursor: cursor,
    clearCursor: cursor == null,
    pageSize: scanPageSize,
  );

  static bool isLocalCursor(String? cursor) => cursor?.startsWith(localCursorPrefix) == true;
}

bool _hasText(String? value) => value?.trim().isNotEmpty == true;
