import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';

StorageDeviceSummary configDevice(
  String id, {
  bool source = false,
  bool online = true,
  bool writable = true,
  int free = 1000000,
  int capacity = 2000000,
  String identity = 'stable_uuid',
  List<String> reasons = const [],
  String? role,
  String? displayName,
}) => StorageDeviceSummary(
  mediaId: id,
  displayName:
      displayName ??
      (id == 'target'
          ? '旅行备份盘'
          : id == 'source'
          ? '相机卡'
          : id),
  kind: source ? 'memory_card' : 'external_ssd',
  kindConfidence: 'high',
  detail: '测试设备',
  capacityBytes: capacity,
  freeBytes: free,
  filesystem: 'exfat',
  label: id,
  roleState: online ? 'available' : 'offline',
  canBeSource: source,
  canBeTarget: !source && writable,
  targetBlockReasons: reasons,
  identityConfidence: identity,
  productRole: role,
);

class ConfigurationFixture {
  DateTime clock = DateTime.now();
  DateTime? expiry;
  bool current = true, readOnly = true, exports = true, available = true;
  int reads = 0, preferencesVersion = 1;
  String? bindingBatch = 'batch-1';
  String sourceId = 'source', token = 'binding-token';
  String jobId = 'rec-1';
  bool notStarted = false;
  bool continuous = false;
  PairPolicy preferred = PairPolicy.rawOnly;
  List<StorageDeviceSummary> devices = [configDevice('source', source: true), configDevice('target')];
  Future<SmartFollowConfigurationSnapshot> Function()? pending;
  void Function(int reads)? beforeRead;

  SmartFollowConfigurationSnapshot snapshot() => SmartFollowConfigurationSnapshot(
    entry: SmartFollowEntryDecision(
      phase: notStarted ? RecognitionEntryPhase.notStarted : RecognitionEntryPhase.running,
      job: notStarted ? null : BirdJobStatus(id: jobId, type: BirdJobType.analysis, state: BirdJobState.running, sourceProjectId: 'batch-1'),
      capabilities: SmartFollowCapabilities(incrementalRecognition: available, copy: SmartFollowCapability(available: true, continuousQueueAvailable: continuous, continuousContractVersion: continuous ? SmartFollowContract.continuousVersion : null), metadataUpdate: false),
    ),
    binding: SourceBinding(sourceMediaId: sourceId, displayName: '相机卡', token: token, expiresAt: expiry ?? clock.add(const Duration(minutes: 10)), verifiedReadOnly: readOnly, batchId: bindingBatch),
    preferences: CopyPreferences(pairPolicy: preferred, version: preferencesVersion, origin: 'synthetic'),
    copyCapabilities: CopyCapabilities(revision: '1.0-rc3', copyReady: true, supportedScopes: const [CopyScope.recognizedAssets], recognitionPolicyVersion: 'recognized_only_v1', reviewExportReady: exports),
    devices: devices,
  );

  SmartFollowConfigurationReader reader({Stream<void>? changes}) => SmartFollowConfigurationReader(
    batchId: 'batch-1',
    contextKey: 'box-1|http://box',
    changes: changes,
    isCurrent: () => current,
    readSnapshot: () async {
      ++reads;
      beforeRead?.call(reads);
      return pending == null ? snapshot() : pending!();
    },
  );

  Future<SmartFollowConfigurationController> controller() async {
    final controller = SmartFollowConfigurationController(reader(), now: () => clock);
    await controller.refresh();
    return controller;
  }
}
