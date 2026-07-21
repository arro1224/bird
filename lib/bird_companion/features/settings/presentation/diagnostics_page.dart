import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
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
        DiagnosticResult(label: '盒子连接', passed: session.isConnected, detail: session.isConnected ? '已连接' : '尚未连接设备'),
        const DiagnosticResult(label: '状态更新', passed: false, detail: '正在检查盒子的状态更新…'),
        DiagnosticResult(label: '尚未传回盒子的修改', passed: true, detail: '${dependencies.pendingOperationStore.readAll().length} 项'),
      ];
    });
    final eventState = dependencies.eventClient.currentState;
    try {
      final status = await dependencies.deviceRepository.fetchStatus().timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() {
        _checkingApi = false;
        _results = [
          _results[0],
          DiagnosticResult(label: '状态更新', passed: eventState == EventConnectionState.connected, detail: eventState == EventConnectionState.connected ? '盒子状态可以自动更新' : '盒子状态需要手动刷新'),
          _results[2],
          DiagnosticResult(label: '盒子软件', passed: true, detail: '盒子软件 ${status.softwareVersion ?? '未知'} · 兼容信息 ${status.connection.apiVersion ?? 'v1'}'),
        ];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingApi = false;
        _results = [
          _results[0],
          DiagnosticResult(label: '状态更新', passed: eventState == EventConnectionState.connected, detail: eventState == EventConnectionState.connected ? '盒子状态可以自动更新' : '盒子状态需要手动刷新'),
          _results[2],
          const DiagnosticResult(label: '盒子软件', passed: false, detail: '暂时无法读取盒子信息，请重新连接后再试'),
        ];
      });
    }
  }

  Future<void> _retryPending() async {
    final dependencies = BirdCompanionScope.of(context);
    setState(() => _checkingApi = true);
    final result = await dependencies.birdSyncService.synchronize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已更新 ${result.syncedCount} 项，${result.failedOperations.length} 项仍需处理')),
    );
    await _run();
  }

  String _operationLabel(PendingOperation operation) => switch (operation.type) {
    PendingOperationType.updateReview => '单张人工复核',
    PendingOperationType.batchReview => '批量审阅/标签',
    PendingOperationType.controlJob => '任务控制',
    PendingOperationType.createCopyJob => '创建复制任务',
  };

  @override
  Widget build(BuildContext context) {
    final pending = BirdCompanionScope.of(context).pendingOperationStore.readAll();
    return Scaffold(
      backgroundColor: AppColors.brand,
      appBar: AppBar(
        leading: const BirdPageBackButton(),
        title: const Text('连接检查'),
        actions: [IconButton(onPressed: _checkingApi ? null : _run, icon: const Icon(Icons.refresh))],
      ),
      body: BirdDarkTheme(
        child: _results.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const BirdConnectionLine(),
                  const SizedBox(height: 28),
                  Text('连接检查', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('检查手机与盒子的连接，以及尚未传回盒子的修改', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  if (pending.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        leading: const Icon(Icons.sync_problem_outlined, color: AppColors.warning),
                        title: Text('尚未传回盒子的修改 ${pending.length} 项'),
                        subtitle: const Text('可以查看原因并重新尝试'),
                        children: [
                          for (final operation in pending)
                            ListTile(
                              dense: true,
                              title: Text(_operationLabel(operation)),
                              subtitle: Text(
                                operation.failureReason == null ? '${operation.status.name} · ${operation.createdAt.toLocal()}' : '已重试 ${operation.retryCount} 次：${operation.failureReason}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _checkingApi ? null : _retryPending,
                                icon: const Icon(Icons.sync),
                                label: const Text('立即重试全部'),
                              ),
                            ),
                          ),
                        ],
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
                    label: const Text('导出问题报告'),
                  ),
                ],
              ),
      ),
    );
  }
}
