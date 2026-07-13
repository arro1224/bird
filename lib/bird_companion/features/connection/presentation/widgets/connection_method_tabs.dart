import 'package:flutter/material.dart';

enum ConnectionMethod { nearby, hotspot, manual, scan }

class ConnectionMethodTabs extends StatelessWidget {
  const ConnectionMethodTabs({super.key, required this.value, required this.onChanged});

  final ConnectionMethod value;
  final ValueChanged<ConnectionMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ConnectionMethod>(
      segments: const [
        ButtonSegment(value: ConnectionMethod.nearby, icon: Icon(Icons.radar_outlined), label: Text('附近设备')),
        ButtonSegment(value: ConnectionMethod.hotspot, icon: Icon(Icons.wifi_outlined), label: Text('盒子热点')),
        ButtonSegment(value: ConnectionMethod.manual, icon: Icon(Icons.language_outlined), label: Text('手动地址')),
        ButtonSegment(value: ConnectionMethod.scan, icon: Icon(Icons.qr_code_scanner_outlined), label: Text('扫码')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selected) => onChanged(selected.first),
    );
  }
}
