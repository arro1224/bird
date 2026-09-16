/// Secret-safe event in one BLE discovery/provisioning trace.
///
/// Only the explicitly listed fields are serialised. Device addresses, local
/// names, credentials, pairing codes, tokens, request payloads and raw packet
/// bytes must never be added to this model.
final class BleConnectionDiagnosticEvent {
  const BleConnectionDiagnosticEvent({
    required this.traceId,
    required this.occurredAt,
    required this.eventType,
    required this.source,
    this.manufacturer,
    this.model,
    this.androidRelease,
    this.sdkInt,
    this.appVersionName,
    this.appVersionCode,
    this.operationName,
    this.gattStatus,
    this.bondState,
    this.characteristicUuid,
    this.commandType,
    this.resultCode,
  });

  final String traceId;
  final DateTime occurredAt;
  final String eventType;
  final String source;
  final String? manufacturer;
  final String? model;
  final String? androidRelease;
  final int? sdkInt;
  final String? appVersionName;
  final String? appVersionCode;
  final String? operationName;
  final int? gattStatus;
  final String? bondState;
  final String? characteristicUuid;
  final String? commandType;
  final String? resultCode;

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'trace_id': traceId,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'event_type': eventType,
    'source': source,
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (model != null) 'model': model,
    if (androidRelease != null) 'android_release': androidRelease,
    if (sdkInt != null) 'sdk_int': sdkInt,
    if (appVersionName != null) 'app_version_name': appVersionName,
    if (appVersionCode != null) 'app_version_code': appVersionCode,
    if (operationName != null) 'operation_name': operationName,
    if (gattStatus != null) 'gatt_status': gattStatus,
    if (bondState != null) 'bond_state': bondState,
    if (characteristicUuid != null) 'characteristic_uuid': characteristicUuid,
    if (commandType != null) 'command_type': commandType,
    if (resultCode != null) 'result_code': resultCode,
  };

  factory BleConnectionDiagnosticEvent.fromJson(
    Map<String, dynamic> value,
  ) => BleConnectionDiagnosticEvent(
    traceId: value['trace_id'] as String,
    occurredAt: DateTime.parse(value['occurred_at'] as String),
    eventType: value['event_type'] as String,
    source: value['source'] as String,
    manufacturer: value['manufacturer'] as String?,
    model: value['model'] as String?,
    androidRelease: value['android_release'] as String?,
    sdkInt: value['sdk_int'] as int?,
    appVersionName: value['app_version_name'] as String?,
    appVersionCode: value['app_version_code']?.toString(),
    operationName: value['operation_name'] as String?,
    gattStatus: value['gatt_status'] as int?,
    bondState: value['bond_state'] as String?,
    characteristicUuid: value['characteristic_uuid'] as String?,
    commandType: value['command_type'] as String?,
    resultCode: value['result_code'] as String?,
  );

  factory BleConnectionDiagnosticEvent.fromPlatform(
    Map<String, dynamic> value,
  ) {
    final traceId = value['traceId'];
    final eventType = value['eventType'];
    if (traceId is! String || traceId.isEmpty) {
      throw const FormatException('BLE diagnostic traceId is missing');
    }
    if (eventType is! String || eventType.isEmpty) {
      throw const FormatException('BLE diagnostic eventType is missing');
    }
    final occurredAtMs = value['occurredAtMs'];
    return BleConnectionDiagnosticEvent(
      traceId: traceId,
      occurredAt: occurredAtMs is int ? DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true) : DateTime.now().toUtc(),
      eventType: eventType,
      source: 'android',
      manufacturer: value['manufacturer'] as String?,
      model: value['model'] as String?,
      androidRelease: value['androidRelease'] as String?,
      sdkInt: value['sdkInt'] as int?,
      appVersionName: value['appVersionName'] as String?,
      appVersionCode: value['appVersionCode']?.toString(),
      operationName: value['operationName'] as String?,
      gattStatus: value['gattStatus'] as int?,
      bondState: value['bondState'] as String?,
      characteristicUuid: value['characteristicUuid'] as String?,
      commandType: value['commandType'] as String?,
      resultCode: value['resultCode'] as String?,
    );
  }
}

abstract interface class BleConnectionDiagnosticSink {
  Future<void> record(BleConnectionDiagnosticEvent event);
}
