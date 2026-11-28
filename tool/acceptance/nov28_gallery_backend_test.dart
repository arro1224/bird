import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_repository_impl.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_local_query_executor.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/retained_copy_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual Python API: summary, retained list, selection membership and RC3 count all agree on 47', () async {
    final root = Directory(Platform.environment['BIRDBOX_BACKEND_ROOT'] ?? '../盒子端后端/continuous').absolute;
    final fixture = File('tool/acceptance/fixtures/nov28_gallery_backend.py').absolute.path;
    String linux(String path) => '/mnt/${path[0].toLowerCase()}${path.substring(2).replaceAll('\\', '/')}';
    final process = Platform.isWindows
        ? await Process.start('wsl.exe', [
            '-d',
            Platform.environment['BIRDBOX_WSL_DISTRIBUTION'] ?? 'Ubuntu-24.04',
            '--',
            'env',
            'PYTHONIOENCODING=utf-8',
            Platform.environment['BIRDBOX_WSL_PYTHON'] ?? '/home/windsky/birdbox-20261113-venv/bin/python',
            linux(fixture),
            linux(root.path),
            '/tmp/bird-nov28-api-${DateTime.now().microsecondsSinceEpoch}',
          ])
        : await Process.start(Platform.environment['PYTHON_EXECUTABLE'] ?? 'python3', [fixture, root.path, (await Directory.systemTemp.createTemp('bird-nov28-api-')).path], environment: {'PYTHONIOENCODING': 'utf-8'});
    Uri? endpoint;
    addTearDown(() async {
      final http = HttpClient();
      try {
        if (endpoint != null) await (await http.postUrl(endpoint.resolve('/local-nov28-shutdown'))).close();
        await process.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        process.kill();
      } finally {
        http.close(force: true);
      }
    });
    final stderr = StringBuffer();
    addTearDown(() {
      if (stderr.toString().contains('Traceback')) debugPrint(stderr.toString());
    });
    // wsl.exe may prepend a host-encoded networking warning on stderr.
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(stderr.write);
    final ready = jsonDecode(await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds: 20))) as Map;
    final client = ApiClient()..configure(Uri.parse('http://127.0.0.1:${ready['port']}'));
    endpoint = client.baseUri;
    addTearDown(client.dispose);
    for (var i = 0; ; i++) {
      try {
        await client.get('/api/v1/device/status');
        break;
      } catch (_) {
        if (i == 30) fail('Python API did not start: $stderr');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    final paired = await client.post('/api/v1/device/pair', data: {'pairing_code': '123456', 'client_name': 'nov28-test'}, idempotencyKey: 'nov28-fixture-pair');
    client.setSession(accessToken: paired['access_token'] as String);
    final project = ready['project_id'] as String;
    final projects = await client.get('/api/v1/projects');
    final summary = (projects['items'] as List).cast<Map>().singleWhere((p) => p['project_id'] == project);
    expect(summary['keep_count'], 47);
    final api = PhotoApi(client);
    final photos = _Photos(PhotoLocalQueryExecutor(api.page, api.searchSpecies));
    const query = PhotoQuery(keepState: 'keep');
    final page = await photos.page(project, query);
    expect(page.items, hasLength(47));
    expect(page.items.where((p) => p.keepState == 'featured'), hasLength(2));
    final copies = CopyRepositoryImpl(CopyApi(client));
    final selection = await createRetainedCopySelection(batchId: project, query: query, photos: photos, copies: copies, isCurrent: () => true);
    expect(selection.assetCount, 47);
    final stored = await client.get('/api/v1/copy-selections/${selection.selectionId}');
    expect(stored['asset_ids'], hasLength(47));
    expect(stored['asset_ids'], containsAll(['fixture-photo-045', 'fixture-photo-046']));
    expect(stored['asset_ids'], isNot(contains('fixture-photo-047')));
    final options = await copies.scopeOptions(batchId: project, selectionId: selection.selectionId);
    expect(options.singleWhere((o) => o.scope.wireValue == 'selected_assets').logicalAssets, 47);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

class _Photos implements PhotoRepository {
  _Photos(this.executor);
  final PhotoLocalQueryExecutor executor;
  @override
  Future<PhotoPage> page(String projectId, PhotoQuery query) => executor.page(projectId, query);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
