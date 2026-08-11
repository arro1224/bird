import 'dart:convert';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_local_filter_engine.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query_plan.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';

typedef PhotoServerPageLoader =
    Future<PhotoPage> Function(
      String batchId,
      PhotoQuery query,
    );
typedef SpeciesAliasLoader = Future<List<SpeciesCandidate>> Function(String query);
typedef PhotoCandidateSnapshotReader =
    PhotoCandidateSnapshot? Function(
      String batchId,
      PhotoQuery serverQuery,
    );
typedef PhotoCandidateSnapshotWriter =
    Future<void> Function(
      String batchId,
      PhotoQuery serverQuery,
      PhotoCandidateSnapshot snapshot,
    );

class PhotoCandidateSnapshot {
  const PhotoCandidateSnapshot({
    required this.items,
    required this.cachedAt,
  });

  final List<PhotoSummary> items;
  final DateTime cachedAt;
}

/// Executes App-local filters without extending the frozen photo-list API.
class PhotoLocalQueryExecutor {
  PhotoLocalQueryExecutor(
    this._loadServerPage,
    this._loadSpeciesAliases, [
    this._filterEngine = const PhotoLocalFilterEngine(),
    this._readCandidateSnapshot,
    this._writeCandidateSnapshot,
  ]);

  final PhotoServerPageLoader _loadServerPage;
  final SpeciesAliasLoader _loadSpeciesAliases;
  final PhotoLocalFilterEngine _filterEngine;
  final PhotoCandidateSnapshotReader? _readCandidateSnapshot;
  final PhotoCandidateSnapshotWriter? _writeCandidateSnapshot;
  final Map<int, _LocalQuerySession> _sessions = {};
  static const _maxSessionItems = 50000;
  int _nextSessionId = 1;

  Future<PhotoPage> page(
    String batchId,
    PhotoQuery query, {
    PhotoQueryProgressCallback? onProgress,
    PhotoQueryCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final plan = PhotoQueryPlan(query);
    if (!plan.requiresLocalScan) return _loadServerPage(batchId, query);

    final signature = _signature(batchId, query);
    final localCursor = _LocalCursor.tryParse(query.cursor);
    if (localCursor != null) {
      final session = _sessions[localCursor.sessionId];
      if (session != null && session.signature == signature) {
        return _slice(session, localCursor.offset, query.pageSize);
      }
    }

    onProgress?.call(const PhotoQueryProgress(scannedCount: 0, matchedCount: 0));
    final aliases = await _resolveAliases(query);
    cancellationToken?.throwIfCancelled();
    final serverQuery = plan.serverQuery();
    final cachedSnapshot = _readCandidateSnapshot?.call(batchId, serverQuery);
    if (cachedSnapshot != null) {
      final items = _filterEngine.filterAndSort(
        cachedSnapshot.items,
        query,
        searchAliases: aliases.search,
        speciesAliases: aliases.species,
      );
      onProgress?.call(
        PhotoQueryProgress(
          scannedCount: cachedSnapshot.items.length,
          matchedCount: items.length,
          complete: true,
          fromCache: true,
        ),
      );
      return _slice(
        _createSession(
          batchId: batchId,
          signature: signature,
          items: items,
          fromCache: true,
          cachedAt: cachedSnapshot.cachedAt,
          resultComplete: true,
          cacheScope: PhotoCacheScope.complete,
          scannedCount: cachedSnapshot.items.length,
        ),
        0,
        query.pageSize,
      );
    }

    final byId = <String, PhotoSummary>{};
    final seenCursors = <String>{};
    String? serverCursor;
    DateTime? cachedAt;
    var fromCache = false;

    try {
      while (true) {
        cancellationToken?.throwIfCancelled();
        final serverPage = await _loadServerPage(
          batchId,
          plan.serverQuery(cursor: serverCursor),
        );
        cancellationToken?.throwIfCancelled();
        fromCache = fromCache || serverPage.fromCache;
        if (serverPage.cachedAt != null && (cachedAt == null || serverPage.cachedAt!.isAfter(cachedAt))) {
          cachedAt = serverPage.cachedAt;
        }
        for (final photo in serverPage.items) {
          if (photo.id.isNotEmpty) byId[photo.id] = photo;
        }
        final matchedCount = _filterEngine.countMatches(
          byId.values,
          query,
          searchAliases: aliases.search,
          speciesAliases: aliases.species,
        );
        onProgress?.call(
          PhotoQueryProgress(
            scannedCount: byId.length,
            matchedCount: matchedCount,
            fromCache: fromCache,
          ),
        );

        final nextCursor = serverPage.nextCursor;
        if (!serverPage.hasMore || nextCursor == null || nextCursor.isEmpty || !seenCursors.add(nextCursor)) {
          break;
        }
        serverCursor = nextCursor;
      }
    } on ApiException {
      if (byId.isEmpty) rethrow;
      final items = _filterEngine.filterAndSort(
        byId.values,
        query,
        searchAliases: aliases.search,
        speciesAliases: aliases.species,
      );
      onProgress?.call(
        PhotoQueryProgress(
          scannedCount: byId.length,
          matchedCount: items.length,
          fromCache: true,
        ),
      );
      return _slice(
        _createSession(
          batchId: batchId,
          signature: signature,
          items: items,
          fromCache: true,
          cachedAt: cachedAt,
          resultComplete: false,
          cacheScope: PhotoCacheScope.partial,
          scannedCount: byId.length,
        ),
        0,
        query.pageSize,
      );
    }

    cancellationToken?.throwIfCancelled();
    final items = _filterEngine.filterAndSort(
      byId.values,
      query,
      searchAliases: aliases.search,
      speciesAliases: aliases.species,
    );
    final completedAt = cachedAt ?? DateTime.now();
    await _writeCandidateSnapshot?.call(
      batchId,
      serverQuery,
      PhotoCandidateSnapshot(
        items: byId.values.toList(growable: false),
        cachedAt: completedAt,
      ),
    );
    cancellationToken?.throwIfCancelled();
    final session = _createSession(
      batchId: batchId,
      signature: signature,
      items: items,
      fromCache: fromCache,
      cachedAt: completedAt,
      resultComplete: true,
      cacheScope: PhotoCacheScope.none,
      scannedCount: byId.length,
    );
    onProgress?.call(
      PhotoQueryProgress(
        scannedCount: byId.length,
        matchedCount: items.length,
        complete: true,
        fromCache: fromCache,
      ),
    );
    return _slice(session, 0, query.pageSize);
  }

  void invalidateBatch(String batchId) {
    _sessions.removeWhere((_, session) => session.batchId == batchId);
  }

  Future<_ResolvedAliases> _resolveAliases(PhotoQuery query) async {
    final resolved = <String, Set<String>>{};
    Future<Set<String>> resolve(String? value) async {
      final term = value?.trim() ?? '';
      if (term.isEmpty) return const {};
      final normalized = term.toLowerCase();
      if (resolved.containsKey(normalized)) return resolved[normalized]!;
      final aliases = <String>{normalized};
      try {
        final candidates = await _loadSpeciesAliases(term);
        for (final candidate in candidates) {
          aliases.addAll(
            [
              candidate.name,
              candidate.speciesId ?? '',
              candidate.englishName ?? '',
              candidate.latinName ?? '',
            ].map((value) => value.trim().toLowerCase()).where((value) => value.isNotEmpty),
          );
        }
      } on ApiException {
        // Alias assistance is optional. Raw text matching remains available.
      }
      resolved[normalized] = aliases;
      return aliases;
    }

    return _ResolvedAliases(
      search: await resolve(query.search),
      species: await resolve(query.species),
    );
  }

  PhotoPage _slice(_LocalQuerySession session, int requestedOffset, int requestedSize) {
    final pageSize = requestedSize > 0 ? requestedSize : 1;
    final start = requestedOffset.clamp(0, session.items.length);
    final end = (start + pageSize).clamp(start, session.items.length);
    return PhotoPage(
      items: session.items.sublist(start, end),
      hasMore: end < session.items.length,
      nextCursor: end < session.items.length ? '${PhotoQueryPlan.localCursorPrefix}${session.id}-$end' : null,
      fromCache: session.fromCache,
      cachedAt: session.cachedAt,
      resultComplete: session.resultComplete,
      cacheScope: session.cacheScope,
      scannedCount: session.scannedCount,
      matchedCount: session.items.length,
    );
  }

  _LocalQuerySession _createSession({
    required String batchId,
    required String signature,
    required List<PhotoSummary> items,
    required bool fromCache,
    required DateTime? cachedAt,
    required bool resultComplete,
    required PhotoCacheScope cacheScope,
    required int scannedCount,
  }) {
    final sessionId = _nextSessionId++;
    final session = _LocalQuerySession(
      id: sessionId,
      batchId: batchId,
      signature: signature,
      items: items,
      fromCache: fromCache,
      cachedAt: cachedAt,
      resultComplete: resultComplete,
      cacheScope: cacheScope,
      scannedCount: scannedCount,
    );
    _sessions[sessionId] = session;
    _trimSessions();
    return session;
  }

  String _signature(String batchId, PhotoQuery query) => jsonEncode({
    'batch_id': batchId,
    ...query.copyWith(clearCursor: true).toJson(),
  });

  void _trimSessions() {
    var retainedItems = _sessions.values.fold<int>(
      0,
      (total, session) => total + session.items.length,
    );
    while (_sessions.length > 1 && (_sessions.length > 16 || retainedItems > _maxSessionItems)) {
      retainedItems -= _sessions.values.first.items.length;
      _sessions.remove(_sessions.keys.first);
    }
  }
}

class _LocalQuerySession {
  const _LocalQuerySession({
    required this.id,
    required this.batchId,
    required this.signature,
    required this.items,
    required this.fromCache,
    required this.cachedAt,
    required this.resultComplete,
    required this.cacheScope,
    required this.scannedCount,
  });

  final int id;
  final String batchId;
  final String signature;
  final List<PhotoSummary> items;
  final bool fromCache;
  final DateTime? cachedAt;
  final bool resultComplete;
  final PhotoCacheScope cacheScope;
  final int scannedCount;
}

class _ResolvedAliases {
  const _ResolvedAliases({required this.search, required this.species});

  final Set<String> search;
  final Set<String> species;
}

class _LocalCursor {
  const _LocalCursor(this.sessionId, this.offset);

  final int sessionId;
  final int offset;

  static _LocalCursor? tryParse(String? value) {
    if (!PhotoQueryPlan.isLocalCursor(value)) return null;
    final match = RegExp(r'^local-v1-(\d+)-(\d+)$').firstMatch(value!);
    if (match == null) return null;
    final sessionId = int.tryParse(match.group(1)!);
    final offset = int.tryParse(match.group(2)!);
    if (sessionId == null || offset == null) return null;
    return _LocalCursor(sessionId, offset);
  }
}
