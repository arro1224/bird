import 'dart:async';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_controller.dart';
import 'completion_fixtures.dart';

class MetadataStore implements DiagnosticStorage {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class MetadataBackend extends CompletionBackend {
  bool capability = true, available = true, failPreview = false;
  String? active;
  int availabilityReads = 0, previewReads = 0, detailReads = 0, creates = 0, updateReads = 0;
  Map<String, dynamic>? submitted;
  String? submittedKey;
  Object? createError;
  Completer<void>? previewGate, createGate, detailGate;
  Map<String, dynamic> previewData = {
    'preview_id': 'pv-1',
    'preview_token': 'token-1',
    'expires_at': '2099-01-01T00:00:00Z',
    'target_media_id': 'media_usb_fake',
    'target_display_name': '摄影备份盘',
    'child_job_count': 2,
    'updatable_asset_count': 3,
    'updatable_file_count': 5,
    'unchanged_count': 1,
    'blocked_count': 0,
    'conflict_count': 0,
    'estimated_bytes': 4096,
    'write_mode': 'safe_embed_first',
    'requires_partial_confirmation': false,
    'blocked_reasons': <String>[],
  };
  Map<String, dynamic>? detailData;
  @override
  Future<SmartFollowCapabilities> capabilities() async => SmartFollowCapabilities.fromJson({
    'incremental_recognition_results': {'available': true},
    'smart_follow_copy': {'available': true},
    'smart_follow_metadata_update': {'available': capability},
  });
  @override
  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionId) async {
    ++availabilityReads;
    return SmartFollowMetadataAvailability.fromJson({'available': available, if (active != null) 'active_update_id': active});
  }

  @override
  Future<SmartFollowMetadataPreview> previewMetadata(String sessionId, {Map<String, dynamic>? data, String? idempotencyKey}) async {
    ++previewReads;
    if (previewGate != null) await previewGate!.future;
    if (failPreview) throw StateError('预览暂不可用');
    return SmartFollowMetadataPreview.fromJson({...previewData});
  }

  @override
  Future<SmartFollowMetadataPreview> previewDetail(String previewId) async {
    ++detailReads;
    if (detailGate != null) await detailGate!.future;
    return SmartFollowMetadataPreview.fromJson({...detailData ?? previewData});
  }

  @override
  Future<SmartFollowMetadataUpdate> createMetadataUpdate(String sessionId, {required Map<String, dynamic> data, String? idempotencyKey}) async {
    ++creates;
    submitted = data;
    submittedKey = idempotencyKey;
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    active = 'update-1';
    available = false;
    return SmartFollowMetadataUpdate.fromJson({'update_id': active, 'state': 'queued'});
  }

  @override
  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId) async {
    ++updateReads;
    return SmartFollowMetadataUpdate.fromJson({'update_id': updateId, 'state': 'running'});
  }
}

class MetadataEnvironment {
  MetadataEnvironment() {
    repository = SmartFollowRepository(backend, metadataStorage: store, metadataDeviceId: () => deviceId);
    controller = newController();
  }
  final backend = MetadataBackend();
  final store = MetadataStore();
  late final SmartFollowRepository repository;
  late final SmartFollowMetadataController controller;
  DateTime clock = DateTime.utc(2030);
  bool current = true, wrongRecognition = false;
  String deviceId = 'box-1';
  BirdJobState recognitionState = BirdJobState.completed;
  SmartFollowMetadataController newController({SmartFollowRepository? follows}) => SmartFollowMetadataController(
    repository: follows ?? repository,
    sessionId: 'sf_fake',
    isCurrent: () => current,
    now: () => clock,
    readRecognition: (id) async => BirdJobStatus(id: wrongRecognition ? 'other-job' : id, type: BirdJobType.analysis, state: recognitionState),
  );
  void dispose() {
    controller.dispose();
    repository.dispose();
  }
}
