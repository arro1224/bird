enum BleScanPermissionState { unknown, notRequired, notRequested, granted, denied }

enum BleAdapterState { unknown, unavailable, disabled, enabled }

enum BleLocationServiceState { unknown, notRequired, disabled, enabled }

enum BleScanEndReason {
  timeout,
  stopped,
  cancelled,
  permissionDenied,
  bluetoothUnavailable,
  platformError,
  disposed,
}

final class BleScanEnvironment {
  const BleScanEnvironment({
    required this.permission,
    required this.adapter,
    this.scanPermission = BleScanPermissionState.unknown,
    this.connectPermission = BleScanPermissionState.unknown,
    this.locationPermission = BleScanPermissionState.unknown,
    this.locationService = BleLocationServiceState.unknown,
    this.locationRequiredByApp,
    this.locationPermissionRequiredByPlatform,
    this.locationRequiredForDeviceCompatibility,
    this.locationCompatibilityRule,
    this.manufacturer,
    this.model,
    this.androidRelease,
    this.sdkInt,
    this.packageId,
    this.buildFlavor,
    this.buildType,
    this.appVersionName,
    this.appVersionCode,
    this.gitCommit,
    this.buildDirty,
    this.buildId,
    this.sourceFingerprint,
    this.apkSha256,
    this.scanPermissionPolicy,
    this.scanFlavor,
    this.scanStrategyFallbackEnabled = false,
    this.scanMode,
  });

  const BleScanEnvironment.unknown()
    : permission = BleScanPermissionState.unknown,
      adapter = BleAdapterState.unknown,
      scanPermission = BleScanPermissionState.unknown,
      connectPermission = BleScanPermissionState.unknown,
      locationPermission = BleScanPermissionState.unknown,
      locationService = BleLocationServiceState.unknown,
      locationRequiredByApp = null,
      locationPermissionRequiredByPlatform = null,
      locationRequiredForDeviceCompatibility = null,
      locationCompatibilityRule = null,
      manufacturer = null,
      model = null,
      androidRelease = null,
      sdkInt = null,
      packageId = null,
      buildFlavor = null,
      buildType = null,
      appVersionName = null,
      appVersionCode = null,
      gitCommit = null,
      buildDirty = null,
      buildId = null,
      sourceFingerprint = null,
      apkSha256 = null,
      scanPermissionPolicy = null,
      scanFlavor = null,
      scanStrategyFallbackEnabled = false,
      scanMode = null;

  final BleScanPermissionState permission;
  final BleAdapterState adapter;
  final BleScanPermissionState scanPermission;
  final BleScanPermissionState connectPermission;
  final BleScanPermissionState locationPermission;
  final BleLocationServiceState locationService;
  final bool? locationRequiredByApp;
  final bool? locationPermissionRequiredByPlatform;
  final bool? locationRequiredForDeviceCompatibility;
  final String? locationCompatibilityRule;
  final String? manufacturer;
  final String? model;
  final String? androidRelease;
  final int? sdkInt;
  final String? packageId;
  final String? buildFlavor;
  final String? buildType;
  final String? appVersionName;
  final String? appVersionCode;
  final String? gitCommit;
  final bool? buildDirty;
  final String? buildId;
  final String? sourceFingerprint;
  final String? apkSha256;
  final String? scanPermissionPolicy;
  final String? scanFlavor;
  final bool scanStrategyFallbackEnabled;
  final String? scanMode;

  factory BleScanEnvironment.fromPlatform(Map<String, dynamic> value) {
    final permissionGranted = value['permissionGranted'];
    final adapterState = value['adapterState'];
    return BleScanEnvironment(
      permission: _permissionFromBool(permissionGranted),
      adapter: switch (adapterState) {
        'unavailable' => BleAdapterState.unavailable,
        'disabled' => BleAdapterState.disabled,
        'enabled' => BleAdapterState.enabled,
        _ => BleAdapterState.unknown,
      },
      scanPermission: _permissionFromValue(value['scanPermission']),
      connectPermission: _permissionFromValue(value['connectPermission']),
      locationPermission: _permissionFromValue(value['locationPermission']),
      locationService: _locationServiceFromValue(value['locationService']),
      locationRequiredByApp: value['locationRequiredByApp'] as bool?,
      locationPermissionRequiredByPlatform: value['locationPermissionRequiredByPlatform'] as bool?,
      locationRequiredForDeviceCompatibility: value['locationRequiredForDeviceCompatibility'] as bool?,
      locationCompatibilityRule: value['locationCompatibilityRule'] as String?,
      manufacturer: value['manufacturer'] as String?,
      model: value['model'] as String?,
      androidRelease: value['androidRelease'] as String?,
      sdkInt: value['sdkInt'] as int?,
      packageId: value['packageId'] as String?,
      buildFlavor: value['buildFlavor'] as String?,
      buildType: value['buildType'] as String?,
      appVersionName: value['appVersionName'] as String?,
      appVersionCode: value['appVersionCode']?.toString(),
      gitCommit: _knownBuildValue(value['gitCommit']),
      buildDirty: value['buildDirty'] as bool?,
      buildId: value['buildId'] as String?,
      sourceFingerprint: value['sourceFingerprint'] as String?,
      apkSha256: _knownBuildValue(value['apkSha256']),
      scanPermissionPolicy: value['scanPermissionPolicy'] as String?,
      scanFlavor: value['scanFlavor'] as String?,
      scanStrategyFallbackEnabled: value['scanStrategyFallbackEnabled'] as bool? ?? false,
      scanMode: value['scanMode'] as String?,
    );
  }

  static BleScanPermissionState _permissionFromBool(Object? value) => switch (value) {
    true => BleScanPermissionState.granted,
    false => BleScanPermissionState.denied,
    _ => BleScanPermissionState.unknown,
  };

  static BleScanPermissionState _permissionFromValue(Object? value) => switch (value) {
    'not_required' => BleScanPermissionState.notRequired,
    'not_requested' || 'notRequested' => BleScanPermissionState.notRequested,
    'granted' || true => BleScanPermissionState.granted,
    'denied' || false => BleScanPermissionState.denied,
    _ => BleScanPermissionState.unknown,
  };

  static BleLocationServiceState _locationServiceFromValue(Object? value) => switch (value) {
    'not_required' || 'notRequired' => BleLocationServiceState.notRequired,
    'enabled' || true => BleLocationServiceState.enabled,
    'disabled' || false => BleLocationServiceState.disabled,
    _ => BleLocationServiceState.unknown,
  };

  static String? _knownBuildValue(Object? value) => value is String && value.isNotEmpty && value != 'unknown' ? value : null;
}

/// One redacted raw Android scan callback.
final class BleScanObservationDiagnostic {
  const BleScanObservationDiagnostic({
    required this.occurredAt,
    required this.accepted,
    required this.reasonCode,
    this.addressHash,
    this.name,
    this.alias,
    this.rssi,
    this.serviceUuids = const [],
    this.manufacturerDataPresent = false,
    this.manufacturerDataLength = 0,
    this.scanRecordLength,
    this.scanRecordSha256,
    this.scanRecordRedactedHex,
    this.scanRecordTruncated = false,
    this.strategyIndex,
    this.strategyName,
    this.strategyGeneration,
    this.deviceNamePresent = false,
  });

  final DateTime occurredAt;
  final bool accepted;
  final String reasonCode;
  final String? addressHash;
  final String? name;
  final String? alias;
  final int? rssi;
  final List<String> serviceUuids;
  final bool manufacturerDataPresent;
  final int manufacturerDataLength;
  final int? scanRecordLength;
  final String? scanRecordSha256;
  final String? scanRecordRedactedHex;
  final bool scanRecordTruncated;
  final int? strategyIndex;
  final String? strategyName;
  final int? strategyGeneration;
  final bool deviceNamePresent;

  Map<String, Object?> toJson() => {
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    if (addressHash != null) 'address_hash': addressHash,
    if (name != null) 'name': name,
    if (alias != null) 'alias': alias,
    if (rssi != null) 'rssi': rssi,
    'service_uuids': serviceUuids,
    'manufacturer_data_present': manufacturerDataPresent,
    'manufacturer_data_length': manufacturerDataLength,
    if (scanRecordLength != null) 'scan_record_length': scanRecordLength,
    if (scanRecordSha256 != null) 'scan_record_sha256': scanRecordSha256,
    if (scanRecordRedactedHex != null) 'scan_record_redacted_hex': scanRecordRedactedHex,
    if (scanRecordRedactedHex != null) 'scan_record_truncated': scanRecordTruncated,
    if (strategyIndex != null) 'strategy_index': strategyIndex,
    if (strategyName != null) 'strategy_name': strategyName,
    if (strategyGeneration != null) 'strategy_generation': strategyGeneration,
    'device_name_present': deviceNamePresent,
    'accepted': accepted,
    'reason_code': reasonCode,
  };

  factory BleScanObservationDiagnostic.fromJson(Map<String, dynamic> value) => BleScanObservationDiagnostic(
    occurredAt: DateTime.parse(value['occurred_at'] as String),
    addressHash: value['address_hash'] as String?,
    name: value['name'] as String?,
    alias: value['alias'] as String?,
    rssi: value['rssi'] as int?,
    serviceUuids: (value['service_uuids'] as List? ?? const []).whereType<String>().toList(growable: false),
    manufacturerDataPresent: value['manufacturer_data_present'] as bool? ?? false,
    manufacturerDataLength: value['manufacturer_data_length'] as int? ?? 0,
    // v2 records did not contain a parseable redacted representation.
    // Do not relabel their length/hash-only observations as complete v3
    // evidence when the cache is migrated.
    scanRecordLength: value['scan_record_redacted_hex'] is String ? value['scan_record_length'] as int? : null,
    scanRecordSha256: value['scan_record_redacted_hex'] is String ? value['scan_record_sha256'] as String? : null,
    scanRecordRedactedHex: value['scan_record_redacted_hex'] as String?,
    scanRecordTruncated: value['scan_record_truncated'] as bool? ?? false,
    strategyIndex: value['strategy_index'] as int?,
    strategyName: value['strategy_name'] as String?,
    strategyGeneration: value['strategy_generation'] as int?,
    deviceNamePresent: value['device_name_present'] as bool? ?? false,
    accepted: value['accepted'] as bool? ?? false,
    reasonCode: value['reason_code'] as String? ?? 'legacy_unknown',
  );
}

/// One native strategy lifecycle event from the serial Huawei scan fallback.
final class BleScanStrategyDiagnostic {
  const BleScanStrategyDiagnostic({
    required this.occurredAt,
    required this.event,
    required this.index,
    required this.name,
    required this.generation,
    required this.switchReason,
    required this.rawResultCount,
    required this.deviceNameResultCount,
    required this.candidateCount,
    this.locationService = BleLocationServiceState.unknown,
    this.androidScanErrorCode,
  });

  final DateTime occurredAt;
  final String event;
  final int index;
  final String name;
  final int generation;
  final String switchReason;
  final int rawResultCount;
  final int deviceNameResultCount;
  final int candidateCount;
  final BleLocationServiceState locationService;
  final int? androidScanErrorCode;

  Map<String, Object?> toJson() => {
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'event': event,
    'index': index,
    'name': name,
    'generation': generation,
    'switch_reason': switchReason,
    'raw_result_count': rawResultCount,
    'device_name_result_count': deviceNameResultCount,
    'candidate_count': candidateCount,
    'location_service': locationService.name,
    if (androidScanErrorCode != null) 'android_scan_error_code': androidScanErrorCode,
  };

  factory BleScanStrategyDiagnostic.fromJson(Map<String, dynamic> value) => BleScanStrategyDiagnostic(
    occurredAt: DateTime.parse(value['occurred_at'] as String),
    event: value['event'] as String? ?? 'unknown',
    index: value['index'] as int? ?? -1,
    name: value['name'] as String? ?? 'UNKNOWN',
    generation: value['generation'] as int? ?? -1,
    switchReason: value['switch_reason'] as String? ?? 'unknown',
    rawResultCount: value['raw_result_count'] as int? ?? 0,
    deviceNameResultCount: value['device_name_result_count'] as int? ?? 0,
    candidateCount: value['candidate_count'] as int? ?? 0,
    locationService: BleScanEnvironment._locationServiceFromValue(
      value['location_service'],
    ),
    androidScanErrorCode: value['android_scan_error_code'] as int?,
  );
}

/// Secret-safe evidence for one Android BLE discovery session.
final class BleScanDiagnosticSession {
  const BleScanDiagnosticSession({
    required this.scanSessionId,
    this.recordSequence,
    this.flowId,
    this.scanTrigger,
    this.previousScanSessionId,
    required this.startedAt,
    required this.endedAt,
    required this.permissionBefore,
    required this.permissionAfter,
    required this.adapterBefore,
    required this.adapterAfter,
    required this.rawResultCount,
    required this.acceptedCount,
    required this.filteredCount,
    required this.reasonCounts,
    required this.endReason,
    this.nativeStartedAt,
    this.firstRawResultAt,
    this.firstCandidateAt,
    this.androidScanErrorCode,
    this.scanPermissionBefore = BleScanPermissionState.unknown,
    this.scanPermissionAfter = BleScanPermissionState.unknown,
    this.connectPermissionBefore = BleScanPermissionState.unknown,
    this.connectPermissionAfter = BleScanPermissionState.unknown,
    this.locationPermissionBefore = BleScanPermissionState.unknown,
    this.locationPermissionAfter = BleScanPermissionState.unknown,
    this.locationServiceBefore = BleLocationServiceState.unknown,
    this.locationServiceAfter = BleLocationServiceState.unknown,
    this.locationRequiredByApp,
    this.locationPermissionRequiredByPlatform,
    this.locationRequiredForDeviceCompatibility,
    this.locationCompatibilityRule,
    this.manufacturer,
    this.model,
    this.androidRelease,
    this.sdkInt,
    this.packageId,
    this.buildFlavor,
    this.buildType,
    this.appVersionName,
    this.appVersionCode,
    this.gitCommit,
    this.buildDirty,
    this.buildId,
    this.sourceFingerprint,
    this.apkSha256,
    this.scanPermissionPolicy,
    this.scanFlavor,
    this.scanStrategyFallbackEnabled = false,
    this.scanMode = 'low_latency',
    this.uniqueDeviceCount = 0,
    this.observations = const [],
    this.strategyEvents = const [],
  });

  final String scanSessionId;
  final int? recordSequence;
  final String? flowId;
  final String? scanTrigger;
  final String? previousScanSessionId;
  final DateTime startedAt;
  final DateTime? nativeStartedAt;
  final DateTime? firstRawResultAt;
  final DateTime? firstCandidateAt;
  final DateTime endedAt;
  final BleScanPermissionState permissionBefore;
  final BleScanPermissionState permissionAfter;
  final BleAdapterState adapterBefore;
  final BleAdapterState adapterAfter;
  final BleScanPermissionState scanPermissionBefore;
  final BleScanPermissionState scanPermissionAfter;
  final BleScanPermissionState connectPermissionBefore;
  final BleScanPermissionState connectPermissionAfter;
  final BleScanPermissionState locationPermissionBefore;
  final BleScanPermissionState locationPermissionAfter;
  final BleLocationServiceState locationServiceBefore;
  final BleLocationServiceState locationServiceAfter;
  final bool? locationRequiredByApp;
  final bool? locationPermissionRequiredByPlatform;
  final bool? locationRequiredForDeviceCompatibility;
  final String? locationCompatibilityRule;
  final String? manufacturer;
  final String? model;
  final String? androidRelease;
  final int? sdkInt;
  final String? packageId;
  final String? buildFlavor;
  final String? buildType;
  final String? appVersionName;
  final String? appVersionCode;
  final String? gitCommit;
  final bool? buildDirty;
  final String? buildId;
  final String? sourceFingerprint;
  final String? apkSha256;
  final String? scanPermissionPolicy;
  final String? scanFlavor;
  final bool scanStrategyFallbackEnabled;
  final String scanMode;
  final int rawResultCount;
  final int uniqueDeviceCount;
  final int acceptedCount;
  final int filteredCount;
  final Map<String, int> reasonCounts;
  final List<BleScanObservationDiagnostic> observations;
  final List<BleScanStrategyDiagnostic> strategyEvents;
  final BleScanEndReason endReason;
  final int? androidScanErrorCode;

  Duration get duration => endedAt.difference(startedAt);

  Map<String, Object?> toJson() => {
    'schema_version': 4,
    if (locationRequiredByApp != null) 'location_required_by_app': locationRequiredByApp,
    if (locationPermissionRequiredByPlatform != null) 'location_permission_required_by_platform': locationPermissionRequiredByPlatform,
    if (locationRequiredForDeviceCompatibility != null) 'location_required_for_device_compatibility': locationRequiredForDeviceCompatibility,
    if (locationCompatibilityRule != null) 'location_compatibility_rule': locationCompatibilityRule,

    'trace_id': scanSessionId,
    'scan_session_id': scanSessionId,
    if (recordSequence != null) 'record_sequence': recordSequence,
    if (flowId != null) 'flow_id': flowId,
    if (scanTrigger != null) 'scan_trigger': scanTrigger,
    if (previousScanSessionId != null) 'previous_scan_session_id': previousScanSessionId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'native_started_at': nativeStartedAt?.toUtc().toIso8601String(),
    'first_raw_result_at': firstRawResultAt?.toUtc().toIso8601String(),
    'first_candidate_at': firstCandidateAt?.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'duration_ms': duration.inMilliseconds,
    'permission_before': permissionBefore.name,
    'permission_after': permissionAfter.name,
    'scan_permission_before': scanPermissionBefore.name,
    'scan_permission_after': scanPermissionAfter.name,
    'connect_permission_before': connectPermissionBefore.name,
    'connect_permission_after': connectPermissionAfter.name,
    'location_permission_before': locationPermissionBefore.name,
    'location_permission_after': locationPermissionAfter.name,
    'adapter_before': adapterBefore.name,
    'adapter_after': adapterAfter.name,
    'location_service_before': locationServiceBefore.name,
    'location_service_after': locationServiceAfter.name,
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (model != null) 'model': model,
    if (androidRelease != null) 'android_release': androidRelease,
    if (sdkInt != null) 'sdk_int': sdkInt,
    if (packageId != null) 'package_id': packageId,
    if (buildFlavor != null) 'build_flavor': buildFlavor,
    if (buildType != null) 'build_type': buildType,
    if (appVersionName != null) 'app_version_name': appVersionName,
    if (appVersionCode != null) 'app_version_code': appVersionCode,
    if (gitCommit != null) 'git_commit': gitCommit,
    if (buildDirty != null) 'build_dirty': buildDirty,
    if (buildId != null) 'build_id': buildId,
    if (sourceFingerprint != null) 'source_fingerprint': sourceFingerprint,
    if (apkSha256 != null) 'apk_sha256': apkSha256,
    if (scanPermissionPolicy != null) 'scan_permission_policy': scanPermissionPolicy,
    if (scanFlavor != null) 'scan_flavor': scanFlavor,
    'scan_strategy_fallback_enabled': scanStrategyFallbackEnabled,
    'scan_mode': scanMode,
    'raw_result_count': rawResultCount,
    'unique_device_count': uniqueDeviceCount,
    'accepted_count': acceptedCount,
    'filtered_count': filteredCount,
    'reason_counts': reasonCounts,
    'observations': observations.map((item) => item.toJson()).toList(),
    'observations_total': rawResultCount,
    'observations_retained': observations.length,
    'observations_dropped': (rawResultCount - observations.length).clamp(0, rawResultCount),
    'strategy_events': strategyEvents.map((item) => item.toJson()).toList(),
    'end_reason': endReason.name,
    'android_scan_error_code': androidScanErrorCode,
  };

  factory BleScanDiagnosticSession.fromJson(Map<String, dynamic> value) => BleScanDiagnosticSession(
    scanSessionId: value['scan_session_id'] as String,
    recordSequence: value['record_sequence'] as int?,
    flowId: value['flow_id'] as String?,
    scanTrigger: value['scan_trigger'] as String?,
    previousScanSessionId: value['previous_scan_session_id'] as String?,
    startedAt: DateTime.parse(value['started_at'] as String),
    nativeStartedAt: _date(value['native_started_at']),
    firstRawResultAt: _date(value['first_raw_result_at']),
    firstCandidateAt: _date(value['first_candidate_at']),
    endedAt: DateTime.parse(value['ended_at'] as String),
    permissionBefore: _permission(value['permission_before']),
    permissionAfter: _permission(value['permission_after']),
    adapterBefore: _enumByName(
      BleAdapterState.values,
      value['adapter_before'],
      BleAdapterState.unknown,
    ),
    adapterAfter: _enumByName(
      BleAdapterState.values,
      value['adapter_after'],
      BleAdapterState.unknown,
    ),
    scanPermissionBefore: _permission(value['scan_permission_before']),
    scanPermissionAfter: _permission(value['scan_permission_after']),
    connectPermissionBefore: _permission(value['connect_permission_before']),
    connectPermissionAfter: _permission(value['connect_permission_after']),
    locationPermissionBefore: _permission(value['location_permission_before']),
    locationPermissionAfter: _permission(value['location_permission_after']),
    locationServiceBefore: _enumByName(
      BleLocationServiceState.values,
      value['location_service_before'],
      BleLocationServiceState.unknown,
    ),
    locationServiceAfter: _enumByName(
      BleLocationServiceState.values,
      value['location_service_after'],
      BleLocationServiceState.unknown,
    ),
    locationRequiredByApp: value['location_required_by_app'] as bool?,
    locationPermissionRequiredByPlatform: value['location_permission_required_by_platform'] as bool?,
    locationRequiredForDeviceCompatibility: value['location_required_for_device_compatibility'] as bool?,
    locationCompatibilityRule: value['location_compatibility_rule'] as String?,
    manufacturer: value['manufacturer'] as String?,
    model: value['model'] as String?,
    androidRelease: value['android_release'] as String?,
    sdkInt: value['sdk_int'] as int?,
    packageId: value['package_id'] as String?,
    buildFlavor: value['build_flavor'] as String?,
    buildType: value['build_type'] as String?,
    appVersionName: value['app_version_name'] as String?,
    appVersionCode: value['app_version_code']?.toString(),
    gitCommit: value['git_commit'] as String?,
    buildDirty: value['build_dirty'] as bool?,
    buildId: value['build_id'] as String?,
    sourceFingerprint: value['source_fingerprint'] as String?,
    apkSha256: value['apk_sha256'] as String?,
    scanPermissionPolicy: value['scan_permission_policy'] as String?,
    scanFlavor: value['scan_flavor'] as String?,
    scanStrategyFallbackEnabled: value['scan_strategy_fallback_enabled'] as bool? ?? false,
    scanMode: value['scan_mode'] as String? ?? 'low_latency',
    rawResultCount: value['raw_result_count'] as int? ?? 0,
    uniqueDeviceCount: value['unique_device_count'] as int? ?? 0,
    acceptedCount: value['accepted_count'] as int? ?? 0,
    filteredCount: value['filtered_count'] as int? ?? 0,
    reasonCounts: Map<String, int>.from(
      value['reason_counts'] as Map? ?? const <String, int>{},
    ),
    observations: (value['observations'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => BleScanObservationDiagnostic.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false),
    strategyEvents: (value['strategy_events'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => BleScanStrategyDiagnostic.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false),
    endReason: _enumByName(
      BleScanEndReason.values,
      value['end_reason'],
      BleScanEndReason.platformError,
    ),
    androidScanErrorCode: value['android_scan_error_code'] as int?,
  );

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;

  static BleScanPermissionState _permission(Object? value) => _enumByName(
    BleScanPermissionState.values,
    value,
    BleScanPermissionState.unknown,
  );

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? name,
    T fallback,
  ) => values.where((value) => value.name == name).firstOrNull ?? fallback;
}

abstract interface class BleScanDiagnosticSink {
  Future<void> record(BleScanDiagnosticSession session);
}

abstract interface class BleScanDiagnosticSource {
  Stream<BleScanDiagnosticSession> get scanDiagnostics;
}
