import 'package:flutter/material.dart';

class SyncStateIndicator extends StatelessWidget {
  const SyncStateIndicator({super.key, required this.synced});
  final bool synced;
  @override
  Widget build(BuildContext c) => Chip(label: Text(synced ? '已同步' : '待同步'), avatar: Icon(synced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined, size: 18));
}
