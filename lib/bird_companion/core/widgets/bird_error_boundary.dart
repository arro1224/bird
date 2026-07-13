import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class BirdErrorBoundary {
  static void install() {
    ErrorWidget.builder = (details) => Material(
      color: const Color(0xfff5fbf5),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 52, color: Color(0xff9b2c2c)),
                const SizedBox(height: 16),
                const Text('页面暂时无法显示', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('请返回上一页重试；若问题持续，请在“诊断与日志”中导出日志。', textAlign: TextAlign.center),
                if (kDebugMode) ...[const SizedBox(height: 12), Text(details.exceptionAsString(), maxLines: 5, overflow: TextOverflow.ellipsis)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
