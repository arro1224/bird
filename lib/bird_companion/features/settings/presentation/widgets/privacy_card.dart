import 'package:flutter/material.dart';

class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key});
  @override
  Widget build(BuildContext context) => const Card(
    child: ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('隐私与手机数据'), subtitle: Text('手机只会通过当前 Wi-Fi 与拍鸟盒子通信，不会上传原始照片。清理预览图不会删除你做过的修改。')),
  );
}
