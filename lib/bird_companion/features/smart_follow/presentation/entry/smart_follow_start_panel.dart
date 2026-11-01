import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_form.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:flutter/material.dart';

class SmartFollowStartPanel extends StatefulWidget {
  const SmartFollowStartPanel({super.key, required this.reader, required this.service, required this.onCreated, this.expectedJobId, this.expectedPhase, this.onConfigurationChanged});
  final SmartFollowConfigurationReader reader;
  final SmartFollowCreationService service;
  final String? expectedJobId;
  final RecognitionEntryPhase? expectedPhase;
  final ValueChanged<SmartFollowSession> onCreated;
  final ValueChanged<SmartFollowConfiguredIntent?>? onConfigurationChanged;
  @override
  State<SmartFollowStartPanel> createState() => _SmartFollowStartPanelState();
}

class _SmartFollowStartPanelState extends State<SmartFollowStartPanel> with WidgetsBindingObserver {
  SmartFollowConfiguredIntent? _intent;
  bool _busy = false, _foreground = true;
  String? _error;
  int _formRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _foreground = state == AppLifecycleState.resumed;

  Future<void> _submit({bool queryOnly = false}) async {
    if (_busy || !widget.reader.isCurrent()) return;
    final reader = widget.reader, intent = _intent;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = queryOnly
          ? await widget.service.recover(reader.batchId!)
          : await widget.service.start(
              intent!,
              SmartFollowConfigurationReader(
                readSnapshot: reader.readSnapshot,
                contextKey: reader.contextKey,
                batchId: reader.batchId,
                isCurrent: () => mounted && _foreground && identical(_intent, intent) && identical(widget.reader, reader) && reader.isCurrent(),
              ),
            );
      if (mounted && _foreground && identical(widget.reader, reader) && reader.isCurrent()) widget.onCreated(session);
    } catch (error) {
      if (mounted) {
        if (error is SmartFollowConfirmationRequired) {
          _intent = null;
          ++_formRevision;
          widget.onConfigurationChanged?.call(null);
        }
        setState(
          () => _error = error is SmartFollowCreationPending
              ? error.toString()
              : error is SmartFollowConfirmationRequired
              ? error.message
              : UserMessageMapper.fromCopyConfigurationError(error).message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.reader.batchId != null && widget.service.hasPending(widget.reader.batchId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          ignoring: _busy,
          child: SmartFollowConfigurationForm(
            key: ValueKey(_formRevision),
            reader: widget.reader,
            expectedRecognitionJobId: widget.expectedJobId,
            expectedRecognitionPhase: widget.expectedPhase,
            onChanged: (intent) {
              setState(() => _intent = intent);
              widget.onConfigurationChanged?.call(intent);
            },
          ),
        ),
        if (pending) const Text('原创建请求结果待确认。查询不会创建任务；重试将保留原参数和同一个请求编号。'),
        if (_error != null) Text(_error!, key: const Key('smart-follow-create-error')),
        if (pending) OutlinedButton(key: const Key('smart-follow-recover-create'), onPressed: _busy || !widget.reader.isCurrent() ? null : () => _submit(queryOnly: true), child: const Text('查询原请求')),
        FilledButton(
          key: const Key('smart-follow-submit'),
          onPressed: _busy || _intent == null || !widget.reader.isCurrent() ? null : _submit,
          child: Text(
            _busy
                ? '正在确认创建结果…'
                : pending
                ? '用原请求重试'
                : widget.expectedJobId == null
                ? '开始识别并复制'
                : '开始边识别边复制',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Remains available even if recognition finished while its POST timed out.
class SmartFollowPendingCreation extends StatefulWidget {
  const SmartFollowPendingCreation({super.key, required this.service, required this.batchId, required this.onRecovered, required this.isCurrent});
  final SmartFollowCreationService service;
  final String batchId;
  final ValueChanged<SmartFollowSession> onRecovered;
  final bool Function() isCurrent;
  @override
  State<SmartFollowPendingCreation> createState() => _SmartFollowPendingCreationState();
}

class _SmartFollowPendingCreationState extends State<SmartFollowPendingCreation> {
  bool _busy = false;
  String? _message;
  @override
  Widget build(BuildContext context) {
    if (!widget.service.hasPending(widget.batchId)) return const SizedBox.shrink();
    return Column(
      children: [
        Text(_message ?? '有一次创建结果待确认，请先查询原请求。'),
        TextButton(
          key: const Key('smart-follow-pending-query'),
          onPressed: _busy || !widget.isCurrent()
              ? null
              : () async {
                  setState(() => _busy = true);
                  final contextKey = widget.service.contextKey(), service = widget.service, batch = widget.batchId;
                  try {
                    final session = await widget.service.recover(widget.batchId);
                    if (mounted && identical(service, widget.service) && batch == widget.batchId && contextKey == service.contextKey() && widget.isCurrent()) widget.onRecovered(session);
                  } catch (error) {
                    if (mounted) setState(() => _message = error is SmartFollowCreationPending ? error.toString() : '暂时无法确认原请求，请检查连接后再查询。');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(_busy ? '正在查询…' : '查询原请求'),
        ),
      ],
    );
  }
}
