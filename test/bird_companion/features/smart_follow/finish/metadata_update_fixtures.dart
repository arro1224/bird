import 'dart:async';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart';
import 'metadata_fixtures.dart';

class MetadataUpdateBackend extends MetadataBackend {
  MetadataUpdateBackend() {
    active = 'update-1';
    available = false;
    data.addAll({'active_metadata_update_id': active, 'copied_asset_count': 3, 'copied_file_count': 5, 'eligible_count': 3, 'child_job_count': 2});
  }
  bool parentFails = false, availabilityFails = false, wrongParent = false;
  Completer<void>? parentGate;
  final parentReads = <String>[];
  Map<String, dynamic> updateData = {
    'update_id': 'update-1',
    'state': 'completed',
    'state_version': 1,
    'child_job_count': 2,
    'updated_asset_count': 3,
    'updated_file_count': 5,
    'failed_count': 0,
    'unchanged_count': 1,
    'blocked_count': 0,
    'child_jobs': [child('md-a', 'copy-1', files: 2), child('md-b', 'copy-2', files: 3)],
  };
  static Map<String, dynamic> child(String id, String copy, {int files = 2, int failed = 0, String state = 'completed'}) => {
    'metadata_update_id': id,
    'copy_job_id': copy,
    'state': state,
    'updated_file_count': files,
    'failed_file_count': failed,
  };
  @override
  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId) async {
    ++updateReads;
    parentReads.add(updateId);
    final result = {...updateData, 'update_id': wrongParent ? 'wrong-parent' : updateId};
    if (parentGate != null) await parentGate!.future;
    if (parentFails) throw StateError('report unavailable');
    return SmartFollowMetadataUpdate.fromJson(result);
  }

  @override
  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionId) async {
    if (availabilityFails) throw StateError('availability unavailable');
    return super.metadataAvailability(sessionId);
  }
}

class MetadataUpdateEnvironment {
  MetadataUpdateEnvironment() {
    repository = SmartFollowRepository(backend, metadataStorage: store, metadataDeviceId: () => deviceId);
    controller = newController();
  }
  final backend = MetadataUpdateBackend();
  final store = MetadataStore();
  late final SmartFollowRepository repository;
  late final SmartFollowMetadataUpdateController controller;
  String deviceId = 'box-1';
  bool current = true;
  SmartFollowMetadataUpdateController newController({SmartFollowRepository? follows, String? id = 'update-1'}) =>
      SmartFollowMetadataUpdateController(repository: follows ?? repository, sessionId: 'sf_fake', updateId: id, isCurrent: () => current);
  void dispose() {
    controller.dispose();
    repository.dispose();
  }
}
