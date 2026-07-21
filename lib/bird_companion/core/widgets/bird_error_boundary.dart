import 'package:flutter/material.dart';

abstract final class BirdErrorBoundary {
  static void install() {
    ErrorWidget.builder = (details) => const Material(
      color: Color(0xfff5fbf5),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 52, color: Color(0xff9b2c2c)),
                SizedBox(height: 16),
                Text('页面暂时无法显示', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('请返回上一页重试；如果问题一直存在，请在“检查连接问题”中导出问题报告。', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
