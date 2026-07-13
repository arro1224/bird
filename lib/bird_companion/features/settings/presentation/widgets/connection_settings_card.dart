import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:flutter/material.dart';

class ConnectionSettingsCard extends StatelessWidget {
  const ConnectionSettingsCard({super.key, required this.session, required this.onReconnect, required this.onForget});
  final DeviceSessionState session;
  final VoidCallback onReconnect, onForget;
  @override
  Widget build(BuildContext context) {
    final device = session.device;
    return Card(
      child: Column(
        children: [
          ListTile(leading: Icon(session.isConnected ? Icons.wifi : Icons.wifi_off), title: Text(device?.name ?? '未连接拍鸟盒子'), subtitle: Text(device == null ? '请先在设备页连接盒子' : '${device.networkMode.label}\n${device.baseUri}')),
          OverflowBar(
            children: [
              TextButton(onPressed: onReconnect, child: const Text('重新连接')),
              TextButton(onPressed: device == null ? null : onForget, child: const Text('忘记设备')),
            ],
          ),
        ],
      ),
    );
  }
}
