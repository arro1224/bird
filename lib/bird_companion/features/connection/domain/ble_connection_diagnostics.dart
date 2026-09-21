/// Secret-safe event in one BLE discovery/provisioning trace.
final class BleConnectionDiagnosticEvent {
  const BleConnectionDiagnosticEvent({
    required this.traceId,
    required this.occurredAt,
    required this.eventType,
    required this.source,
    this.deviceAddressHash,
    this.manufacturer,
    this.model,
    this.androidRelease,
    this.sdkInt,
    this.appVersionName,
    this.appVersionCode,
    this.gitCommit,
    this.apkSha256,
    this.gattInstanceId,
    this.connectionState,
    this.serviceDiscoveryResult,
    this.mtu,
    this.notificationState,
    this.operationName,
    this.gattStatus,
    this.writeType,
    this.writeCallbackStatus,
    this.bondState,
    this.previousBondState,
    this.systemPairingInteraction,
    this.gattRebuilt,
    this.retryCount,
    this.requestId,
    this.securityTrigger,
    this.characteristicUuid,
    this.commandType,
    this.responseType,
    this.resultCode,
  });

  final String traceId;
  final DateTime occurredAt;
  final String eventType;
  final String source;
  final String? deviceAddressHash;
  final String? manufacturer;
  final String? model;
  final String? androidRelease;
  final int? sdkInt;
  final String? appVersionName;
  final String? appVersionCode;
  final String? gitCommit;
  final String? apkSha256;
  final int? gattInstanceId;
  final String? connectionState;
  final String? serviceDiscoveryResult;
  final int? mtu;
  final String? notificationState;
  final String? operationName;
  final int? gattStatus;
  final String? writeType;
  final int? writeCallbackStatus;
  final String? bondState;
  final String? previousBondState;
  final bool? systemPairingInteraction;
  final bool? gattRebuilt;
  final int? retryCount;
  final String? requestId;
  final String? securityTrigger;
  final String? characteristicUuid;
  final String? commandType;
  final String? responseType;
  final String? resultCode;

  Map<String, Object?> toJson() => {
    'schema_version': 2,
    'trace_id': traceId,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'event_type': eventType,
    'source': source,
    if (deviceAddressHash != null) 'device_address_hash': deviceAddressHash,
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (model != null) 'model': model,
    if (androidRelease != null) 'android_release': androidRelease,
    if (sdkInt != null) 'sdk_int': sdkInt,
    if (appVersionName != null) 'app_version_name': appVersionName,
    if (appVersionCode != null) 'app_version_code': appVersionCode,
    if (gitCommit != null) 'git_commit': gitCommit,
    if (apkSha256 != null) 'apk_sha256': apkSha256,
    if (gattInstanceId != null) 'gatt_instance_id': gattInstanceId,
    if (connectionState != null) 'connection_state': connectionState,
    if (serviceDiscoveryResult != null)
      'service_discovery_result': serviceDiscoveryResult,
    if (mtu != null) 'mtu': mtu,
    if (notificationState != null) 'notification_state': notificationState,
    if (operationName != null) 'operation_name': operationName,
    if (gattStatus != null) 'gatt_status': gattStatus,
    if (writeType != null) 'write_type': writeType,
    if (writeCallbackStatus != null)
      'write_callback_status': writeCallbackStatus,
    if (bondState != null) 'bond_state': bondState,
    if (previousBondState != null) 'previous_bond_state': previousBondState,
    if (systemPairingInteraction != null)
      'system_pairing_interaction': systemPairingInteraction,
    if (gattRebuilt != null) 'gatt_rebuilt': gattRebuilt,
    if (retryCount != null) 'retry_count': retryCount,
    if (requestId != null) 'request_id': requestId,
    if (securityTrigger != null) 'security_trigger': securityTrigger,
    if (characteristicUuid != null) 'characteristic_uuid': characteristicUuid,
    if (commandType != null) 'command_type': commandType,
    if (responseType != null) 'response_type': responseType,
    if (resultCode != null) 'result_code': resultCode,
  };

  factory BleConnectionDiagnosticEvent.fromJson(Map<String, dynamic> value) =>
      BleConnectionDiagnosticEvent(
        traceId: value['trace_id'] as String,
        occurredAt: DateTime.parse(value['occurred_at'] as String),
        eventType: value['event_type'] as String,
        source: value['source'] as String,
        deviceAddressHash: value['device_address_hash'] as String?,
        manufacturer: value['manufacturer'] as String?,
        model: value['model'] as String?,
        androidRelease: value['android_release'] as String?,
        sdkInt: value['sdk_int'] as int?,
        appVersionName: value['app_version_name'] as String?,
        appVersionCode: value['app_version_code']?.toString(),
        gitCommit: value['git_commit'] as String?,
        apkSha256: value['apk_sha256'] as String?,
        gattInstanceId: value['gatt_instance_id'] as int?,
        connectionState: value['connection_state'] as String?,
        serviceDiscoveryResult: value['service_discovery_result'] as String?,
        mtu: value['mtu'] as int?,
        notificationState: value['notification_state'] as String?,
        operationName: value['operation_name'] as String?,
        gattStatus: value['gatt_status'] as int?,
        writeType: value['write_type'] as String?,
        writeCallbackStatus: value['write_callback_status'] as int?,
        bondState: value['bond_state'] as String?,
        previousBondState: value['previous_bond_state'] as String?,
        systemPairingInteraction: value['system_pairing_interaction'] as bool?,
        gattRebuilt: value['gatt_rebuilt'] as bool?,
        retryCount: value['retry_count'] as int?,
        requestId: value['request_id'] as String?,
        securityTrigger: value['security_trigger'] as String?,
        characteristicUuid: value['characteristic_uuid'] as String?,
        commandType: value['command_type'] as String?,
        responseType: value['response_type'] as String?,
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
      occurredAt: occurredAtMs is int
          ? DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true)
          : DateTime.now().toUtc(),
      eventType: eventType,
      source: 'android',
      deviceAddressHash: value['deviceAddressHash'] as String?,
      manufacturer: value['manufacturer'] as String?,
      model: value['model'] as String?,
      androidRelease: value['androidRelease'] as String?,
      sdkInt: value['sdkInt'] as int?,
      appVersionName: value['appVersionName'] as String?,
      appVersionCode: value['appVersionCode']?.toString(),
      gitCommit: _knownBuildValue(value['gitCommit']),
      apkSha256: _knownBuildValue(value['apkSha256']),
      gattInstanceId: value['gattInstanceId'] as int?,
      connectionState: value['connectionState'] as String?,
      serviceDiscoveryResult: value['serviceDiscoveryResult'] as String?,
      mtu: value['mtu'] as int?,
      notificationState: value['notificationState'] as String?,
      operationName: value['operationName'] as String?,
      gattStatus: value['gattStatus'] as int?,
      writeType: value['writeType'] as String?,
      writeCallbackStatus: value['writeCallbackStatus'] as int?,
      bondState: value['bondState'] as String?,
      previousBondState: value['previousBondState'] as String?,
      systemPairingInteraction: value['systemPairingInteraction'] as bool?,
      gattRebuilt: value['gattRebuilt'] as bool?,
      retryCount: value['retryCount'] as int?,
      requestId: value['requestId'] as String?,
      securityTrigger: value['securityTrigger'] as String?,
      characteristicUuid: value['characteristicUuid'] as String?,
      commandType: value['commandType'] as String?,
      responseType: value['responseType'] as String?,
      resultCode: value['resultCode'] as String?,
    );
  }

  static String? _knownBuildValue(Object? value) =>
      value is String && value.isNotEmpty && value != 'unknown' ? value : null;
}

abstract interface class BleConnectionDiagnosticSink {
  Future<void> record(BleConnectionDiagnosticEvent event);
}
