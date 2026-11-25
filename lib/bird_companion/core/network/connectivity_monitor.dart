import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityMonitor {
  ConnectivityMonitor({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get onNetworkChanged => _connectivity.onConnectivityChanged.map((types) => !types.contains(ConnectivityResult.none)).distinct();
  // Do not collapse Wi-Fi-to-Wi-Fi changes into the same `true` boolean.
  Stream<void> get onTransportChanged => _connectivity.onConnectivityChanged.map((_) {});

  Future<bool> get hasNetwork async => !(await _connectivity.checkConnectivity()).contains(ConnectivityResult.none);

  /// Client Wi-Fi is only a transport hint. A phone hosting a hotspot can
  /// reach its box while this is false; cellular availability proves neither.
  Future<bool> get hasWifi async => (await _connectivity.checkConnectivity()).contains(ConnectivityResult.wifi);
}

abstract interface class DiagnosticNetworkTypes {
  Future<List<String>> get networkTypes;
}

extension ConnectivityDiagnosticSnapshot on ConnectivityMonitor {
  Future<List<String>> get diagnosticNetworkTypes async {
    final monitor = this;
    if (monitor is DiagnosticNetworkTypes) return (monitor as DiagnosticNetworkTypes).networkTypes;
    return (await _connectivity.checkConnectivity()).map((type) => type.name).toList(growable: false);
  }
}
