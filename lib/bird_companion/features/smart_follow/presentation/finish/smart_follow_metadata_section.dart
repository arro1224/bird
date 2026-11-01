import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_controller.dart';

/// Shared by the run and completion routes. Events wake reads, never writes.
class SmartFollowMetadataSection extends StatefulWidget {
  const SmartFollowMetadataSection({super.key, required this.repository, required this.sessionId, required this.readRecognition, required this.onOpenPreview, required this.onOpenUpdate, required this.isCurrent, this.refreshSignals});
  final SmartFollowRepository repository;
  final String sessionId;
  final Future<BirdJobStatus> Function(String) readRecognition;
  final VoidCallback onOpenPreview;
  final void Function(String) onOpenUpdate;
  final bool Function() isCurrent;
  final Stream<void>? refreshSignals;
  @override
  State<SmartFollowMetadataSection> createState() => _SmartFollowMetadataSectionState();
}

class _SmartFollowMetadataSectionState extends State<SmartFollowMetadataSection> with WidgetsBindingObserver {
  late final SmartFollowMetadataController _controller;
  StreamSubscription<void>? _signals;
  Timer? _timer;
  bool _foreground = true, _visible = true;
  String? _observed;
  @override
  void initState() {
    super.initState();
    _controller = SmartFollowMetadataController(repository: widget.repository, sessionId: widget.sessionId, readRecognition: widget.readRecognition, isCurrent: widget.isCurrent)..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(_sessionChanged);
    _signals = widget.refreshSignals?.listen((_) {
      if (mounted) setState(() {});
      if (_foreground && _visible) unawaited(_controller.refresh());
    });
    unawaited(_controller.refresh());
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_foreground && _visible && !_controller.busy) unawaited(_controller.refresh());
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    final value = widget.repository.snapshot(widget.sessionId);
    final key = '${value?.stateVersion}|${value?.metadataUpdateAvailable}|${value?.activeMetadataUpdateId}';
    if (_observed == key) return;
    _observed = key;
    if (_foreground && _visible && !_controller.busy) unawaited(_controller.refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (visible && !_visible && _foreground) unawaited(_controller.refresh());
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _visible) unawaited(_controller.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.removeListener(_sessionChanged);
    unawaited(_signals?.cancel());
    _timer?.cancel();
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller;
    if (!state.current || (!state.busy && state.error == null && !state.enabled)) return const SizedBox.shrink();
    if (state.busy) return const Padding(padding: EdgeInsets.all(12), child: Text('正在核对识别信息更新状态…'));
    final active = state.activeUpdateId;
    final latest = state.latestUpdateId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('识别信息更新', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (state.error != null)
              Text(state.error!)
            else if (active != null)
              const Text('已有信息更新任务，请查看原任务。')
            else if (state.outcomeUnknown)
              const Text('上次信息更新结果待确认，请查询原任务；不会重新创建。')
            else if (!state.recognitionFinished)
              const Text('识别仍在进行，新的信息还会继续产生。保存当前已有信息后，以后仍可能需要再次更新。')
            else if (state.availability?.available == true)
              const Text('识别已结束，已复制的副本有新的识别信息可更新。')
            else
              const Text('当前没有可统一更新的识别信息。'),
            if (latest != null && state.enabled && state.error == null)
              OutlinedButton(
                key: const Key('sf-metadata-open-update'),
                onPressed: () {
                  if (state.current) widget.onOpenUpdate(latest);
                },
                child: Text(active == null ? '查看上次信息更新报告' : '查看信息更新任务'),
              ),
            if (state.canPreview)
              if (state.recognitionFinished)
                FilledButton(key: const Key('sf-metadata-open-preview'), onPressed: widget.onOpenPreview, child: Text(state.actionLabel))
              else
                OutlinedButton(key: const Key('sf-metadata-open-preview'), onPressed: widget.onOpenPreview, child: Text(state.actionLabel)),
            if (state.error != null || state.outcomeUnknown) TextButton(key: const Key('sf-metadata-query'), onPressed: state.current ? state.refresh : null, child: Text(state.outcomeUnknown ? '查询原任务' : '重新核对')),
            const Text('先预览，再确认。只更新识别与审阅信息，不重新复制照片。'),
          ],
        ),
      ),
    );
  }
}
