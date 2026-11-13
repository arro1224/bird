import 'dart:async';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/continuous_queue_models.dart';
import 'package:flutter/material.dart';

/// File states are live, not a frozen selection of files to retry. Actions stay
/// on the authoritative parent, and returning here starts a fresh first page.
class SmartFollowFilesPage extends StatefulWidget {
  const SmartFollowFilesPage({super.key, required this.repository, required this.sessionId});
  final SmartFollowRepository repository;
  final String sessionId;
  @override
  State<SmartFollowFilesPage> createState() => _SmartFollowFilesPageState();
}

class _SmartFollowFilesPageState extends State<SmartFollowFilesPage> with WidgetsBindingObserver {
  final _items = <String, SmartFollowFileItem>{};
  final _cursors = <String>{};
  String? _filter, _next;
  bool _busy = false, _hasMore = false;
  Object? _error;
  int _generation = 0;
  late final int _device;
  bool get _sameDevice => widget.repository.deviceGeneration == _device;

  @override
  void initState() {
    super.initState();
    _device = widget.repository.deviceGeneration;
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(_changed);
    unawaited(_load(reset: true));
  }

  void _changed() {
    if (!_sameDevice && mounted) {
      ++_generation;
      setState(() {
        _items.clear();
        _busy = false;
        _hasMore = false;
        _error = StateError('盒子连接已变化，请返回原任务。');
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sameDevice) unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (!_sameDevice || (!reset && (_busy || !_hasMore))) return;
    final generation = ++_generation;
    final cursor = reset ? null : _next;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursors.clear();
        _next = null;
        _hasMore = false;
      }
    });
    try {
      final page = await widget.repository.fileItems(widget.sessionId, cursor: cursor, state: _filter);
      if (!mounted || generation != _generation || !_sameDevice) return;
      if (page.hasMore && (page.items.isEmpty || !_cursors.add(page.nextCursor!))) throw StateError('文件明细分页未推进，请刷新列表。');
      setState(() {
        for (final item in page.items) { _items[item.itemId] = item; }
        _next = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation && _sameDevice) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('复制文件明细'), actions: [
      IconButton(onPressed: _sameDevice ? () => _load(reset: true) : null, icon: const Icon(Icons.refresh), tooltip: '重新读取文件状态'),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('文件状态会随任务变化。重试请返回主任务操作，不会重新复制成功文件。'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _filter ?? 'all',
        decoration: const InputDecoration(labelText: '筛选文件状态'),
        items: [
          const DropdownMenuItem(value: 'all', child: Text('全部文件')),
          for (final entry in SmartFollowFileItem.stateLabels.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: !_sameDevice ? null : (value) {
          _filter = value == 'all' ? null : value;
          unawaited(_load(reset: true));
        },
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(UserMessageMapper.fromError(_error!).message),
        TextButton(onPressed: _sameDevice ? () => _load(reset: _items.isEmpty) : null, child: const Text('重新读取')),
      ],
      if (!_busy && _error == null && _items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('当前没有符合筛选条件的文件。')),
      for (final item in _items.values) Card(child: ListTile(
        title: Text(item.name),
        subtitle: Text([
          item.stateLabel, '尝试 ${item.attemptCount} 次',
          if (item.errorMessage?.isNotEmpty == true) item.errorMessage!,
          if (item.errorCode?.isNotEmpty == true) '错误码：${item.errorCode}',
          if (item.targetRelativePath?.isNotEmpty == true) item.targetRelativePath!,
        ].join('\n')),
        leading: Icon(switch (item.state) {
          'copied' => Icons.check_circle_outline,
          'failed' || 'blocked' => Icons.error_outline,
          _ => Icons.schedule,
        }),
      )),
      if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      if (_hasMore) OutlinedButton(onPressed: _busy ? null : () => _load(reset: false), child: const Text('加载更多文件')),
    ]),
  );

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.removeListener(_changed);
    super.dispose();
  }
}
