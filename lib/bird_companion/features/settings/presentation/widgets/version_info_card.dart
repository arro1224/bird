import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class VersionInfoCard extends StatelessWidget {
  const VersionInfoCard({super.key, required this.session, required this.appVersion});
  final DeviceSessionState session;
  final String appVersion;
  @override
  Widget build(BuildContext c) => Card(
    child: ListTile(
      leading: const Icon(Icons.info_outline_rounded, color: AppColors.brand),
      title: const Text('版本信息'),
      subtitle: Text('App：$appVersion\n盒子 API：${session.device?.apiVersion ?? '未连接'}\n连接方式：${session.device?.networkMode.label ?? '未连接'}'),
    ),
  );
}
