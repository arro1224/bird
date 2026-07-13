import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:flutter/material.dart';

class DeviceErrorDetailPage extends StatelessWidget {
  const DeviceErrorDetailPage({super.key, required this.status});
  final DeviceStatus status;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备异常详情')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(title: const Text('错误码'), subtitle: Text(status.errorCode ?? '未提供')),
        ListTile(title: const Text('错误说明'), subtitle: Text(status.errorMessage ?? '设备当前没有可读的错误说明。')),
        const ListTile(title: Text('建议操作'), subtitle: Text('检查存储卡、电量、温度和与盒子的连接；问题持续时导出诊断日志。')),
      ],
    ),
  );
}
