import 'dart:convert';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_repository_impl.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:dio/dio.dart';

class RepairMemoryCache implements LocalCache {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => values[key] = jsonDecode(jsonEncode(value));
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  List<String> keysWithPrefix(String prefix) => values.keys.where((key) => key.startsWith(prefix)).toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RepairConnectivity extends ConnectivityMonitor {
  bool online = true;
  @override
  Future<bool> get hasNetwork async => online;
}

class RepairTestContext {
  RepairTestContext(this.profile);
  static const project = 'mock-batch-current';
  final RepairAcceptanceProfile profile;
  final cache = RepairMemoryCache();
  final pending = PendingOperationStore.memory();
  final connectivity = RepairConnectivity();
  final bus = AppDataChangeBus();
  final writes = <Map<String, dynamic>>[];
  String deviceId = 'box-a';
  late final MockBoxServer server;
  late final ApiClient client;
  late final Dio dio;
  late final BatchRepositoryImpl batches;
  late final PhotoRepositoryImpl photos;
  late final ReviewRepositoryImpl reviews;
  String get manualId => profile.manualSpeciesFileId;

  Future<void> open() async {
    server = MockBoxServer(acceptanceProfile: profile, logRequests: false);
    dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST' && options.path.endsWith('/decision')) writes.add(Map<String, dynamic>.from(options.data as Map));
            handler.next(options);
          },
        ),
      );
    client = ApiClient(dio: dio)..configure(await server.start());
    batches = BatchRepositoryImpl(BatchApi(client), cache, () => deviceId);
    photos = PhotoRepositoryImpl(PhotoApi(client), connectivity, pending, cache, () => deviceId, () => deviceId);
    reviews = freshReviewRepository();
  }

  ReviewRepositoryImpl freshReviewRepository() => ReviewRepositoryImpl(ReviewApi(client), connectivity, pending, cache, () => deviceId, () => deviceId, bus);
  GalleryCubit gallery() => GalleryCubit(photos, project, null, bus, cache, pending, () => deviceId, null, null, batches);
  Future<void> close() async {
    await client.dispose();
    await server.close();
    await pending.dispose();
    await bus.dispose();
  }
}
