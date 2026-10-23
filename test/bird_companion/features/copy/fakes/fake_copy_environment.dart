import 'synthetic_copy_plan.dart';
import 'dart:async';

import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

StorageDeviceSummary b3Device(String id, {String? name, bool source = false, bool target = true, bool online = true, String? productRole, List<String> reasons = const [], int free = 1000000}) => StorageDeviceSummary(
  mediaId: id,
  displayName: name ?? id,
  kind: source ? 'memory_card' : 'usb_flash',
  kindConfidence: 'high',
  detail: '测试设备',
  capacityBytes: 2000000,
  freeBytes: free,
  filesystem: 'exfat',
  label: id,
  roleState: online ? 'available' : 'removed',
  canBeSource: source,
  canBeTarget: target,
  targetBlockReasons: reasons,
  identityConfidence: 'stable_uuid',
  productRole: productRole,
);

/// Synthetic rc3 environment. These are not captured board responses.
class FakeCopyEnvironment with SyntheticCopyPlan implements CopyRepository {
  @override
  int get syntheticFileCount => 1;
  @override
  int get syntheticBytes => 100;
  List<StorageDeviceSummary> storage = [b3Device('source', source: true, target: false), b3Device('target'), b3Device('other-target')];
  String sourceId = 'source', bindingToken = 'binding-1';
  bool verifiedReadOnly = true;
  Duration previewLifetime = const Duration(minutes: 10);
  Future<CopyDeviceList> Function()? readDevices;
  Future<SourceBinding> Function()? readSource;
  Future<CopyPreview> Function(CopyRequestDraft)? makePreview;
  Future<CopyPreferences> Function(PairPolicy, int)? savePolicy;
  Completer<CopyJobSummary>? pendingCreate;
  int deviceCalls = 0, sourceCalls = 0, previewCalls = 0, createCalls = 0, preferenceVersion = 1;
  final drafts = <CopyRequestDraft>[], savedVersions = <int>[];
  final createdTokens = <String>[];
  CopyRequestDraft? createdDraft;

  SourceBinding binding() => SourceBinding(sourceMediaId: sourceId, displayName: sourceId, token: bindingToken, expiresAt: DateTime.now().add(const Duration(minutes: 2)), verifiedReadOnly: verifiedReadOnly);
  CopyPreview previewFor(CopyRequestDraft draft) => CopyPreview(
    previewToken: 'preview-$previewCalls',
    expiresAt: DateTime.now().add(previewLifetime),
    source: storage.where((d) => d.mediaId == draft.sourceMediaId).first,
    target: storage.where((d) => d.mediaId == draft.targetMediaId).first,
    logicalPhotoCount: 1,
    actualFileCount: 1,
    totalBytes: 100,
    rawCount: 1,
    jpegCount: 0,
    videoCount: 0,
    companionCount: 0,
    estimatedDateDirectories: 1,
    conflictCount: 0,
    targetFreeBytes: 1000000,
    safetyReserveBytes: 100,
  );

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(revision: '1.0-rc3', copyReady: true, supportedScopes: [CopyScope.batchAllAssets, CopyScope.recognizedAssets], recognitionPolicyVersion: 'recognized-assets-v1');
  @override
  Future<CopyDeviceList> devices() async {
    deviceCalls++;
    return readDevices == null ? CopyDeviceList(devices: List.of(storage)) : await readDevices!();
  }

  @override
  Future<SourceBinding> source({String? batchId}) async {
    sourceCalls++;
    return readSource == null ? binding() : await readSource!();
  }

  @override
  Future<CopyPreferences> preferences() async => CopyPreferences(pairPolicy: PairPolicy.rawOnly, version: preferenceVersion, origin: 'factory_default');
  @override
  Future<CopyPreferences> savePreferences(PairPolicy policy, {required int expectedVersion}) async {
    savedVersions.add(expectedVersion);
    return savePolicy == null ? CopyPreferences(pairPolicy: policy, version: ++preferenceVersion, origin: 'user_saved') : await savePolicy!(policy, expectedVersion);
  }

  @override
  Future<List<CopyScopeOption>> scopeOptions({String? batchId, String? selectionId, Map<String, dynamic>? filter}) async => [
    for (final scope in [CopyScope.batchAllAssets, CopyScope.recognizedAssets, CopyScope.selectedAssets, CopyScope.filteredAssets, CopyScope.mediaFullBackup])
      CopyScopeOption(scope: scope, available: true, logicalAssets: 1, countState: 'known', navigationAction: 'none'),
  ];
  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async {
    previewCalls++;
    drafts.add(draft);
    return makePreview == null ? previewFor(draft) : await makePreview!(draft);
  }

  @override
  Future<CopyJobSummary> createJob(CopyRequestDraft draft, String previewToken) async {
    createCalls++;
    createdDraft = draft;
    createdTokens.add(previewToken);
    return pendingCreate == null ? const CopyJobSummary(copyJobId: 'created-job', state: 'queued', eventSeq: 0) : await pendingCreate!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
