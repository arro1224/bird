enum BleScanPermissionState { unknown, granted, denied }

enum BleAdapterState { unknown, unavailable, disabled, enabled }

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
  });

  const BleScanEnvironment.unknown()
    : permission = BleScanPermissionState.unknown,
      adapter = BleAdapterState.unknown;

  final BleScanPermissionState permission;
  final BleAdapterState adapter;

  factory BleScanEnvironment.fromPlatform(Map<String, dynamic> value) {
    final permissionGranted = value['permissionGranted'];
    final adapterState = value['adapterState'];
    return BleScanEnvironment(
      permission: switch (permissionGranted) {
        true => BleScanPermissionState.granted,
        false => BleScanPermissionState.denied,
        _ => BleScanPermissionState.unknown,
      },
      adapter: switch (adapterState) {
        'unavailable' => BleAdapterState.unavailable,
        'disabled' => BleAdapterState.disabled,
        'enabled' => BleAdapterState.enabled,
        _ => BleAdapterState.unknown,
      },
    );
  }
}

/// Secret-safe evidence for one Android BLE discovery session.
///
/// Device handles, local names, manufacturer bytes and pairing data are
/// deliberately excluded so this object can be persisted and shared with
/// technical support.
final class BleScanDiagnosticSession {
  const BleScanDiagnosticSession({
    required this.scanSessionId,
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
  });

  final String scanSessionId;
  final DateTime startedAt;
  final DateTime? nativeStartedAt;
  final DateTime? firstRawResultAt;
  final DateTime? firstCandidateAt;
  final DateTime endedAt;
  final BleScanPermissionState permissionBefore;
  final BleScanPermissionState permissionAfter;
  final BleAdapterState adapterBefore;
  final BleAdapterState adapterAfter;
  final int rawResultCount;
  final int acceptedCount;
  final int filteredCount;
  final Map<String, int> reasonCounts;
  final BleScanEndReason endReason;
  final int? androidScanErrorCode;

  Duration get duration => endedAt.difference(startedAt);

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'scan_session_id': scanSessionId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'native_started_at': nativeStartedAt?.toUtc().toIso8601String(),
    'first_raw_result_at': firstRawResultAt?.toUtc().toIso8601String(),
    'first_candidate_at': firstCandidateAt?.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'duration_ms': duration.inMilliseconds,
    'permission_before': permissionBefore.name,
    'permission_after': permissionAfter.name,
    'adapter_before': adapterBefore.name,
    'adapter_after': adapterAfter.name,
    'raw_result_count': rawResultCount,
    'accepted_count': acceptedCount,
    'filtered_count': filteredCount,
    'reason_counts': reasonCounts,
    'end_reason': endReason.name,
    'android_scan_error_code': androidScanErrorCode,
  };

  factory BleScanDiagnosticSession.fromJson(Map<String, dynamic> value) => BleScanDiagnosticSession(
    scanSessionId: value['scan_session_id'] as String,
    startedAt: DateTime.parse(value['started_at'] as String),
    nativeStartedAt: _date(value['native_started_at']),
    firstRawResultAt: _date(value['first_raw_result_at']),
    firstCandidateAt: _date(value['first_candidate_at']),
    endedAt: DateTime.parse(value['ended_at'] as String),
    permissionBefore: _enumByName(
      BleScanPermissionState.values,
      value['permission_before'],
      BleScanPermissionState.unknown,
    ),
    permissionAfter: _enumByName(
      BleScanPermissionState.values,
      value['permission_after'],
      BleScanPermissionState.unknown,
    ),
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
    rawResultCount: value['raw_result_count'] as int? ?? 0,
    acceptedCount: value['accepted_count'] as int? ?? 0,
    filteredCount: value['filtered_count'] as int? ?? 0,
    reasonCounts: Map<String, int>.from(
      value['reason_counts'] as Map? ?? const <String, int>{},
    ),
    endReason: _enumByName(
      BleScanEndReason.values,
      value['end_reason'],
      BleScanEndReason.platformError,
    ),
    androidScanErrorCode: value['android_scan_error_code'] as int?,
  );

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;

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
