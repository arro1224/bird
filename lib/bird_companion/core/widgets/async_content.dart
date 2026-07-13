import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:flutter/material.dart';

class AsyncContent<T> extends StatelessWidget {
  const AsyncContent({
    super.key,
    required this.snapshot,
    required this.dataBuilder,
    this.emptyTitle = '暂无内容',
    this.emptyMessage = '当前没有可展示的数据。',
    this.onRetry,
  });

  final AsyncSnapshot<T> snapshot;
  final Widget Function(BuildContext context, T data) dataBuilder;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(
        child: ErrorNotice(
          title: '加载失败',
          message: '暂时无法获取数据，请检查与盒子的连接后重试。',
          onRetry: onRetry,
        ),
      );
    }
    final data = snapshot.data;
    if (data == null) {
      return Center(
        child: EmptyState(title: emptyTitle, message: emptyMessage),
      );
    }
    return dataBuilder(context, data);
  }
}
