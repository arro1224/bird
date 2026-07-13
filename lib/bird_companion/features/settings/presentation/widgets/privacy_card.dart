import 'package:flutter/material.dart';

class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key});
  @override
  Widget build(BuildContext context) => const Card(
    child: ListTile(leading: Icon(Icons.privacy_tip_outlined), title: Text('隐私与本地数据'), subtitle: Text('默认仅在手机与拍鸟盒子的局域网内通信，不上传原始照片。清理缩略图不会删除待同步的人工修改。')),
  );
}
