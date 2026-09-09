import 'dart:async';
import 'dart:typed_data';

import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_http_client.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:dio/dio.dart';
// flutter_cache_manager exposes package:file objects in its public contract.
// ignore: depend_on_referenced_packages
import 'package:file/file.dart' as file_api;
// ignore: depend_on_referenced_packages
import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EventClient eventClient;
  late _MemoryCacheManager manager;
  late _MemoryEtagStore etagStore;
  late MediaAssetCache cache;
  late MediaAssetCoordinator coordinator;
  late _PendingHttpClient httpClient;
  late MediaAssetService service;

  setUp(() {
    eventClient = EventClient();
    manager = _MemoryCacheManager();
    etagStore = _MemoryEtagStore();
    cache = MediaAssetCache(manager: manager, etagStore: etagStore);
    coordinator = MediaAssetCoordinator(
      eventClient: eventClient,
      activeDeviceId: () => 'box-1',
      cacheInvalidator: cache,
    );
    httpClient = _PendingHttpClient();
    service = MediaAssetService(
      httpClient: httpClient,
      cache: cache,
      coordinator: coordinator,
    );
  });

  tearDown(() async {
    service.dispose();
    await coordinator.dispose();
    await eventClient.dispose();
  });

  test(
    'same stable resource shares one transfer and subscriber cancellation is isolated',
    () async {
      final firstToken = CancelToken();
      final first = service.load(_descriptor(), cancelToken: firstToken);
      final second = service.load(
        _descriptor(signature: 'rotated'),
        forceRefresh: true,
      );

      await _waitForCalls(httpClient, 1);
      expect(httpClient.calls, hasLength(1));
      expect(httpClient.calls.single.cancelToken, isNull);

      firstToken.cancel('tile disposed');
      await expectLater(
        first,
        throwsA(
          isA<MediaAssetFailure>().having(
            (failure) => failure.kind,
            'kind',
            MediaAssetFailureKind.cancelled,
          ),
        ),
      );

      httpClient.complete(
        0,
        _response(bytes: [1, 2, 3], etag: '"etag-v1"'),
      );
      final sharedResult = await second;

      expect(sharedResult.etag, '"etag-v1"');
      expect(httpClient.calls, hasLength(1));

      final refreshed = service.load(
        _descriptor(signature: 'third'),
        forceRefresh: true,
      );
      await _waitForCalls(httpClient, 2);
      expect(httpClient.calls[1].ifNoneMatch, '"etag-v1"');
      httpClient.complete(
        1,
        const MediaAssetHttpResponse(
          notModified: true,
          bytes: null,
          etag: '"etag-v1"',
        ),
      );

      expect((await refreshed).fromCache, isTrue);
    },
  );

  test('new stable URI starts a new transfer and stale completion is ignored', () async {
    final versionOne = service.load(_descriptor(path: 'preview-v1.jpg'));
    await _waitForCalls(httpClient, 1);

    final versionTwo = service.load(_descriptor(path: 'preview-v2.jpg'));
    await _waitForCalls(httpClient, 2);

    httpClient.complete(
      1,
      _response(bytes: [2], etag: '"etag-v2"'),
    );
    expect((await versionTwo).etag, '"etag-v2"');

    httpClient.complete(
      0,
      _response(bytes: [1], etag: '"etag-v1"'),
    );
    expect((await versionOne).etag, '"etag-v1"');
    expect(coordinator.snapshot(_descriptor().key)?.etag, '"etag-v2"');
  });

  test('device and media kind remain separate in-flight identities', () async {
    final preview = service.load(_descriptor());
    final thumbnail = service.load(
      _descriptor(kind: MediaAssetKind.thumbnail),
    );
    final otherDevice = service.load(_descriptor(deviceId: 'box-2'));

    await _waitForCalls(httpClient, 3);
    for (var index = 0; index < 3; index++) {
      httpClient.complete(
        index,
        _response(bytes: [index], etag: '"etag-$index"'),
      );
    }

    await Future.wait([preview, thumbnail, otherDevice]);
    expect(httpClient.calls, hasLength(3));
  });

  test('persisted ETag is restored after cache object recreation', () async {
    await cache.write(
      _descriptor(),
      Uint8List.fromList([8, 9]),
      etag: '"persisted-etag"',
    );
    final restartedCache = MediaAssetCache(
      manager: manager,
      etagStore: etagStore,
    );
    final restartedService = MediaAssetService(
      httpClient: httpClient,
      cache: restartedCache,
      coordinator: coordinator,
    );

    final load = restartedService.load(_descriptor(), forceRefresh: true);
    await _waitForCalls(httpClient, 1);

    expect(httpClient.calls.single.ifNoneMatch, '"persisted-etag"');
    httpClient.complete(
      0,
      const MediaAssetHttpResponse(
        notModified: true,
        bytes: null,
        etag: '"persisted-etag"',
      ),
    );
    expect((await load).fromCache, isTrue);
    restartedService.dispose();
  });
}

MediaAssetDescriptor _descriptor({
  String path = 'preview.jpg',
  String signature = 'initial',
  String deviceId = 'box-1',
  MediaAssetKind kind = MediaAssetKind.preview,
}) => MediaAssetDescriptor(
  key: MediaAssetKey(
    deviceId: deviceId,
    fileId: 'photo-1',
    kind: kind,
  ),
  uri: Uri.parse('http://box.local/media/$path?signature=$signature'),
  status: MediaAssetStatus.ready,
);

MediaAssetHttpResponse _response({
  required List<int> bytes,
  required String etag,
}) => MediaAssetHttpResponse(
  notModified: false,
  bytes: Uint8List.fromList(bytes),
  etag: etag,
  contentType: 'image/jpeg',
);

Future<void> _waitForCalls(_PendingHttpClient client, int count) async {
  for (var attempt = 0; attempt < 20 && client.calls.length < count; attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(client.calls, hasLength(count));
}

class _HttpCall {
  const _HttpCall({
    required this.uri,
    required this.ifNoneMatch,
    required this.cancelToken,
  });

  final Uri uri;
  final String? ifNoneMatch;
  final CancelToken? cancelToken;
}

class _PendingHttpClient extends MediaAssetHttpClient {
  _PendingHttpClient() : super(dio: Dio());

  final List<_HttpCall> calls = [];
  final List<Completer<MediaAssetHttpResponse>> _responses = [];

  @override
  Future<MediaAssetHttpResponse> fetch(
    Uri uri, {
    String? ifNoneMatch,
    CancelToken? cancelToken,
  }) {
    calls.add(
      _HttpCall(
        uri: uri,
        ifNoneMatch: ifNoneMatch,
        cancelToken: cancelToken,
      ),
    );
    final response = Completer<MediaAssetHttpResponse>();
    _responses.add(response);
    return response.future;
  }

  void complete(int index, MediaAssetHttpResponse response) {
    _responses[index].complete(response);
  }

  @override
  void dispose() {}
}

class _MemoryEtagStore implements MediaAssetEtagStore {
  final Map<String, String> values = {};

  @override
  String? read(String cacheKey) => values[cacheKey];

  @override
  Future<void> remove(String cacheKey) async {
    values.remove(cacheKey);
  }

  @override
  Future<void> write(String cacheKey, String etag) async {
    values[cacheKey] = etag;
  }
}

class _MemoryCacheManager implements BaseCacheManager {
  final MemoryFileSystem _fileSystem = MemoryFileSystem();
  final Map<String, FileInfo> _entries = {};
  var _fileIndex = 0;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => _entries[key];

  @override
  Future<file_api.File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    final file = _fileSystem.file('/cache/${_fileIndex++}.$fileExtension');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(fileBytes);
    _entries[key ?? url] = FileInfo(
      file,
      FileSource.Cache,
      DateTime.now().add(maxAge),
      url,
    );
    return file;
  }

  @override
  Future<void> removeFile(String key) async {
    final info = _entries.remove(key);
    if (info != null && await info.file.exists()) {
      await info.file.delete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
