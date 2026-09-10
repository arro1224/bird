import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/features/device/data/device_status_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_local_query_executor.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/storage/data/storage_api.dart';

Future<void> main(List<String> arguments) async {
  final baseUri = _baseUri(arguments);
  try {
    final report = await runB12AK7Acceptance(baseUri);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } catch (error, stackTrace) {
    stderr.writeln('B12-A K7 acceptance failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

/// Runs the B12-A release gate against an already-running K7 simulator.
///
/// The write checks create isolated B12-A simulator projects and jobs. The
/// simulator is process-local, so restarting it restores the initial dataset.
Future<B12AK7AcceptanceReport> runB12AK7Acceptance(
  Uri baseUri, {
  bool exerciseWrites = true,
}) async {
  final client = ApiClient()..configure(baseUri);
  final watch = Stopwatch()..start();
  try {
    final health = await client.getUri(baseUri.resolve('/healthz'));
    _require(health['status'] == 'ok', 'K7 health status is not ok');
    final advertisedPhotos = _nonNegativeInt(health['photos'], 'health.photos');

    final device = await DeviceStatusApi(client).fetchStatus();
    _require(device.connection.id.isNotEmpty, 'device_id is empty');
    _require(device.connection.apiVersion == 'v1', 'K7 does not report birdbox-v1');

    final batchApi = BatchApi(client);
    final batch = await batchApi.current();
    _require(batch != null, 'K7 has no current project');
    _require(batch!.totalFiles == advertisedPhotos, 'project and health photo counts differ');

    final storageApi = StorageApi(client);
    final scan = await storageApi.currentScan();
    _require(scan.canCreateProject, 'current card is not in detected/createable state');
    _require(scan.photoCount == advertisedPhotos, 'card and health photo counts differ');

    final photoApi = PhotoApi(client);
    final scenes = await photoApi.scenes(batch.id);
    _require(scenes.isNotEmpty, 'K7 returned no scenes');

    final progress = <({int scanned, int matched, bool complete})>[];
    final executor = PhotoLocalQueryExecutor(
      photoApi.page,
      photoApi.searchSpecies,
    );
    final egretWatch = Stopwatch()..start();
    final egrets = await executor.page(
      batch.id,
      const PhotoQuery(search: '白鹭', pageSize: 200),
      onProgress: (value) => progress.add(
        (
          scanned: value.scannedCount,
          matched: value.matchedCount,
          complete: value.complete,
        ),
      ),
    );
    egretWatch.stop();
    _require(egrets.items.isNotEmpty, 'search 白鹭 returned no photos');
    _require(egrets.scannedCount == advertisedPhotos, 'search 白鹭 did not scan the complete project');
    _require(egrets.resultComplete, 'search 白鹭 returned an incomplete result');
    _require(progress.any((value) => value.complete), 'search 白鹭 did not publish completion progress');

    final kingfishers = await executor.page(
      batch.id,
      const PhotoQuery(search: '普通翠鸟', pageSize: 200),
    );
    _require(kingfishers.items.isNotEmpty, 'search 普通翠鸟 returned no photos');

    final combined = await executor.page(
      batch.id,
      const PhotoQuery(
        species: '白鹭',
        minScore: 4,
        minConfidence: .75,
        tags: ['湿地'],
        clarityState: 'clear',
        recognitionState: 'recognized',
        sort: 'score_desc',
        pageSize: 200,
      ),
    );
    _require(combined.items.isNotEmpty, 'combined 白鹭 filter returned no photos');

    final thumbnailUri = egrets.items.first.preview.thumbnailUri;
    _require(thumbnailUri != null, '白鹭 result has no thumbnail');
    final thumbnail = await client.downloadSignedBytes(thumbnailUri!);
    _require(thumbnail.bytes.length > 1000, '白鹭 thumbnail is empty');


    final jobApi = JobApi(client);
    final initialJobs = await jobApi.page(pageSize: 100);
    final exercisedJobs = <String>[];
    var conflict409Verified = false;
    var unavailable422Verified = false;
    var logBytes = 0;

    if (exerciseWrites) {
      final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      final project = await batchApi.create(
        ProjectCreateRequest(
          name: 'B12-A simulator acceptance $stamp',
          cardId: scan.cardId!,
        ),
      );

      var importJob = await jobApi.createImport(
        project.id,
        const ImportJobRequest(),
      );
      exercisedJobs.add(importJob.id);
      importJob = await jobApi.control(
        importJob.id,
        'pause',
        version: importJob.version!,
      );
      _require(importJob.state.name == 'paused', 'import pause did not converge');
      try {
        await jobApi.control(importJob.id, 'resume', version: 0);
      } on ApiException catch (error) {
        conflict409Verified = error.statusCode == HttpStatus.conflict;
      }
      _require(conflict409Verified, 'stale task version did not return 409');
      importJob = await jobApi.control(
        importJob.id,
        'resume',
        version: importJob.version!,
      );
      importJob = await jobApi.control(
        importJob.id,
        'cancel',
        version: importJob.version!,
      );
      _require(importJob.state.name == 'cancelled', 'import cancel did not converge');
      try {
        await jobApi.control(
          importJob.id,
          'pause',
          version: importJob.version!,
        );
      } on ApiException catch (error) {
        unavailable422Verified = error.statusCode == HttpStatus.unprocessableEntity;
      }
      _require(unavailable422Verified, 'unavailable task action did not return 422');

      var analysisJob = await jobApi.createAnalysis(
        project.id,
        const AnalysisJobRequest(),
      );
      exercisedJobs.add(analysisJob.id);
      analysisJob = await jobApi.control(
        analysisJob.id,
        'cancel',
        version: analysisJob.version!,
      );
      _require(analysisJob.state.name == 'cancelled', 'analysis cancel did not converge');

      // 旧 copy estimate/create 接口已随 birdbox-copy-v1 迁移移除；
      // 复制任务验收将在新协议联调阶段补充（见迁移对照文档 §4.1）。
      var scanJob = await storageApi.rescan();
      exercisedJobs.add(scanJob.id);
      scanJob = await jobApi.control(
        scanJob.id,
        'cancel',
        version: scanJob.version!,
      );
      _require(scanJob.state.name == 'cancelled', 'rescan cancel did not converge');

      final logUrl = await jobApi.exportLogs(
        scope: 'device_and_jobs',
        jobId: scanJob.id,
      );
      _require(logUrl != null && logUrl.isNotEmpty, 'log export returned no URL');
      final log = await client.downloadSignedBytes(baseUri.resolve(logUrl!));
      logBytes = log.bytes.length;
      _require(logBytes > 0, 'downloaded diagnostics log is empty');
    }

    final finalJobs = await jobApi.page(pageSize: 100);
    _require(finalJobs.items.length >= initialJobs.items.length, 'job list lost existing items');
    watch.stop();
    return B12AK7AcceptanceReport(
      baseUri: baseUri,
      deviceId: device.connection.id,
      deviceName: device.connection.name,
      apiVersion: device.connection.apiVersion!,
      advertisedPhotos: advertisedPhotos,
      scannedPhotos: egrets.scannedCount,
      egretMatches: egrets.matchedCount ?? egrets.items.length,
      kingfisherMatches: kingfishers.matchedCount ?? kingfishers.items.length,
      combinedFilterMatches: combined.matchedCount ?? combined.items.length,
      sceneCount: scenes.length,
      progressEvents: progress.length,
      thumbnailBytes: thumbnail.bytes.length,
      initialJobCount: initialJobs.items.length,
      finalJobCount: finalJobs.items.length,
      exercisedJobIds: exercisedJobs,
      conflict409Verified: conflict409Verified,
      unavailable422Verified: unavailable422Verified,
      logBytes: logBytes,
      egretSearchMilliseconds: egretWatch.elapsedMilliseconds,
      totalMilliseconds: watch.elapsedMilliseconds,
    );
  } finally {
    await client.dispose();
  }
}

class B12AK7AcceptanceReport {
  const B12AK7AcceptanceReport({
    required this.baseUri,
    required this.deviceId,
    required this.deviceName,
    required this.apiVersion,
    required this.advertisedPhotos,
    required this.scannedPhotos,
    required this.egretMatches,
    required this.kingfisherMatches,
    required this.combinedFilterMatches,
    required this.sceneCount,
    required this.progressEvents,
    required this.thumbnailBytes,
    required this.initialJobCount,
    required this.finalJobCount,
    required this.exercisedJobIds,
    required this.conflict409Verified,
    required this.unavailable422Verified,
    required this.logBytes,
    required this.egretSearchMilliseconds,
    required this.totalMilliseconds,
  });

  final Uri baseUri;
  final String deviceId;
  final String deviceName;
  final String apiVersion;
  final int advertisedPhotos;
  final int scannedPhotos;
  final int egretMatches;
  final int kingfisherMatches;
  final int combinedFilterMatches;
  final int sceneCount;
  final int progressEvents;
  final int thumbnailBytes;
  final int initialJobCount;
  final int finalJobCount;
  final List<String> exercisedJobIds;
  final bool conflict409Verified;
  final bool unavailable422Verified;
  final int logBytes;
  final int egretSearchMilliseconds;
  final int totalMilliseconds;

  Map<String, Object> toJson() => {
    'result': 'pass',
    'base_url': baseUri.toString(),
    'device_id': deviceId,
    'device_name': deviceName,
    'api_version': apiVersion,
    'advertised_photos': advertisedPhotos,
    'scanned_photos': scannedPhotos,
    'egret_matches': egretMatches,
    'kingfisher_matches': kingfisherMatches,
    'combined_filter_matches': combinedFilterMatches,
    'scene_count': sceneCount,
    'progress_events': progressEvents,
    'thumbnail_bytes': thumbnailBytes,
    'initial_job_count': initialJobCount,
    'final_job_count': finalJobCount,
    'exercised_job_ids': exercisedJobIds,
    'conflict_409_verified': conflict409Verified,
    'unavailable_422_verified': unavailable422Verified,
    'log_bytes': logBytes,
    'egret_search_ms': egretSearchMilliseconds,
    'total_ms': totalMilliseconds,
  };
}

Uri _baseUri(List<String> arguments) {
  const prefix = '--base-url=';
  final raw = arguments.where((value) => value.startsWith(prefix)).map((value) => value.substring(prefix.length)).firstOrNull ?? 'http://127.0.0.1:8787';
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('Invalid --base-url: $raw');
  }
  return uri;
}

int _nonNegativeInt(Object? value, String field) {
  if (value is int && value >= 0) return value;
  throw StateError('$field must be a non-negative integer');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
