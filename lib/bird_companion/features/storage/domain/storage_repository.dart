import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';

abstract interface class StorageRepository {
  Future<CardScanResult> currentScan();
  Future<BirdJobStatus> rescan();
}
