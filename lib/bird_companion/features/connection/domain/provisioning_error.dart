enum ProvisioningErrorOrigin { box, app, protocol }

enum ProvisioningErrorCode {
  protocolVersionUnsupported,
  invalidRequest,
  bleFragmentInvalid,
  requestIdConflict,
  capabilityUnsupported,
  deviceIdUnavailable,
  pairingNotOpen,
  pairingCodeInvalid,
  pairingCodeExpired,
  pairingRateLimited,
  pairingSessionInvalid,
  pairingSessionExpired,
  pairingSessionUsed,
  tokenInvalid,
  tokenExpired,
  authorizationRequired,
  authorizationFailed,
  invalidNetworkMode,
  networkOperationBusy,
  operationNotCancellable,
  wifiScanFailed,
  wifiNotFound,
  wifiSecurityUnsupported,
  wifiPasswordInvalid,
  dppBootstrapFailed,
  dppAuthenticationFailed,
  dppConfigurationRejected,
  dppNetworkUnsupported,
  dppTimeout,
  dppProfileImportFailed,
  staConnectTimeout,
  staDhcpFailed,
  apStartFailed,
  apStopFailed,
  apNotReady,
  networkSwitchFailed,
  networkRecoveryFailed,
  networkInternalError,
  bluetoothPermissionDenied,
  localNetworkPermissionDenied,
  systemWifiJoinDenied,
  phoneDppNotSupported,
  systemDppActivityUnavailable,
  systemDppInvalidUri,
  systemDppFailed,
  userCancelledDppDialog,
  userCancelledWifiDialog,
  phoneRejectedNoInternetNetwork,
  localNetworkIsolated,
  healthCheckFailed,
  deviceIdMismatch,
}

extension ProvisioningErrorCodeWireValue on ProvisioningErrorCode {
  String get wireValue => switch (this) {
    ProvisioningErrorCode.protocolVersionUnsupported => 'PROTOCOL_VERSION_UNSUPPORTED',
    ProvisioningErrorCode.invalidRequest => 'INVALID_REQUEST',
    ProvisioningErrorCode.bleFragmentInvalid => 'BLE_FRAGMENT_INVALID',
    ProvisioningErrorCode.requestIdConflict => 'REQUEST_ID_CONFLICT',
    ProvisioningErrorCode.capabilityUnsupported => 'CAPABILITY_UNSUPPORTED',
    ProvisioningErrorCode.deviceIdUnavailable => 'DEVICE_ID_UNAVAILABLE',
    ProvisioningErrorCode.pairingNotOpen => 'PAIRING_NOT_OPEN',
    ProvisioningErrorCode.pairingCodeInvalid => 'PAIRING_CODE_INVALID',
    ProvisioningErrorCode.pairingCodeExpired => 'PAIRING_CODE_EXPIRED',
    ProvisioningErrorCode.pairingRateLimited => 'PAIRING_RATE_LIMITED',
    ProvisioningErrorCode.pairingSessionInvalid => 'PAIRING_SESSION_INVALID',
    ProvisioningErrorCode.pairingSessionExpired => 'PAIRING_SESSION_EXPIRED',
    ProvisioningErrorCode.pairingSessionUsed => 'PAIRING_SESSION_USED',
    ProvisioningErrorCode.tokenInvalid => 'TOKEN_INVALID',
    ProvisioningErrorCode.tokenExpired => 'TOKEN_EXPIRED',
    ProvisioningErrorCode.authorizationRequired => 'AUTHORIZATION_REQUIRED',
    ProvisioningErrorCode.authorizationFailed => 'AUTHORIZATION_FAILED',
    ProvisioningErrorCode.invalidNetworkMode => 'INVALID_NETWORK_MODE',
    ProvisioningErrorCode.networkOperationBusy => 'NETWORK_OPERATION_BUSY',
    ProvisioningErrorCode.operationNotCancellable => 'OPERATION_NOT_CANCELLABLE',
    ProvisioningErrorCode.wifiScanFailed => 'WIFI_SCAN_FAILED',
    ProvisioningErrorCode.wifiNotFound => 'WIFI_NOT_FOUND',
    ProvisioningErrorCode.wifiSecurityUnsupported => 'WIFI_SECURITY_UNSUPPORTED',
    ProvisioningErrorCode.wifiPasswordInvalid => 'WIFI_PASSWORD_INVALID',
    ProvisioningErrorCode.dppBootstrapFailed => 'DPP_BOOTSTRAP_FAILED',
    ProvisioningErrorCode.dppAuthenticationFailed => 'DPP_AUTHENTICATION_FAILED',
    ProvisioningErrorCode.dppConfigurationRejected => 'DPP_CONFIGURATION_REJECTED',
    ProvisioningErrorCode.dppNetworkUnsupported => 'DPP_NETWORK_UNSUPPORTED',
    ProvisioningErrorCode.dppTimeout => 'DPP_TIMEOUT',
    ProvisioningErrorCode.dppProfileImportFailed => 'DPP_PROFILE_IMPORT_FAILED',
    ProvisioningErrorCode.staConnectTimeout => 'STA_CONNECT_TIMEOUT',
    ProvisioningErrorCode.staDhcpFailed => 'STA_DHCP_FAILED',
    ProvisioningErrorCode.apStartFailed => 'AP_START_FAILED',
    ProvisioningErrorCode.apStopFailed => 'AP_STOP_FAILED',
    ProvisioningErrorCode.apNotReady => 'AP_NOT_READY',
    ProvisioningErrorCode.networkSwitchFailed => 'NETWORK_SWITCH_FAILED',
    ProvisioningErrorCode.networkRecoveryFailed => 'NETWORK_RECOVERY_FAILED',
    ProvisioningErrorCode.networkInternalError => 'NETWORK_INTERNAL_ERROR',
    ProvisioningErrorCode.bluetoothPermissionDenied => 'BLUETOOTH_PERMISSION_DENIED',
    ProvisioningErrorCode.localNetworkPermissionDenied => 'LOCAL_NETWORK_PERMISSION_DENIED',
    ProvisioningErrorCode.systemWifiJoinDenied => 'SYSTEM_WIFI_JOIN_DENIED',
    ProvisioningErrorCode.phoneDppNotSupported => 'PHONE_DPP_NOT_SUPPORTED',
    ProvisioningErrorCode.systemDppActivityUnavailable => 'SYSTEM_DPP_ACTIVITY_UNAVAILABLE',
    ProvisioningErrorCode.systemDppInvalidUri => 'SYSTEM_DPP_INVALID_URI',
    ProvisioningErrorCode.systemDppFailed => 'SYSTEM_DPP_FAILED',
    ProvisioningErrorCode.userCancelledDppDialog => 'USER_CANCELLED_DPP_DIALOG',
    ProvisioningErrorCode.userCancelledWifiDialog => 'USER_CANCELLED_WIFI_DIALOG',
    ProvisioningErrorCode.phoneRejectedNoInternetNetwork => 'PHONE_REJECTED_NO_INTERNET_NETWORK',
    ProvisioningErrorCode.localNetworkIsolated => 'LOCAL_NETWORK_ISOLATED',
    ProvisioningErrorCode.healthCheckFailed => 'HEALTH_CHECK_FAILED',
    ProvisioningErrorCode.deviceIdMismatch => 'DEVICE_ID_MISMATCH',
  };

  ProvisioningErrorOrigin get origin => switch (this) {
    ProvisioningErrorCode.bluetoothPermissionDenied ||
    ProvisioningErrorCode.localNetworkPermissionDenied ||
    ProvisioningErrorCode.systemWifiJoinDenied ||
    ProvisioningErrorCode.phoneDppNotSupported ||
    ProvisioningErrorCode.systemDppActivityUnavailable ||
    ProvisioningErrorCode.systemDppInvalidUri ||
    ProvisioningErrorCode.systemDppFailed ||
    ProvisioningErrorCode.userCancelledDppDialog ||
    ProvisioningErrorCode.userCancelledWifiDialog ||
    ProvisioningErrorCode.phoneRejectedNoInternetNetwork ||
    ProvisioningErrorCode.localNetworkIsolated ||
    ProvisioningErrorCode.healthCheckFailed ||
    ProvisioningErrorCode.deviceIdMismatch => ProvisioningErrorOrigin.app,
    ProvisioningErrorCode.protocolVersionUnsupported || ProvisioningErrorCode.invalidRequest || ProvisioningErrorCode.bleFragmentInvalid || ProvisioningErrorCode.requestIdConflict => ProvisioningErrorOrigin.protocol,
    _ => ProvisioningErrorOrigin.box,
  };

  static ProvisioningErrorCode parse(String value) {
    for (final code in ProvisioningErrorCode.values) {
      if (code.wireValue == value) return code;
    }
    throw ProvisioningProtocolException('error.code', 'unsupported value "$value"');
  }
}

final class ProvisioningProtocolException implements FormatException {
  const ProvisioningProtocolException(this.field, this.message, [this.source]);

  final String field;
  @override
  final String message;
  @override
  final Object? source;
  @override
  int? get offset => null;

  @override
  String toString() => 'ProvisioningProtocolException($field: $message)';
}

final class ProvisioningException implements Exception {
  const ProvisioningException({required this.code, required this.retryable, this.retryAfter = Duration.zero, this.diagnosticMessage});

  final ProvisioningErrorCode code;
  final bool retryable;
  final Duration retryAfter;
  final String? diagnosticMessage;

  factory ProvisioningException.fromJson(Map<String, dynamic> json) {
    final rawCode = json['code'];
    final rawRetryable = json['retryable'];
    final rawRetryAfter = json['retry_after_ms'];
    if (rawCode is! String || rawCode.isEmpty) {
      throw const ProvisioningProtocolException('error.code', 'must be a non-empty string');
    }
    if (rawRetryable is! bool) {
      throw const ProvisioningProtocolException('error.retryable', 'must be a boolean');
    }
    if (rawRetryAfter is! int || rawRetryAfter < 0) {
      throw const ProvisioningProtocolException('error.retry_after_ms', 'must be a non-negative integer');
    }
    final rawMessage = json['message'];
    if (rawMessage != null && rawMessage is! String) {
      throw const ProvisioningProtocolException('error.message', 'must be a string');
    }
    return ProvisioningException(
      code: ProvisioningErrorCodeWireValue.parse(rawCode),
      retryable: rawRetryable,
      retryAfter: Duration(milliseconds: rawRetryAfter),
      diagnosticMessage: rawMessage as String?,
    );
  }

  @override
  String toString() => 'ProvisioningException(code: ${code.wireValue}, retryable: $retryable, retryAfter: ${retryAfter.inMilliseconds}ms)';
}
