import 'dart:async';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/continuous_queue_models.dart';
import 'package:flutter/material.dart';

class GroupedCopyHistoryPageView extends StatefulWidget {
  const GroupedCopyHistoryPageView({super.key, required this.repository, required this.onOpenCopy, required this.onOpenSession});
  final SmartFollowRepository repository;
  final ValueChanged<String> onOpenCopy, onOpenSession;
  @override
  State<GroupedCopyHistoryPageView> createState() => _GroupedCopyHistoryPageViewState();
}

class _GroupedCopyHistoryPageViewState extends State<GroupedCopyHistoryPageView> with WidgetsBindingObserver {
  final _items = <String, GroupedCopyHistoryItem>{};
  final _cursors = <String>{};
  late final int _device;
  int _generation = 0;
  String? _cursor;
  bool _busy = false, _hasMore = false;
  Object? _error;
  bool get _sameDevice => widget.repository.deviceGeneration == _device;

  @override
  void initState() {
    super.initState();
    _device = widget.repository.deviceGeneration;
    widget.repository.addListener(_deviceChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load(reset: true));
  }

  void _deviceChanged() {
    if (!mounted || _sameDevice) return;
    ++_generation;
    setState(() {
      _items.clear(); _hasMore = false; _busy = false;
      _error = StateError('盒子连接已变化，请重新打开复制任务列表。');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (!_sameDevice || (!reset && (_busy || !_hasMore))) return;
    final generation = ++_generation;
    final cursor = reset ? null : _cursor;
    setState(() {
      _busy = true; _error = null;
      if (reset) { _items.clear(); _cursors.clear(); _cursor = null; _hasMore = false; }
    });
    try {
      final page = await widget.repository.groupedHistory(cursor: cursor);
      if (!mounted || generation != _generation || !_sameDevice) return;
      if (page.hasMore && (page.items.isEmpty || !_cursors.add(page.nextCursor!))) throw StateError('复制历史分页没有推进，请重新读取。');
      setState(() {
        for (final item in page.items) { _items[item.key] = item; }
        _cursor = page.nextCursor; _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation && _sameDevice) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('复制任务'), actions: [IconButton(tooltip: '刷新任务', onPressed: _sameDevice ? () => _load(reset: true) : null, icon: const Icon(Icons.refresh))]),
    body: RefreshIndicator(onRefresh: () => _load(reset: true), child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        const Text('每次智能复制显示为一个主任务，普通复制单独保留。'),
        if (_error != null) ...[
          Text(UserMessageMapper.fromError(_error!).message),
          TextButton(onPressed: _sameDevice ? () => _load(reset: _items.isEmpty) : null, child: const Text('重新读取任务')),
        ],
        if (!_busy && _error == null && _items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('还没有复制任务。')),
        for (final item in _items.values) Card(child: ListTile(
          key: ValueKey(item.key),
          leading: Icon(item.session == null ? Icons.content_copy_outlined : Icons.auto_awesome_outlined),
          title: Text(item.session == null ? '普通复制' : '边识别边复制'),
          subtitle: Text(item.session == null
            ? '${item.copy!.state.label}\n任务 ${item.copy!.copyJobId}'
            : '${item.session!.state.label}\n任务 ${item.session!.sessionId}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: !_sameDevice ? null : () => item.session == null ? widget.onOpenCopy(item.copy!.copyJobId) : widget.onOpenSession(item.session!.sessionId),
        )),
        if (_busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (_hasMore) OutlinedButton(onPressed: _busy ? null : () => _load(reset: false), child: const Text('加载更多任务')),
      ],
    )),
  );

  @override
  void dispose() {
    ++_generation;
    widget.repository.removeListener(_deviceChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
