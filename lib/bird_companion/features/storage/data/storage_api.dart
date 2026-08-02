import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';

class StorageApi {
  StorageApi(this._client);
  final ApiClient _client;

  Future<CardScanResult> currentScan() async => CardScanResult.fromJson(
    await _client.get(ApiEndpoints.currentCardScan),
  );

  Future<BirdJobStatus> rescan() async => BirdJobStatus.fromJson(
    await _client.post(ApiEndpoints.currentCardRescan),
  );
}
