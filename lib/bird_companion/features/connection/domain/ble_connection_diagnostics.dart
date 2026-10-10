/// Secret-safe event in one BLE discovery/provisioning trace.
final class BleConnectionDiagnosticEvent {
  const BleConnectionDiagnosticEvent({
    required this.traceId,
    this.recordSequence,
    this.flowId,
    required this.occurredAt,
    required this.eventType,
    required this.source,
    this.systemBondAttempted,
    this.createBondCallCount,
    this.bondElapsedMs,
    this.securityWriteAttemptCount,
    this.securityWriteResult,
    this.thread,
    this.callSource,
    this.teardownReason,
    this.deviceAddressHash,
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
    this.gattInstanceId,
    this.gattGeneration,
    this.connectionState,
    this.serviceDiscoveryResult,
    this.mtu,
    this.notificationState,
    this.operationName,
    this.platformMethod,
    this.pendingOperation,
    this.nativeState,
    this.securityPhase,
    this.gattPresent,
    this.linkReady,
    this.scanning,
    this.connectionGeneration,
    this.gattStatus,
    this.writeType,
    this.writeCallbackStatus,
    this.bondState,
    this.actualBondState,
    this.previousBondState,
    this.systemPairingInteraction,
    this.gattRebuilt,
    this.retryCount,
    this.conditionalBondFallbackAttempted,
    this.bondInitiationSource,
    this.securityGattStatusObserved,
    this.requestId,
    this.attemptId,
    this.securityTrigger,
    this.fallbackTrigger,
    this.characteristicUuid,
    this.writeApiAccepted,
    this.writeCallbackReceived,
    this.securityWriteElapsedMs,
    this.bondStateAtTrigger,
    this.createBondInvoked,
    this.createBondReturned,
    this.createBondStateBefore,
    this.createBondStateAfter,
    this.createBondException,
    this.stateBefore,
    this.stateAfter,
    this.terminalOutcome,
    this.cleanupOutcome,
    this.commandType,
    this.responseType,
    this.resultCode,
    this.errorCode,
    this.sanitizedMessage,
  });

  final String traceId;
  final int? recordSequence;
  final String? flowId;
  final DateTime occurredAt;
  final String eventType;
  final String source;
  final bool? systemBondAttempted;
  final int? createBondCallCount;
  final int? bondElapsedMs;
  final int? securityWriteAttemptCount;
  final String? securityWriteResult;
  final String? thread;
  final String? callSource;
  final String? teardownReason;
  final String? deviceAddressHash;
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
  final int? gattInstanceId;
  final int? gattGeneration;
  final String? connectionState;
  final String? serviceDiscoveryResult;
  final int? mtu;
  final String? notificationState;
  final String? operationName;
  final String? platformMethod;
  final String? pendingOperation;
  final String? nativeState;
  final String? securityPhase;
  final bool? gattPresent;
  final bool? linkReady;
  final bool? scanning;
  final int? connectionGeneration;
  final int? gattStatus;
  final String? writeType;
  final int? writeCallbackStatus;
  final String? bondState;
  final String? actualBondState;
  final String? previousBondState;
  final bool? systemPairingInteraction;
  final bool? gattRebuilt;
  final int? retryCount;
  final bool? conditionalBondFallbackAttempted;
  final String? bondInitiationSource;
  final bool? securityGattStatusObserved;
  final String? requestId;
  final String? attemptId;
  final String? securityTrigger;
  final String? fallbackTrigger;
  final String? characteristicUuid;
  final bool? writeApiAccepted;
  final bool? writeCallbackReceived;
  final int? securityWriteElapsedMs;
  final String? bondStateAtTrigger;
  final bool? createBondInvoked;
  final bool? createBondReturned;
  final String? createBondStateBefore;
  final String? createBondStateAfter;
  final String? createBondException;
  final String? stateBefore;
  final String? stateAfter;
  final String? terminalOutcome;
  final String? cleanupOutcome;
  final String? commandType;
  final String? responseType;
  final String? resultCode;
  final String? errorCode;
  final String? sanitizedMessage;

  Map<String, Object?> toJson() => {
    'schema_version': 4,
    if (systemBondAttempted != null) 'system_bond_attempted': systemBondAttempted,
    if (createBondCallCount != null) 'create_bond_call_count': createBondCallCount,
    if (bondElapsedMs != null) 'bond_elapsed_ms': bondElapsedMs,
    if (securityWriteAttemptCount != null) 'security_write_attempt_count': securityWriteAttemptCount,
    if (securityWriteResult != null) 'security_write_result': securityWriteResult,
    if (thread != null) 'thread': thread,
    if (callSource != null) 'call_source': callSource,
    if (teardownReason != null) 'teardown_reason': teardownReason,

    'trace_id': traceId,
    if (recordSequence != null) 'record_sequence': recordSequence,
    if (flowId != null) 'flow_id': flowId,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'event_type': eventType,
    'source': source,
    if (deviceAddressHash != null) 'device_address_hash': deviceAddressHash,
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
    if (gattInstanceId != null) 'gatt_instance_id': gattInstanceId,
    if (gattGeneration != null) 'gatt_generation': gattGeneration,
    if (connectionState != null) 'connection_state': connectionState,
    if (serviceDiscoveryResult != null) 'service_discovery_result': serviceDiscoveryResult,
    if (mtu != null) 'mtu': mtu,
    if (notificationState != null) 'notification_state': notificationState,
    if (operationName != null) 'operation_name': operationName,
    if (platformMethod != null) 'platform_method': platformMethod,
    if (pendingOperation != null) 'pending_operation': pendingOperation,
    if (nativeState != null) 'native_state': nativeState,
    if (securityPhase != null) 'security_phase': securityPhase,
    if (gattPresent != null) 'gatt_present': gattPresent,
    if (linkReady != null) 'link_ready': linkReady,
    if (scanning != null) 'scanning': scanning,
    if (connectionGeneration != null) 'connection_generation': connectionGeneration,
    if (gattStatus != null) 'gatt_status': gattStatus,
    if (writeType != null) 'write_type': writeType,
    if (writeCallbackStatus != null) 'write_callback_status': writeCallbackStatus,
    if (bondState != null) 'bond_state': bondState,
    if (actualBondState != null) 'actual_bond_state': actualBondState,
    if (previousBondState != null) 'previous_bond_state': previousBondState,
    if (systemPairingInteraction != null) 'system_pairing_interaction': systemPairingInteraction,
    if (gattRebuilt != null) 'gatt_rebuilt': gattRebuilt,
    if (retryCount != null) 'retry_count': retryCount,
    if (conditionalBondFallbackAttempted != null) 'conditional_bond_fallback_attempted': conditionalBondFallbackAttempted,
    if (bondInitiationSource != null) 'bond_initiation_source': bondInitiationSource,
    if (securityGattStatusObserved != null) 'security_gatt_status_observed': securityGattStatusObserved,
    if (requestId != null) 'request_id': requestId,
    if (attemptId != null) 'attempt_id': attemptId,
    if (securityTrigger != null) 'security_trigger': securityTrigger,
    if (fallbackTrigger != null) 'fallback_trigger': fallbackTrigger,
    if (characteristicUuid != null) 'characteristic_uuid': characteristicUuid,
    if (writeApiAccepted != null) 'write_api_accepted': writeApiAccepted,
    if (writeCallbackReceived != null) 'write_callback_received': writeCallbackReceived,
    if (securityWriteElapsedMs != null) 'security_write_elapsed_ms': securityWriteElapsedMs,
    if (bondStateAtTrigger != null) 'bond_state_at_trigger': bondStateAtTrigger,
    if (createBondInvoked != null) 'create_bond_invoked': createBondInvoked,
    if (createBondReturned != null) 'create_bond_returned': createBondReturned,
    if (createBondStateBefore != null) 'create_bond_state_before': createBondStateBefore,
    if (createBondStateAfter != null) 'create_bond_state_after': createBondStateAfter,
    if (createBondException != null) 'create_bond_exception': createBondException,
    if (stateBefore != null) 'state_before': stateBefore,
    if (stateAfter != null) 'state_after': stateAfter,
    if (terminalOutcome != null) 'terminal_outcome': terminalOutcome,
    if (cleanupOutcome != null) 'cleanup_outcome': cleanupOutcome,
    if (commandType != null) 'command_type': commandType,
    if (responseType != null) 'response_type': responseType,
    if (resultCode != null) 'result_code': resultCode,
    if (errorCode != null) 'error_code': errorCode,
    if (sanitizedMessage != null) 'sanitized_message': sanitizedMessage,
  };

  factory BleConnectionDiagnosticEvent.fromJson(Map<String, dynamic> value) => BleConnectionDiagnosticEvent(
    traceId: value['trace_id'] as String,
    recordSequence: value['record_sequence'] as int?,
    flowId: value['flow_id'] as String?,
    occurredAt: DateTime.parse(value['occurred_at'] as String),
    eventType: value['event_type'] as String,
    source: value['source'] as String,
    systemBondAttempted: value['system_bond_attempted'] as bool?,
    createBondCallCount: value['create_bond_call_count'] as int?,
    bondElapsedMs: value['bond_elapsed_ms'] as int?,
    securityWriteAttemptCount: value['security_write_attempt_count'] as int?,
    securityWriteResult: value['security_write_result'] as String?,
    thread: value['thread'] as String?,
    callSource: value['call_source'] as String?,
    teardownReason: value['teardown_reason'] as String?,
    deviceAddressHash: value['device_address_hash'] as String?,
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
    gattInstanceId: value['gatt_instance_id'] as int?,
    gattGeneration: (value['gatt_generation'] ?? value['gatt_instance_id']) as int?,
    connectionState: value['connection_state'] as String?,
    serviceDiscoveryResult: value['service_discovery_result'] as String?,
    mtu: value['mtu'] as int?,
    notificationState: value['notification_state'] as String?,
    operationName: value['operation_name'] as String?,
    platformMethod: value['platform_method'] as String?,
    pendingOperation: value['pending_operation'] as String?,
    nativeState: value['native_state'] as String?,
    securityPhase: value['security_phase'] as String?,
    gattPresent: value['gatt_present'] as bool?,
    linkReady: value['link_ready'] as bool?,
    scanning: value['scanning'] as bool?,
    connectionGeneration: value['connection_generation'] as int?,
    gattStatus: value['gatt_status'] as int?,
    writeType: value['write_type'] as String?,
    writeCallbackStatus: value['write_callback_status'] as int?,
    bondState: value['bond_state'] as String?,
    actualBondState: value['actual_bond_state'] as String?,
    previousBondState: value['previous_bond_state'] as String?,
    systemPairingInteraction: value['system_pairing_interaction'] as bool?,
    gattRebuilt: value['gatt_rebuilt'] as bool?,
    retryCount: value['retry_count'] as int?,
    conditionalBondFallbackAttempted: value['conditional_bond_fallback_attempted'] as bool?,
    bondInitiationSource: value['bond_initiation_source'] as String?,
    securityGattStatusObserved: value['security_gatt_status_observed'] as bool?,
    requestId: value['request_id'] as String?,
    attemptId: value['attempt_id'] as String?,
    securityTrigger: value['security_trigger'] as String?,
    fallbackTrigger: (value['fallback_trigger'] ?? value['security_trigger']) as String?,
    characteristicUuid: value['characteristic_uuid'] as String?,
    writeApiAccepted: value['write_api_accepted'] as bool?,
    writeCallbackReceived: value['write_callback_received'] as bool?,
    securityWriteElapsedMs: value['security_write_elapsed_ms'] as int?,
    bondStateAtTrigger: value['bond_state_at_trigger'] as String?,
    createBondInvoked: value['create_bond_invoked'] as bool?,
    createBondReturned: value['create_bond_returned'] as bool?,
    createBondStateBefore: value['create_bond_state_before'] as String?,
    createBondStateAfter: value['create_bond_state_after'] as String?,
    createBondException: value['create_bond_exception'] as String?,
    stateBefore: value['state_before'] as String?,
    stateAfter: value['state_after'] as String?,
    terminalOutcome: value['terminal_outcome'] as String?,
    cleanupOutcome: value['cleanup_outcome'] as String?,
    commandType: value['command_type'] as String?,
    responseType: value['response_type'] as String?,
    resultCode: value['result_code'] as String?,
    errorCode: value['error_code'] as String?,
    sanitizedMessage: value['sanitized_message'] as String?,
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
      flowId: value['flowId'] as String?,
      occurredAt: occurredAtMs is int ? DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true) : DateTime.now().toUtc(),
      eventType: eventType,
      source: 'android',
      systemBondAttempted: value['systemBondAttempted'] as bool?,
      createBondCallCount: value['createBondCallCount'] as int?,
      bondElapsedMs: value['bondElapsedMs'] as int?,
      securityWriteAttemptCount: value['securityWriteAttemptCount'] as int?,
      securityWriteResult: value['securityWriteResult'] as String?,
      thread: value['thread'] as String?,
      callSource: value['callSource'] as String?,
      teardownReason: value['teardownReason'] as String?,
      deviceAddressHash: value['deviceAddressHash'] as String?,
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
      gattInstanceId: value['gattInstanceId'] as int?,
      gattGeneration: (value['gattGeneration'] ?? value['gattInstanceId']) as int?,
      connectionState: value['connectionState'] as String?,
      serviceDiscoveryResult: value['serviceDiscoveryResult'] as String?,
      mtu: value['mtu'] as int?,
      notificationState: value['notificationState'] as String?,
      operationName: value['operationName'] as String?,
      platformMethod: value['platformMethod'] as String?,
      pendingOperation: value['pendingOperation'] as String?,
      nativeState: value['nativeState'] as String?,
      securityPhase: value['securityPhase'] as String?,
      gattPresent: value['gattPresent'] as bool?,
      linkReady: value['linkReady'] as bool?,
      scanning: value['scanning'] as bool?,
      connectionGeneration: value['connectionGeneration'] as int?,
      gattStatus: value['gattStatus'] as int?,
      writeType: value['writeType'] as String?,
      writeCallbackStatus: value['writeCallbackStatus'] as int?,
      bondState: value['bondState'] as String?,
      actualBondState: value['actualBondState'] as String?,
      previousBondState: value['previousBondState'] as String?,
      systemPairingInteraction: value['systemPairingInteraction'] as bool?,
      gattRebuilt: value['gattRebuilt'] as bool?,
      retryCount: value['retryCount'] as int?,
      conditionalBondFallbackAttempted: value['conditionalBondFallbackAttempted'] as bool?,
      bondInitiationSource: value['bondInitiationSource'] as String?,
      securityGattStatusObserved: value['securityGattStatusObserved'] as bool?,
      requestId: value['requestId'] as String?,
      attemptId: value['attemptId'] as String?,
      securityTrigger: value['securityTrigger'] as String?,
      fallbackTrigger: (value['fallbackTrigger'] ?? value['securityTrigger']) as String?,
      characteristicUuid: value['characteristicUuid'] as String?,
      writeApiAccepted: value['writeApiAccepted'] as bool?,
      writeCallbackReceived: value['writeCallbackReceived'] as bool?,
      securityWriteElapsedMs: value['securityWriteElapsedMs'] as int?,
      bondStateAtTrigger: value['bondStateAtTrigger'] as String?,
      createBondInvoked: value['createBondInvoked'] as bool?,
      createBondReturned: value['createBondReturned'] as bool?,
      createBondStateBefore: value['createBondStateBefore'] as String?,
      createBondStateAfter: value['createBondStateAfter'] as String?,
      createBondException: value['createBondException'] as String?,
      stateBefore: value['stateBefore'] as String?,
      stateAfter: value['stateAfter'] as String?,
      terminalOutcome: value['terminalOutcome'] as String?,
      cleanupOutcome: value['cleanupOutcome'] as String?,
      commandType: value['commandType'] as String?,
      responseType: value['responseType'] as String?,
      resultCode: value['resultCode'] as String?,
      errorCode: value['errorCode'] as String?,
      sanitizedMessage: value['sanitizedMessage'] as String?,
    );
  }

  static String? _knownBuildValue(Object? value) => value is String && value.isNotEmpty && value != 'unknown' ? value : null;
}

abstract interface class BleConnectionDiagnosticSink {
  Future<void> record(BleConnectionDiagnosticEvent event);
}
