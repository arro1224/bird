import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityMonitor {
  ConnectivityMonitor({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get onNetworkChanged => _connectivity.onConnectivityChanged.map((types) => !types.contains(ConnectivityResult.none)).distinct();

  Future<bool> get hasNetwork async => !(await _connectivity.checkConnectivity()).contains(ConnectivityResult.none);
}
