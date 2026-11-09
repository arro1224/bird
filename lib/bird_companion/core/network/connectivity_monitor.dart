import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityMonitor {
  ConnectivityMonitor({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get onNetworkChanged => _connectivity.onConnectivityChanged.map((types) => !types.contains(ConnectivityResult.none)).distinct();
  // Do not collapse Wi-Fi-to-Wi-Fi changes into the same `true` boolean.
  Stream<void> get onTransportChanged => _connectivity.onConnectivityChanged.map((_) {});

  Future<bool> get hasNetwork async => !(await _connectivity.checkConnectivity()).contains(ConnectivityResult.none);

  /// 盒子只能经 Wi-Fi 访问；移动数据可用不代表盒子可达（v10 问题 8）。
  Future<bool> get hasWifi async => (await _connectivity.checkConnectivity()).contains(ConnectivityResult.wifi);
}
