import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';

/// Pure, deterministic filtering used after frozen server pages are scanned.
class PhotoLocalFilterEngine {
  const PhotoLocalFilterEngine();

  int countMatches(
    Iterable<PhotoSummary> photos,
    PhotoQuery query, {
    Set<String> searchAliases = const {},
    Set<String> speciesAliases = const {},
  }) => photos
      .where(
        (photo) => matches(
          photo,
          query,
          searchAliases: searchAliases,
          speciesAliases: speciesAliases,
        ),
      )
      .length;

  List<PhotoSummary> filterAndSort(
    Iterable<PhotoSummary> photos,
    PhotoQuery query, {
    Set<String> searchAliases = const {},
    Set<String> speciesAliases = const {},
  }) {
    final normalizedSearchAliases = searchAliases.map(_normalize).where((value) => value.isNotEmpty).toSet();
    final normalizedSpeciesAliases = speciesAliases.map(_normalize).where((value) => value.isNotEmpty).toSet();
    final result = photos
        .where(
          (photo) => matches(
            photo,
            query,
            searchAliases: normalizedSearchAliases,
            speciesAliases: normalizedSpeciesAliases,
          ),
        )
        .toList();
    // Frozen sorts that cannot be recomputed from PhotoSummary (for example
    // file size) retain the order already produced by the server scan.
    if (_supportsLocalSort(query.sort)) {
      result.sort((left, right) => compare(left, right, query.sort));
    }
    return result;
  }

  bool matches(
    PhotoSummary photo,
    PhotoQuery query, {
    Set<String> searchAliases = const {},
    Set<String> speciesAliases = const {},
  }) {
    final candidates = photo.recognition?.candidates ?? const <SpeciesCandidate>[];
    final search = _normalize(query.search);
    if (search.isNotEmpty) {
      final directValues = <String>[
        photo.filename,
        ...photo.userTags,
        for (final candidate in candidates) ..._candidateValues(candidate),
      ].map(_normalize);
      final directMatch = directValues.any((value) => value.contains(search));
      if (!directMatch && !_candidatesMatchAliases(candidates, searchAliases)) return false;
    }

    final species = _normalize(query.species);
    if (species.isNotEmpty) {
      final speciesTerms = <String>{species, ...speciesAliases};
      if (!_candidatesMatchAliases(candidates, speciesTerms)) return false;
    }

    if (query.minScore != null && (photo.rating?.totalScore ?? -1) < query.minScore!) return false;
    if (query.minConfidence != null && _primaryConfidence(candidates) < query.minConfidence!) return false;

    if (query.tags.isNotEmpty) {
      final photoTags = photo.userTags.map(_normalize).toSet();
      if (!query.tags.map(_normalize).every(photoTags.contains)) return false;
    }
    if (_hasText(query.keepState) && _normalize(photo.keepState) != _normalize(query.keepState)) return false;
    if (_hasText(query.analysisState) && _normalize(photo.analysisState.wireValue) != _normalize(query.analysisState)) return false;
    if (_hasText(query.clarityState) && _normalize(photo.clarityState.wireValue) != _normalize(query.clarityState)) return false;
    if (query.recommendedOnly && !photo.isRecommended) return false;
    if (_hasText(query.groupId) && photo.groupId != query.groupId) return false;
    if (_hasText(query.sceneId) && photo.sceneId != query.sceneId) return false;

    switch (_normalize(query.recognitionState)) {
      case 'recognized':
      case 'matched':
        if (candidates.isEmpty || photo.recognition?.isLowConfidence == true) return false;
        break;
      case 'needs_review':
      case 'uncertain':
      case 'pending':
        if (photo.recognition?.isLowConfidence != true) return false;
        break;
      case 'unknown':
      case 'unrecognized':
        if (candidates.isNotEmpty) return false;
        break;
    }
    return true;
  }

  int compare(PhotoSummary left, PhotoSummary right, String sort) {
    final result = switch (sort) {
      'captured_at_asc' => _time(left).compareTo(_time(right)),
      'score_desc' => _score(right).compareTo(_score(left)),
      'score_asc' => _score(left).compareTo(_score(right)),
      'confidence_desc' => _confidence(right).compareTo(_confidence(left)),
      'confidence_asc' => _confidence(left).compareTo(_confidence(right)),
      'recommended_desc' => _compareRecommended(left, right),
      'filename_asc' => left.filename.toLowerCase().compareTo(right.filename.toLowerCase()),
      'filename_desc' => right.filename.toLowerCase().compareTo(left.filename.toLowerCase()),
      _ => _time(right).compareTo(_time(left)),
    };
    return result != 0 ? result : left.id.compareTo(right.id);
  }

  bool _candidatesMatchAliases(Iterable<SpeciesCandidate> candidates, Set<String> aliases) {
    if (aliases.isEmpty) return false;
    return candidates
        .expand(_candidateValues)
        .map(_normalize)
        .any(
          (value) => aliases.any((alias) => value == alias || value.contains(alias) || alias.contains(value)),
        );
  }

  Iterable<String> _candidateValues(SpeciesCandidate candidate) => [
    candidate.name,
    candidate.speciesId ?? '',
    candidate.englishName ?? '',
    candidate.latinName ?? '',
  ].where((value) => value.isNotEmpty);

  double _primaryConfidence(Iterable<SpeciesCandidate> candidates) => candidates.isEmpty ? -1 : candidates.first.confidence;

  double _score(PhotoSummary photo) => photo.rating?.totalScore ?? -1;

  double _confidence(PhotoSummary photo) => _primaryConfidence(photo.recognition?.candidates ?? const <SpeciesCandidate>[]);

  DateTime _time(PhotoSummary photo) => photo.capturedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  int _compareRecommended(PhotoSummary left, PhotoSummary right) {
    final recommendation = (right.isRecommended ? 1 : 0).compareTo(left.isRecommended ? 1 : 0);
    return recommendation != 0 ? recommendation : _score(right).compareTo(_score(left));
  }

  bool _supportsLocalSort(String sort) => const {
    'captured_at_desc',
    'captured_at_asc',
    'score_desc',
    'score_asc',
    'confidence_desc',
    'confidence_asc',
    'recommended_desc',
    'filename_asc',
    'filename_desc',
  }.contains(sort);
}

String _normalize(String? value) => value?.trim().toLowerCase() ?? '';

bool _hasText(String? value) => value?.trim().isNotEmpty == true;
