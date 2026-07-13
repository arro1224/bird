import 'package:flutter/material.dart';

class BatchOperationResult extends StatelessWidget {
  const BatchOperationResult({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext c) => SnackBar(content: Text('已提交 $count 张照片的批量操作。'));
}
