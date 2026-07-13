import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/features/settings/domain/diagnostic_result.dart';
import 'package:flutter/material.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  List<DiagnosticResult> _results = const [];
  var _checkingApi = false;
  var _dependenciesReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dependenciesReady) {
      _dependenciesReady = true;
      _run();
    }
  }

  Future<void> _run() async {
    final dependencies = BirdCompanionScope.of(context);
    final session = dependencies.deviceSessionCubit.state;
    setState(() {
      _checkingApi = true;
      _results = [
        DiagnosticResult(label: '连接会话', passed: session.isConnected, detail: session.device?.baseUri.toString() ?? '尚未连接设备'),
        const DiagnosticResult(label: '事件通道', passed: false, detail: '正在检查实时事件连接…'),
        DiagnosticResult(label: '本地待同步操作', passed: true, detail: '${dependencies.pendingOperationStore.readAll().length} 项'),
      ];
    });
    final eventState = await dependencies.eventClient.connectionStates.first.timeout(const Duration(milliseconds: 250), onTimeout: () => EventConnectionState.disconnected);
    try {
      final status = await dependencies.deviceRepository.fetchStatus().timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() {
        _checkingApi = false;
        _results = [
          _results[0],
          DiagnosticResult(label: '事件通道', passed: eventState == EventConnectionState.connected, detail: eventState == EventConnectionState.connected ? '实时事件已连接' : '当前使用 HTTP 刷新，实时事件不可用'),
          _results[2],
          DiagnosticResult(label: '设备 API', passed: true, detail: '盒子 ${status.softwareVersion ?? '未知'} · API ${status.connection.apiVersion ?? 'v1'} · 模型 ${status.modelVersion ?? '未知'}'),
        ];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingApi = false;
        _results = [
          _results[0],
          DiagnosticResult(label: '事件通道', passed: eventState == EventConnectionState.connected, detail: eventState == EventConnectionState.connected ? '实时事件已连接' : '当前使用 HTTP 刷新，实时事件不可用'),
          _results[2],
          DiagnosticResult(label: '设备 API', passed: false, detail: error.toString()),
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const BirdPageBackButton(),
      title: const Text('设置诊断'),
      actions: [IconButton(onPressed: _checkingApi ? null : _run, icon: const Icon(Icons.refresh))],
    ),
    body: _results.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const BirdConnectionLine(),
              const SizedBox(height: 28),
              Text('设置诊断', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('检查本地连接、盒子服务与待同步操作', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              for (final result in _results)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: DecoratedBox(
                      decoration: ShapeDecoration(color: result.passed ? AppColors.brandLight : AppColors.amberLight, shape: const CircleBorder()),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Icon(result.passed ? Icons.check_rounded : Icons.priority_high_rounded, color: result.passed ? AppColors.brand : AppColors.warning),
                      ),
                    ),
                    title: Text(result.label),
                    subtitle: Text(result.detail),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final dependencies = BirdCompanionScope.of(context);
                  try {
                    final url = await dependencies.jobRepository.exportLogs();
                    if (url == null) throw StateError('日志正在生成，请稍后重试。');
                    final log = await dependencies.logDownloadService.download(url);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日志已下载到：${log.file.path}')));
                  } catch (error) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('日志导出失败：$error')));
                  }
                },
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('导出诊断日志'),
              ),
            ],
          ),
  );
}
