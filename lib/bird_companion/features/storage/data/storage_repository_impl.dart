import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/storage/data/storage_api.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/storage/domain/storage_repository.dart';

class StorageRepositoryImpl implements StorageRepository {
  StorageRepositoryImpl(this._api);
  final StorageApi _api;

  @override
  Future<CardScanResult> currentScan() => _api.currentScan();

  @override
  Future<BirdJobStatus> rescan() => _api.rescan();
}
