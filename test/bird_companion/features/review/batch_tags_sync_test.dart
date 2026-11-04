import 'dart:io';

import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/mock_box_server/mock_box_server.dart';

void main() {
  for (final saveFirst in [false, true]) {
    test('batch tags survive detail/edit/save and removal (previous save: $saveFirst)', () async {
      final server = MockBoxServer(
        photoCount: 12,
        assetDirectory: Directory('tool/mock_box_server/assets'),
        logRequests: false,
      );
      final uri = await server.start();
      addTearDown(server.close);
      final client = ApiClient()..configure(uri);
      final pending = PendingOperationStore.memory();
      addTearDown(pending.dispose);
      final repository = ReviewRepositoryImpl(
        ReviewApi(client),
        _Online(),
        pending,
        _MemoryCache(),
        () => 'box-1',
        () => 'box-1',
      );
      final before = await repository.detail('photo-0001');
      if (saveFirst) {
        await repository.save(
          UserDecision(
            fileId: 'photo-0001',
            keepState: KeepState.keep,
            userTags: before.decision!.userTags,
            version: before.decision!.version,
          ),
        );
      }
      final original = (await repository.detail('photo-0001')).decision!;
      final untouched = await repository.detail('photo-0002');
      final api = PhotoApi(client);
      final added = await api.batchOperation('mock-batch-current', ['photo-0001'], 'add_tags', version: original.version!, value: ['水鸟']);
      expect(added.succeededIds, ['photo-0001']);
      final detail = await repository.detail('photo-0001');
      expect(detail.decision!.userTags, [...original.userTags, '水鸟']);
      expect(detail.photo.summary.userTags, detail.decision!.userTags);
      expect(detail.decision!.version, original.version! + 1);
      expect((await repository.detail('photo-0002')).decision, untouched.decision);

      // Saving another field from the editor must not erase the batch tag.
      await repository.save(
        UserDecision(
          fileId: 'photo-0001',
          keepState: KeepState.featured,
          userTags: detail.decision!.userTags,
          version: detail.decision!.version,
        ),
      );
      final saved = await repository.detail('photo-0001');
      expect(saved.decision!.userTags, contains('水鸟'));
      final removed = await api.batchOperation('mock-batch-current', ['photo-0001'], 'remove_tags', version: saved.decision!.version!, value: ['水鸟']);
      expect(removed.succeededIds, ['photo-0001']);
      final after = await repository.detail('photo-0001');
      expect(after.decision!.userTags, original.userTags);
      expect(after.photo.summary.userTags, original.userTags);
      expect(after.decision!.keepState, KeepState.featured);
    });
  }
}

class _Online extends ConnectivityMonitor {
  @override
  Future<bool> get hasNetwork async => true;
}

class _MemoryCache implements LocalCache {
  final _values = <String, Object?>{};
  @override
  T? read<T>(String key) => _values[key] as T?;
  @override
  List<String> keysWithPrefix(String prefix) => _values.keys.where((key) => key.startsWith(prefix)).toList();
  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
