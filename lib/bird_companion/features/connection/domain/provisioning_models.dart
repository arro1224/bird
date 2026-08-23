import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

enum ProvisioningNetworkMode { none, directAp, infrastructureSta }

extension ProvisioningNetworkModeWireValue on ProvisioningNetworkMode {
  String get wireValue => switch (this) {
    ProvisioningNetworkMode.none => 'none',
    ProvisioningNetworkMode.directAp => 'direct_ap',
    ProvisioningNetworkMode.infrastructureSta => 'infrastructure_sta',
  };

  static ProvisioningNetworkMode parse(String value) => switch (value) {
    'none' => ProvisioningNetworkMode.none,
    'direct_ap' => ProvisioningNetworkMode.directAp,
    'infrastructure_sta' => ProvisioningNetworkMode.infrastructureSta,
    _ => throw ProvisioningProtocolException('network_mode', 'unsupported value "$value"'),
  };
}

enum StaNetworkKind { router, thisPhoneHotspot, otherPhoneHotspot, unknown }

extension StaNetworkKindWireValue on StaNetworkKind {
  String get wireValue => switch (this) {
    StaNetworkKind.router => 'router',
    StaNetworkKind.thisPhoneHotspot => 'this_phone_hotspot',
    StaNetworkKind.otherPhoneHotspot => 'other_phone_hotspot',
    StaNetworkKind.unknown => 'unknown',
  };

  static StaNetworkKind parse(String value) => switch (value) {
    'router' => StaNetworkKind.router,
    'this_phone_hotspot' => StaNetworkKind.thisPhoneHotspot,
    'other_phone_hotspot' => StaNetworkKind.otherPhoneHotspot,
    'unknown' => StaNetworkKind.unknown,
    _ => throw ProvisioningProtocolException('network_kind', 'unsupported value "$value"'),
  };
}

enum ProvisioningMethod { androidDpp, wifiQr, bleScanSelection, bleManual }

extension ProvisioningMethodWireValue on ProvisioningMethod {
  String get wireValue => switch (this) {
    ProvisioningMethod.androidDpp => 'android_dpp',
    ProvisioningMethod.wifiQr => 'wifi_qr',
    ProvisioningMethod.bleScanSelection => 'ble_scan_selection',
    ProvisioningMethod.bleManual => 'ble_manual',
  };

  static ProvisioningMethod parse(String value) => switch (value) {
    'android_dpp' => ProvisioningMethod.androidDpp,
    'wifi_qr' => ProvisioningMethod.wifiQr,
    'ble_scan_selection' => ProvisioningMethod.bleScanSelection,
    'ble_manual' => ProvisioningMethod.bleManual,
    _ => throw ProvisioningProtocolException('provisioning_method', 'unsupported value "$value"'),
  };
}

enum WifiSelectionMethod { scanResult, manual }

extension WifiSelectionMethodWireValue on WifiSelectionMethod {
  String get wireValue => switch (this) {
    WifiSelectionMethod.scanResult => 'scan_result',
    WifiSelectionMethod.manual => 'manual',
  };

  static WifiSelectionMethod parse(String value) => switch (value) {
    'scan_result' => WifiSelectionMethod.scanResult,
    'manual' => WifiSelectionMethod.manual,
    _ => throw ProvisioningProtocolException('selection_method', 'unsupported value "$value"'),
  };
}

enum WifiSecurity { open, wpa2Personal, wpa3Personal, wpa2Wpa3Transition }

extension WifiSecurityWireValue on WifiSecurity {
  String get wireValue => switch (this) {
    WifiSecurity.open => 'open',
    WifiSecurity.wpa2Personal => 'wpa2_personal',
    WifiSecurity.wpa3Personal => 'wpa3_personal',
    WifiSecurity.wpa2Wpa3Transition => 'wpa2_wpa3_transition',
  };

  static WifiSecurity parse(String value) => switch (value) {
    'open' => WifiSecurity.open,
    'wpa2_personal' => WifiSecurity.wpa2Personal,
    'wpa3_personal' => WifiSecurity.wpa3Personal,
    'wpa2_wpa3_transition' => WifiSecurity.wpa2Wpa3Transition,
    _ => throw ProvisioningProtocolException('security', 'unsupported value "$value"'),
  };
}

enum PairingCodeMode { fixedDev, sessionRandom }

extension PairingCodeModeWireValue on PairingCodeMode {
  String get wireValue => switch (this) {
    PairingCodeMode.fixedDev => 'fixed_dev',
    PairingCodeMode.sessionRandom => 'session_random',
  };

  static PairingCodeMode parse(String value) => switch (value) {
    'fixed_dev' => PairingCodeMode.fixedDev,
    'session_random' => PairingCodeMode.sessionRandom,
    _ => throw ProvisioningProtocolException('pairing_code_mode', 'unsupported value "$value"'),
  };
}

enum NetworkOperationState {
  idle,
  startingAp,
  apReady,
  stoppingAp,
  scanning,
  scanComplete,
  preparingDpp,
  waitingDppConfigurator,
  dppAuthenticating,
  dppConfigurationReceived,
  credentialsReceived,
  disconnectingCurrentNetwork,
  connectingSta,
  obtainingIp,
  staConnected,
  switching,
  recovering,
  failed,
  cancelled,
}

extension NetworkOperationStateWireValue on NetworkOperationState {
  String get wireValue => switch (this) {
    NetworkOperationState.idle => 'idle',
    NetworkOperationState.startingAp => 'starting_ap',
    NetworkOperationState.apReady => 'ap_ready',
    NetworkOperationState.stoppingAp => 'stopping_ap',
    NetworkOperationState.scanning => 'scanning',
    NetworkOperationState.scanComplete => 'scan_complete',
    NetworkOperationState.preparingDpp => 'preparing_dpp',
    NetworkOperationState.waitingDppConfigurator => 'waiting_dpp_configurator',
    NetworkOperationState.dppAuthenticating => 'dpp_authenticating',
    NetworkOperationState.dppConfigurationReceived => 'dpp_configuration_received',
    NetworkOperationState.credentialsReceived => 'credentials_received',
    NetworkOperationState.disconnectingCurrentNetwork => 'disconnecting_current_network',
    NetworkOperationState.connectingSta => 'connecting_sta',
    NetworkOperationState.obtainingIp => 'obtaining_ip',
    NetworkOperationState.staConnected => 'sta_connected',
    NetworkOperationState.switching => 'switching',
    NetworkOperationState.recovering => 'recovering',
    NetworkOperationState.failed => 'failed',
    NetworkOperationState.cancelled => 'cancelled',
  };

  bool get cancellable => switch (this) {
    NetworkOperationState.scanning || NetworkOperationState.preparingDpp || NetworkOperationState.waitingDppConfigurator || NetworkOperationState.dppAuthenticating => true,
    _ => false,
  };

  bool get terminal => switch (this) {
    NetworkOperationState.idle || NetworkOperationState.apReady || NetworkOperationState.scanComplete || NetworkOperationState.staConnected || NetworkOperationState.failed || NetworkOperationState.cancelled => true,
    _ => false,
  };

  static NetworkOperationState parse(String value) {
    for (final state in NetworkOperationState.values) {
      if (state.wireValue == value) return state;
    }
    throw ProvisioningProtocolException('operation_state', 'unsupported value "$value"');
  }
}

enum BleCommandType { openPairing, authorizePairing, getNetworkStatus, startDirectAp, stopDirectAp, scanWifi, setStaConfig, startDppProvisioning, cancelNetworkOperation }

enum ProvisioningAuthorizationType { pairingSession, bearerToken }

extension ProvisioningAuthorizationTypeWireValue on ProvisioningAuthorizationType {
  String get wireValue => switch (this) {
    ProvisioningAuthorizationType.pairingSession => 'pairing_session',
    ProvisioningAuthorizationType.bearerToken => 'bearer_token',
  };

  static ProvisioningAuthorizationType parse(String value) => switch (value) {
    'pairing_session' => ProvisioningAuthorizationType.pairingSession,
    'bearer_token' => ProvisioningAuthorizationType.bearerToken,
    _ => throw ProvisioningProtocolException('authorization.type', 'unsupported value "$value"'),
  };
}

final class ProvisioningAuthorization {
  const ProvisioningAuthorization({required this.type, required this.value}) : assert(value != '');

  final ProvisioningAuthorizationType type;
  final String value;

  factory ProvisioningAuthorization.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'type', 'value'}, 'authorization');
    return ProvisioningAuthorization(type: ProvisioningAuthorizationTypeWireValue.parse(_requiredString(json, 'type')), value: _requiredString(json, 'value'));
  }

  Map<String, dynamic> toProtocolJson() => {'type': type.wireValue, 'value': value};

  @override
  String toString() => 'ProvisioningAuthorization(type: ${type.wireValue}, value: <redacted>)';
}

extension BleCommandTypeWireValue on BleCommandType {
  String get wireValue => switch (this) {
    BleCommandType.openPairing => 'open_pairing',
    BleCommandType.authorizePairing => 'authorize_pairing',
    BleCommandType.getNetworkStatus => 'get_network_status',
    BleCommandType.startDirectAp => 'start_direct_ap',
    BleCommandType.stopDirectAp => 'stop_direct_ap',
    BleCommandType.scanWifi => 'scan_wifi',
    BleCommandType.setStaConfig => 'set_sta_config',
    BleCommandType.startDppProvisioning => 'start_dpp_provisioning',
    BleCommandType.cancelNetworkOperation => 'cancel_network_operation',
  };
}

enum ProvisioningEventType { pairingOpened, pairingAuthorized, commandAccepted, networkStatus, wifiScanResults, directApReady, directApStopped, staConnected, dppBootstrapReady, networkProgress, networkRecovered, cancelled }

extension ProvisioningEventTypeWireValue on ProvisioningEventType {
  String get wireValue => switch (this) {
    ProvisioningEventType.pairingOpened => 'pairing_opened',
    ProvisioningEventType.pairingAuthorized => 'pairing_authorized',
    ProvisioningEventType.commandAccepted => 'command_accepted',
    ProvisioningEventType.networkStatus => 'network_status',
    ProvisioningEventType.wifiScanResults => 'wifi_scan_results',
    ProvisioningEventType.directApReady => 'direct_ap_ready',
    ProvisioningEventType.directApStopped => 'direct_ap_stopped',
    ProvisioningEventType.staConnected => 'sta_connected',
    ProvisioningEventType.dppBootstrapReady => 'dpp_bootstrap_ready',
    ProvisioningEventType.networkProgress => 'network_progress',
    ProvisioningEventType.networkRecovered => 'network_recovered',
    ProvisioningEventType.cancelled => 'cancelled',
  };

  static ProvisioningEventType parse(String value) {
    for (final type in ProvisioningEventType.values) {
      if (type.wireValue == value) return type;
    }
    throw ProvisioningProtocolException('type', 'unsupported event "$value"');
  }
}

final class BirdBoxAdvertisement {
  BirdBoxAdvertisement({required this.localName, required Iterable<String> serviceUuids, required this.rssi, this.companyIdentifier, this.manufacturerPayload})
    : serviceUuids = Set.unmodifiable(serviceUuids.map(BleProtocolConstants.normalizeUuid));

  final String localName;
  final Set<String> serviceUuids;
  final int rssi;
  final int? companyIdentifier;
  final List<int>? manufacturerPayload;

  bool get hasBirdBoxService => BleProtocolConstants.hasBirdBoxService(serviceUuids);
  bool get hasValidLocalName => localName.startsWith(BleProtocolConstants.localNamePrefix);
  bool get hasManufacturerExtension => companyIdentifier != null && manufacturerPayload != null;
  bool get hasValidManufacturerExtension =>
      companyIdentifier == BleProtocolConstants.developmentCompanyIdentifier &&
      manufacturerPayload?.length == BleProtocolConstants.manufacturerPayloadLength &&
      manufacturerPayload?.first == BleProtocolConstants.advertisementStructureVersion;

  @override
  String toString() => 'BirdBoxAdvertisement(localName: $localName, hasBirdBoxService: $hasBirdBoxService, rssi: $rssi, manufacturerExtension: ${hasManufacturerExtension ? 'present' : 'absent'})';
}

final class ProvisioningDevice {
  const ProvisioningDevice({required this.scanId, required this.advertisement, this.deviceInfo});

  final String scanId;
  final BirdBoxAdvertisement advertisement;
  final ProvisioningDeviceInfo? deviceInfo;

  bool get identityConfirmed => deviceInfo != null;
}

final class DeviceCapabilities {
  const DeviceCapabilities({
    required this.directAp,
    required this.infrastructureSta,
    required this.wifiScan,
    required this.wifiManual,
    required this.dppEnrolleeSupported,
    required this.dppSupportedAkm,
    required this.modeSwitch,
    required this.networkRecovery,
    required this.bleFragmentationV1,
    required this.wifiApStaConcurrency,
    required this.apBand24Ghz,
    required this.apBand5Ghz,
  });

  final bool directAp;
  final bool infrastructureSta;
  final bool wifiScan;
  final bool wifiManual;
  final bool dppEnrolleeSupported;
  final Set<String> dppSupportedAkm;
  final bool modeSwitch;
  final bool networkRecovery;
  final bool bleFragmentationV1;
  final bool wifiApStaConcurrency;
  final bool apBand24Ghz;
  final bool apBand5Ghz;

  bool get dppUsableByBox => dppEnrolleeSupported && dppSupportedAkm.any(const {'psk', 'sae'}.contains);

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    const keys = <String>{
      'direct_ap',
      'infrastructure_sta',
      'wifi_scan',
      'wifi_manual',
      'dpp_enrollee_supported',
      'dpp_supported_akm',
      'mode_switch',
      'network_recovery',
      'ble_fragmentation_v1',
      'wifi_ap_sta_concurrency',
      'ap_band_2_4_ghz',
      'ap_band_5_ghz',
    };
    _rejectUnknownKeys(json, keys, 'capabilities');
    final akm = _requiredStringList(json, 'dpp_supported_akm').toSet();
    if (!const {'psk', 'sae'}.containsAll(akm)) {
      throw const ProvisioningProtocolException('capabilities.dpp_supported_akm', 'only psk and sae are allowed');
    }
    final dppSupported = _requiredBool(json, 'dpp_enrollee_supported');
    if (!dppSupported && akm.isNotEmpty) {
      throw const ProvisioningProtocolException('capabilities.dpp_supported_akm', 'must be empty when DPP is disabled');
    }
    return DeviceCapabilities(
      directAp: _requiredBool(json, 'direct_ap'),
      infrastructureSta: _requiredBool(json, 'infrastructure_sta'),
      wifiScan: _requiredBool(json, 'wifi_scan'),
      wifiManual: _requiredBool(json, 'wifi_manual'),
      dppEnrolleeSupported: dppSupported,
      dppSupportedAkm: Set.unmodifiable(akm),
      modeSwitch: _requiredBool(json, 'mode_switch'),
      networkRecovery: _requiredBool(json, 'network_recovery'),
      bleFragmentationV1: _requiredBool(json, 'ble_fragmentation_v1'),
      wifiApStaConcurrency: _requiredBool(json, 'wifi_ap_sta_concurrency'),
      apBand24Ghz: _requiredBool(json, 'ap_band_2_4_ghz'),
      apBand5Ghz: _requiredBool(json, 'ap_band_5_ghz'),
    );
  }
}

final class ProvisioningDeviceInfo {
  const ProvisioningDeviceInfo({
    required this.protocolVersion,
    required this.minAppProtocolVersion,
    required this.deviceId,
    required this.deviceName,
    required this.firmwareVersion,
    required this.apiVersion,
    required this.pairingCodeMode,
    required this.pairingCodeLength,
    required this.pairingCodeTtl,
    required this.displayAvailable,
    required this.capabilities,
  });

  final String protocolVersion;
  final String minAppProtocolVersion;
  final String deviceId;
  final String deviceName;
  final String firmwareVersion;
  final String apiVersion;
  final PairingCodeMode pairingCodeMode;
  final int pairingCodeLength;
  final Duration pairingCodeTtl;
  final bool displayAvailable;
  final DeviceCapabilities capabilities;

  factory ProvisioningDeviceInfo.fromJson(Map<String, dynamic> json) {
    const keys = <String>{
      'protocol_version',
      'min_app_protocol_version',
      'device_id',
      'device_name',
      'firmware_version',
      'api_version',
      'pairing_code_mode',
      'pairing_code_length',
      'pairing_code_ttl_seconds',
      'display_available',
      'capabilities',
    };
    _rejectUnknownKeys(json, keys, 'device_info');
    final protocolVersion = _requiredString(json, 'protocol_version');
    if (protocolVersion != BleProtocolConstants.protocolVersion) {
      throw ProvisioningProtocolException('protocol_version', 'expected ${BleProtocolConstants.protocolVersion}, got $protocolVersion');
    }
    final deviceId = _requiredString(json, 'device_id');
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId)) {
      throw const ProvisioningProtocolException('device_id', 'must match bbx- followed by 32 lowercase hex characters');
    }
    final name = _requiredString(json, 'device_name');
    if (!RegExp(r'^BirdBox-[0-9A-F]{8}$').hasMatch(name)) {
      throw const ProvisioningProtocolException('device_name', 'must match BirdBox-<8 uppercase hex>');
    }
    return ProvisioningDeviceInfo(
      protocolVersion: protocolVersion,
      minAppProtocolVersion: _requiredString(json, 'min_app_protocol_version'),
      deviceId: deviceId,
      deviceName: name,
      firmwareVersion: _requiredString(json, 'firmware_version'),
      apiVersion: _requiredString(json, 'api_version'),
      pairingCodeMode: PairingCodeModeWireValue.parse(_requiredString(json, 'pairing_code_mode')),
      pairingCodeLength: _requiredPositiveInt(json, 'pairing_code_length'),
      pairingCodeTtl: Duration(seconds: _requiredNonNegativeInt(json, 'pairing_code_ttl_seconds')),
      displayAvailable: _requiredBool(json, 'display_available'),
      capabilities: DeviceCapabilities.fromJson(_requiredMap(json, 'capabilities')),
    );
  }
}

final class DirectApSnapshot {
  const DirectApSnapshot({this.ssid, this.security, this.gatewayIpv4, this.prefixLength, this.clientCount});

  final String? ssid;
  final WifiSecurity? security;
  final String? gatewayIpv4;
  final int? prefixLength;
  final int? clientCount;

  factory DirectApSnapshot.fromJson(Map<String, dynamic> json) {
    const keys = <String>{'ssid', 'security', 'gateway_ipv4', 'prefix_length', 'client_count'};
    _rejectUnknownKeys(json, keys, 'direct_ap');
    return DirectApSnapshot(
      ssid: _optionalString(json, 'ssid'),
      security: _optionalEnum(json, 'security', WifiSecurityWireValue.parse),
      gatewayIpv4: _optionalString(json, 'gateway_ipv4'),
      prefixLength: _optionalNonNegativeInt(json, 'prefix_length'),
      clientCount: _optionalNonNegativeInt(json, 'client_count'),
    );
  }
}

final class InfrastructureStaSnapshot {
  const InfrastructureStaSnapshot({this.ssid, this.bssid, this.ipv4, this.prefixLength, this.gatewayIpv4, this.networkKind, this.provisioningMethod, required this.saved});

  final String? ssid;
  final String? bssid;
  final String? ipv4;
  final int? prefixLength;
  final String? gatewayIpv4;
  final StaNetworkKind? networkKind;
  final ProvisioningMethod? provisioningMethod;
  final bool saved;

  factory InfrastructureStaSnapshot.fromJson(Map<String, dynamic> json) {
    const keys = <String>{'ssid', 'bssid', 'ipv4', 'prefix_length', 'gateway_ipv4', 'network_kind', 'provisioning_method', 'saved'};
    _rejectUnknownKeys(json, keys, 'infrastructure_sta');
    return InfrastructureStaSnapshot(
      ssid: _optionalString(json, 'ssid'),
      bssid: _optionalString(json, 'bssid'),
      ipv4: _optionalString(json, 'ipv4'),
      prefixLength: _optionalNonNegativeInt(json, 'prefix_length'),
      gatewayIpv4: _optionalString(json, 'gateway_ipv4'),
      networkKind: _optionalEnum(json, 'network_kind', StaNetworkKindWireValue.parse),
      provisioningMethod: _optionalEnum(json, 'provisioning_method', ProvisioningMethodWireValue.parse),
      saved: _requiredBool(json, 'saved'),
    );
  }
}

final class ProvisioningNetworkStatus {
  const ProvisioningNetworkStatus({
    required this.activeMode,
    required this.desiredMode,
    required this.operationState,
    this.operationId,
    required this.busy,
    this.baseUri,
    required this.directAp,
    required this.infrastructureSta,
    this.lastError,
    required this.updatedAt,
  });

  final ProvisioningNetworkMode activeMode;
  final ProvisioningNetworkMode desiredMode;
  final NetworkOperationState operationState;
  final String? operationId;
  final bool busy;
  final Uri? baseUri;
  final DirectApSnapshot directAp;
  final InfrastructureStaSnapshot infrastructureSta;
  final ProvisioningException? lastError;
  final DateTime updatedAt;

  factory ProvisioningNetworkStatus.fromJson(Map<String, dynamic> json) {
    const keys = <String>{'active_mode', 'desired_mode', 'operation_state', 'operation_id', 'busy', 'base_uri', 'direct_ap', 'infrastructure_sta', 'last_error', 'updated_at'};
    _rejectUnknownKeys(json, keys, 'network_status');
    final lastErrorJson = _optionalMap(json, 'last_error');
    return ProvisioningNetworkStatus(
      activeMode: ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'active_mode')),
      desiredMode: ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'desired_mode')),
      operationState: NetworkOperationStateWireValue.parse(_requiredString(json, 'operation_state')),
      operationId: _optionalString(json, 'operation_id'),
      busy: _requiredBool(json, 'busy'),
      baseUri: _optionalUri(json, 'base_uri'),
      directAp: DirectApSnapshot.fromJson(_requiredMap(json, 'direct_ap')),
      infrastructureSta: InfrastructureStaSnapshot.fromJson(_requiredMap(json, 'infrastructure_sta')),
      lastError: lastErrorJson == null ? null : ProvisioningException.fromJson(lastErrorJson),
      updatedAt: _requiredDateTime(json, 'updated_at'),
    );
  }
}

final class PairingWindow {
  const PairingWindow({required this.mode, required this.codeExpiresIn, required this.attemptsRemaining});
  final PairingCodeMode mode;
  final Duration codeExpiresIn;
  final int attemptsRemaining;

  factory PairingWindow.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'pairing_code_mode', 'code_expires_in', 'attempts_remaining'}, 'pairing_opened');
    return PairingWindow(
      mode: PairingCodeModeWireValue.parse(_requiredString(json, 'pairing_code_mode')),
      codeExpiresIn: Duration(seconds: _requiredNonNegativeInt(json, 'code_expires_in')),
      attemptsRemaining: _requiredNonNegativeInt(json, 'attempts_remaining'),
    );
  }
}

final class PairingAuthorization {
  const PairingAuthorization._({required this.pairingSessionId, required this.expiresIn});
  final String pairingSessionId;
  final Duration expiresIn;

  factory PairingAuthorization.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'pairing_session_id', 'expires_in'}, 'pairing_authorized');
    return PairingAuthorization._(
      pairingSessionId: _requiredString(json, 'pairing_session_id'),
      expiresIn: Duration(seconds: _requiredPositiveInt(json, 'expires_in')),
    );
  }

  @override
  String toString() => 'PairingAuthorization(pairingSessionId: <redacted>, expiresIn: ${expiresIn.inSeconds}s)';
}

final class CommandAccepted {
  const CommandAccepted({required this.operationId, required this.desiredMode, this.provisioningMethod});
  final String operationId;
  final ProvisioningNetworkMode desiredMode;
  final ProvisioningMethod? provisioningMethod;

  factory CommandAccepted.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id', 'desired_mode', 'provisioning_method'}, 'command_accepted');
    return CommandAccepted(
      operationId: _operationId(json),
      desiredMode: ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'desired_mode')),
      provisioningMethod: _optionalEnum(json, 'provisioning_method', ProvisioningMethodWireValue.parse),
    );
  }
}

final class WifiScanNetwork {
  const WifiScanNetwork({required this.ssid, required this.bssid, required this.rssiDbm, required this.frequencyMhz, required this.security, required this.unsupported});
  final String ssid;
  final String bssid;
  final int rssiDbm;
  final int frequencyMhz;
  final WifiSecurity security;
  final bool unsupported;

  factory WifiScanNetwork.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'ssid', 'bssid', 'rssi_dbm', 'frequency_mhz', 'security', 'unsupported'}, 'wifi_scan_network');
    return WifiScanNetwork(
      ssid: _requiredString(json, 'ssid'),
      bssid: _requiredString(json, 'bssid'),
      rssiDbm: _requiredInt(json, 'rssi_dbm'),
      frequencyMhz: _requiredPositiveInt(json, 'frequency_mhz'),
      security: WifiSecurityWireValue.parse(_requiredString(json, 'security')),
      unsupported: json.containsKey('unsupported') ? _requiredBool(json, 'unsupported') : false,
    );
  }
}

final class WifiScanBatch {
  const WifiScanBatch({required this.batchIndex, required this.batchCount, required this.complete, required this.networks});
  final int batchIndex;
  final int batchCount;
  final bool complete;
  final List<WifiScanNetwork> networks;

  factory WifiScanBatch.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'batch_index', 'batch_count', 'complete', 'networks'}, 'wifi_scan_results');
    final rawNetworks = json['networks'];
    if (rawNetworks is! List) throw const ProvisioningProtocolException('networks', 'must be an array');
    final batchCount = _requiredPositiveInt(json, 'batch_count');
    final batchIndex = _requiredNonNegativeInt(json, 'batch_index');
    if (batchIndex >= batchCount) throw const ProvisioningProtocolException('batch_index', 'must be less than batch_count');
    return WifiScanBatch(
      batchIndex: batchIndex,
      batchCount: batchCount,
      complete: _requiredBool(json, 'complete'),
      networks: List.unmodifiable(rawNetworks.map((value) => WifiScanNetwork.fromJson(_asMap(value, 'networks[]')))),
    );
  }
}

final class DirectApReady {
  const DirectApReady._({required this.operationId, required this.ssid, required this.security, required this.passphrase, required this.gatewayIpv4, required this.prefixLength, required this.baseUri});
  final String operationId;
  final String ssid;
  final WifiSecurity security;
  final String passphrase;
  final String gatewayIpv4;
  final int prefixLength;
  final Uri baseUri;

  factory DirectApReady.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id', 'active_mode', 'ssid', 'security', 'passphrase', 'gateway_ipv4', 'prefix_length', 'base_uri'}, 'direct_ap_ready');
    if (ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'active_mode')) != ProvisioningNetworkMode.directAp) {
      throw const ProvisioningProtocolException('active_mode', 'direct_ap_ready must use direct_ap');
    }
    return DirectApReady._(
      operationId: _operationId(json),
      ssid: _requiredString(json, 'ssid'),
      security: WifiSecurityWireValue.parse(_requiredString(json, 'security')),
      passphrase: _requiredString(json, 'passphrase'),
      gatewayIpv4: _requiredString(json, 'gateway_ipv4'),
      prefixLength: _requiredNonNegativeInt(json, 'prefix_length'),
      baseUri: _requiredUri(json, 'base_uri'),
    );
  }

  @override
  String toString() => 'DirectApReady(operationId: $operationId, ssid: $ssid, passphrase: <redacted>, baseUri: $baseUri)';
}

final class DirectApStopped {
  const DirectApStopped({required this.operationId, required this.activeMode, required this.operationState, required this.restoredSta, required this.reason});
  final String operationId;
  final ProvisioningNetworkMode activeMode;
  final NetworkOperationState operationState;
  final bool restoredSta;
  final String reason;

  factory DirectApStopped.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id', 'active_mode', 'operation_state', 'restored_sta', 'reason'}, 'direct_ap_stopped');
    return DirectApStopped(
      operationId: _operationId(json),
      activeMode: ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'active_mode')),
      operationState: NetworkOperationStateWireValue.parse(_requiredString(json, 'operation_state')),
      restoredSta: _requiredBool(json, 'restored_sta'),
      reason: _requiredString(json, 'reason'),
    );
  }
}

final class StaConnected {
  const StaConnected({
    required this.operationId,
    required this.ssid,
    this.bssid,
    required this.ipv4,
    required this.prefixLength,
    required this.gatewayIpv4,
    required this.baseUri,
    required this.networkKind,
    required this.provisioningMethod,
  });
  final String operationId;
  final String ssid;
  final String? bssid;
  final String ipv4;
  final int prefixLength;
  final String gatewayIpv4;
  final Uri baseUri;
  final StaNetworkKind networkKind;
  final ProvisioningMethod provisioningMethod;

  factory StaConnected.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id', 'active_mode', 'ssid', 'bssid', 'ipv4', 'prefix_length', 'gateway_ipv4', 'base_uri', 'network_kind', 'provisioning_method'}, 'sta_connected');
    if (ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'active_mode')) != ProvisioningNetworkMode.infrastructureSta) {
      throw const ProvisioningProtocolException('active_mode', 'sta_connected must use infrastructure_sta');
    }
    return StaConnected(
      operationId: _operationId(json),
      ssid: _requiredString(json, 'ssid'),
      bssid: _optionalString(json, 'bssid'),
      ipv4: _requiredString(json, 'ipv4'),
      prefixLength: _requiredNonNegativeInt(json, 'prefix_length'),
      gatewayIpv4: _requiredString(json, 'gateway_ipv4'),
      baseUri: _requiredUri(json, 'base_uri'),
      networkKind: StaNetworkKindWireValue.parse(_requiredString(json, 'network_kind')),
      provisioningMethod: ProvisioningMethodWireValue.parse(_requiredString(json, 'provisioning_method')),
    );
  }
}

final class DppBootstrapReady {
  const DppBootstrapReady._({required this.operationId, required this.operationState, required this.dppUri, required this.expiresIn});
  final String operationId;
  final NetworkOperationState operationState;
  final Uri dppUri;
  final Duration expiresIn;

  factory DppBootstrapReady.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id', 'operation_state', 'dpp_uri', 'expires_in_seconds'}, 'dpp_bootstrap_ready');
    final rawUri = _requiredString(json, 'dpp_uri');
    if (!rawUri.startsWith('DPP:') || !rawUri.endsWith(';;')) {
      throw const ProvisioningProtocolException('dpp_uri', 'must be a standard DPP URI');
    }
    return DppBootstrapReady._(
      operationId: _operationId(json),
      operationState: NetworkOperationStateWireValue.parse(_requiredString(json, 'operation_state')),
      dppUri: Uri.parse(rawUri),
      expiresIn: Duration(seconds: _requiredPositiveInt(json, 'expires_in_seconds')),
    );
  }

  @override
  String toString() => 'DppBootstrapReady(operationId: $operationId, operationState: ${operationState.wireValue}, dppUri: <redacted>, expiresIn: ${expiresIn.inSeconds}s)';
}

final class NetworkProgress {
  const NetworkProgress({required this.operationId, required this.operationState, this.provisioningMethod, this.ssid, this.credentialsReceived});
  final String operationId;
  final NetworkOperationState operationState;
  final ProvisioningMethod? provisioningMethod;
  final String? ssid;
  final bool? credentialsReceived;

  factory NetworkProgress.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id', 'operation_state', 'provisioning_method', 'ssid', 'credentials_received'}, 'network_progress');
    return NetworkProgress(
      operationId: _operationId(json),
      operationState: NetworkOperationStateWireValue.parse(_requiredString(json, 'operation_state')),
      provisioningMethod: _optionalEnum(json, 'provisioning_method', ProvisioningMethodWireValue.parse),
      ssid: _optionalString(json, 'ssid'),
      credentialsReceived: _optionalBool(json, 'credentials_received'),
    );
  }
}

final class NetworkRecovered {
  const NetworkRecovered({
    required this.operationId,
    required this.activeMode,
    required this.operationState,
    required this.recoveredMode,
    required this.recoveryReason,
    this.ssid,
    this.security,
    this.passphrase,
    this.gatewayIpv4,
    this.prefixLength,
    this.baseUri,
  });
  final String operationId;
  final ProvisioningNetworkMode activeMode;
  final NetworkOperationState operationState;
  final ProvisioningNetworkMode recoveredMode;
  final String recoveryReason;
  final String? ssid;
  final WifiSecurity? security;
  final String? passphrase;
  final String? gatewayIpv4;
  final int? prefixLength;
  final Uri? baseUri;

  factory NetworkRecovered.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id', 'active_mode', 'operation_state', 'recovered_mode', 'recovery_reason', 'ssid', 'security', 'passphrase', 'gateway_ipv4', 'prefix_length', 'base_uri'}, 'network_recovered');
    final reason = _requiredString(json, 'recovery_reason');
    if (!const {'previous_sta_connect_failed', 'last_good_sta_connect_failed'}.contains(reason)) {
      throw ProvisioningProtocolException('recovery_reason', 'unsupported value "$reason"');
    }
    return NetworkRecovered(
      operationId: _operationId(json),
      activeMode: ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'active_mode')),
      operationState: NetworkOperationStateWireValue.parse(_requiredString(json, 'operation_state')),
      recoveredMode: ProvisioningNetworkModeWireValue.parse(_requiredString(json, 'recovered_mode')),
      recoveryReason: reason,
      ssid: _optionalString(json, 'ssid'),
      security: _optionalEnum(json, 'security', WifiSecurityWireValue.parse),
      passphrase: _optionalString(json, 'passphrase'),
      gatewayIpv4: _optionalString(json, 'gateway_ipv4'),
      prefixLength: _optionalNonNegativeInt(json, 'prefix_length'),
      baseUri: _optionalUri(json, 'base_uri'),
    );
  }

  @override
  String toString() => 'NetworkRecovered(operationId: $operationId, recoveredMode: ${recoveredMode.wireValue}, passphrase: ${passphrase == null ? 'absent' : '<redacted>'}, baseUri: $baseUri)';
}

final class CancelledOperation {
  const CancelledOperation({required this.operationId});
  final String operationId;

  factory CancelledOperation.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'operation_id'}, 'cancelled');
    return CancelledOperation(operationId: _operationId(json));
  }
}

final class ProvisioningEvent {
  const ProvisioningEvent({required this.type, required this.requestId, required this.deviceId, required this.payload});
  final ProvisioningEventType type;
  final String requestId;
  final String deviceId;
  final Object payload;

  String? get operationId => switch (payload) {
    CommandAccepted value => value.operationId,
    DirectApReady value => value.operationId,
    DirectApStopped value => value.operationId,
    StaConnected value => value.operationId,
    DppBootstrapReady value => value.operationId,
    NetworkProgress value => value.operationId,
    NetworkRecovered value => value.operationId,
    CancelledOperation value => value.operationId,
    ProvisioningNetworkStatus value => value.operationId,
    _ => null,
  };

  bool get terminal => switch (type) {
    ProvisioningEventType.directApReady || ProvisioningEventType.directApStopped || ProvisioningEventType.staConnected || ProvisioningEventType.networkRecovered || ProvisioningEventType.cancelled => true,
    _ => false,
  };

  bool get cancellable => switch (payload) {
    NetworkProgress value => value.operationState.cancellable,
    ProvisioningNetworkStatus value => value.operationState.cancellable,
    DppBootstrapReady _ => true,
    _ => false,
  };

  factory ProvisioningEvent.fromJson(Map<String, dynamic> json) {
    _rejectUnknownKeys(json, const {'protocol_version', 'type', 'request_id', 'device_id', 'ok', 'payload'}, 'event_envelope');
    final version = _requiredString(json, 'protocol_version');
    if (version != BleProtocolConstants.protocolVersion) throw ProvisioningProtocolException('protocol_version', 'expected ${BleProtocolConstants.protocolVersion}, got $version');
    if (!_requiredBool(json, 'ok')) throw const ProvisioningProtocolException('ok', 'event success envelope must be true');
    final type = ProvisioningEventTypeWireValue.parse(_requiredString(json, 'type'));
    final payloadJson = _requiredMap(json, 'payload');
    final payload = switch (type) {
      ProvisioningEventType.pairingOpened => PairingWindow.fromJson(payloadJson),
      ProvisioningEventType.pairingAuthorized => PairingAuthorization.fromJson(payloadJson),
      ProvisioningEventType.commandAccepted => CommandAccepted.fromJson(payloadJson),
      ProvisioningEventType.networkStatus => ProvisioningNetworkStatus.fromJson(payloadJson),
      ProvisioningEventType.wifiScanResults => WifiScanBatch.fromJson(payloadJson),
      ProvisioningEventType.directApReady => DirectApReady.fromJson(payloadJson),
      ProvisioningEventType.directApStopped => DirectApStopped.fromJson(payloadJson),
      ProvisioningEventType.staConnected => StaConnected.fromJson(payloadJson),
      ProvisioningEventType.dppBootstrapReady => DppBootstrapReady.fromJson(payloadJson),
      ProvisioningEventType.networkProgress => NetworkProgress.fromJson(payloadJson),
      ProvisioningEventType.networkRecovered => NetworkRecovered.fromJson(payloadJson),
      ProvisioningEventType.cancelled => CancelledOperation.fromJson(payloadJson),
    };
    final deviceId = _requiredString(json, 'device_id');
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId)) throw const ProvisioningProtocolException('device_id', 'invalid format');
    return ProvisioningEvent(type: type, requestId: _requiredString(json, 'request_id'), deviceId: deviceId, payload: payload);
  }
}

final class StaNetworkConfiguration {
  const StaNetworkConfiguration._({required this.provisioningMethod, required this.selectionMethod, required this.ssid, this.bssid, required this.security, this.password, required this.hidden, required this.networkKind});

  final ProvisioningMethod provisioningMethod;
  final WifiSelectionMethod selectionMethod;
  final String ssid;
  final String? bssid;
  final WifiSecurity security;
  final String? password;
  final bool hidden;
  final StaNetworkKind networkKind;

  factory StaNetworkConfiguration({
    required ProvisioningMethod provisioningMethod,
    required WifiSelectionMethod selectionMethod,
    required String ssid,
    String? bssid,
    required WifiSecurity security,
    String? password,
    required bool hidden,
    required StaNetworkKind networkKind,
  }) {
    if (provisioningMethod == ProvisioningMethod.androidDpp) throw ArgumentError('DPP must use startDppProvisioning, not setStaConfig');
    if (ssid.trim().isEmpty) throw ArgumentError('ssid must not be empty');
    if (selectionMethod == WifiSelectionMethod.manual && bssid != null) throw ArgumentError('manual selection requires bssid=null');
    if (security != WifiSecurity.open && (password == null || password.isEmpty)) throw ArgumentError('secured Wi-Fi requires a password');
    return StaNetworkConfiguration._(provisioningMethod: provisioningMethod, selectionMethod: selectionMethod, ssid: ssid, bssid: bssid, security: security, password: password, hidden: hidden, networkKind: networkKind);
  }

  Map<String, dynamic> toProtocolJson() => {
    'target_mode': ProvisioningNetworkMode.infrastructureSta.wireValue,
    'provisioning_method': provisioningMethod.wireValue,
    'selection_method': selectionMethod.wireValue,
    'ssid': ssid,
    'bssid': bssid,
    'security': security.wireValue,
    'password': password,
    'hidden': hidden,
    'network_kind': networkKind.wireValue,
  };

  @override
  String toString() =>
      'StaNetworkConfiguration(provisioningMethod: ${provisioningMethod.wireValue}, selectionMethod: ${selectionMethod.wireValue}, ssid: $ssid, bssid: $bssid, security: ${security.wireValue}, password: ${password == null ? 'absent' : '<redacted>'}, hidden: $hidden, networkKind: ${networkKind.wireValue})';
}

final class BleCommandRequest {
  const BleCommandRequest({required this.type, required this.requestId, required this.clientId, this.payload = const {}});
  final BleCommandType type;
  final String requestId;
  final String clientId;
  final Map<String, dynamic> payload;

  bool get writesWifiCredentials => type == BleCommandType.setStaConfig;
  bool get isAsynchronous => switch (type) {
    BleCommandType.startDirectAp || BleCommandType.stopDirectAp || BleCommandType.scanWifi || BleCommandType.setStaConfig || BleCommandType.startDppProvisioning || BleCommandType.cancelNetworkOperation => true,
    _ => false,
  };

  @override
  String toString() => 'BleCommandRequest(type: ${type.wireValue}, requestId: $requestId, clientId: $clientId, payload: <redacted>)';
}

void _rejectUnknownKeys(Map<String, dynamic> json, Set<String> allowed, String context) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) throw ProvisioningProtocolException(context, 'unknown fields: ${unknown.join(', ')}');
}

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is! Map) throw ProvisioningProtocolException(field, 'must be an object');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) => _asMap(json[key], key);

Map<String, dynamic>? _optionalMap(Map<String, dynamic> json, String key) => json[key] == null ? null : _asMap(json[key], key);

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw ProvisioningProtocolException(key, 'must be a non-empty string');
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) throw ProvisioningProtocolException(key, 'must be null or a non-empty string');
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw ProvisioningProtocolException(key, 'must be a boolean');
  return value;
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw ProvisioningProtocolException(key, 'must be null or a boolean');
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw ProvisioningProtocolException(key, 'must be an integer');
  return value;
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  final value = _requiredInt(json, key);
  if (value < 0) throw ProvisioningProtocolException(key, 'must be non-negative');
  return value;
}

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final value = _requiredInt(json, key);
  if (value <= 0) throw ProvisioningProtocolException(key, 'must be positive');
  return value;
}

int? _optionalNonNegativeInt(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _requiredNonNegativeInt(json, key);
}

List<String> _requiredStringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) throw ProvisioningProtocolException(key, 'must be an array of strings');
  return value.cast<String>();
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw ProvisioningProtocolException(key, 'must be an ISO-8601 date-time');
  return parsed;
}

Uri _requiredUri(Map<String, dynamic> json, String key) {
  final raw = _requiredString(json, key);
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) throw ProvisioningProtocolException(key, 'must be an absolute URI');
  return uri;
}

Uri? _optionalUri(Map<String, dynamic> json, String key) => json[key] == null ? null : _requiredUri(json, key);

T? _optionalEnum<T>(Map<String, dynamic> json, String key, T Function(String) parse) {
  final raw = json[key];
  if (raw == null) return null;
  if (raw is! String) throw ProvisioningProtocolException(key, 'must be null or a string');
  return parse(raw);
}

String _operationId(Map<String, dynamic> json) {
  final value = _requiredString(json, 'operation_id');
  if (!value.startsWith('op_') || value.length <= 3) throw const ProvisioningProtocolException('operation_id', 'must start with op_');
  return value;
}
