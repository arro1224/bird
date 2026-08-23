import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

/// B owns parsing the standard Wi-Fi QR payload. This A-owned model is the
/// only value that crosses from the parser/UI into the provisioning domain.
final class WifiQrCredentials {
  const WifiQrCredentials({required this.ssid, required this.security, this.password, this.bssid, this.hidden = false, this.networkKind = StaNetworkKind.unknown});

  final String ssid;
  final WifiSecurity security;
  final String? password;
  final String? bssid;
  final bool hidden;
  final StaNetworkKind networkKind;

  StaNetworkConfiguration toStaNetworkConfiguration() => StaNetworkConfiguration(
    provisioningMethod: ProvisioningMethod.wifiQr,
    selectionMethod: bssid == null ? WifiSelectionMethod.manual : WifiSelectionMethod.scanResult,
    ssid: ssid,
    bssid: bssid,
    security: security,
    password: password,
    hidden: hidden,
    networkKind: networkKind,
  );

  @override
  String toString() => 'WifiQrCredentials(ssid: $ssid, security: ${security.wireValue}, password: ${password == null ? 'absent' : '<redacted>'}, bssid: $bssid, hidden: $hidden, networkKind: ${networkKind.wireValue})';
}
