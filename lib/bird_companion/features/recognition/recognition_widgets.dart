import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/recognition/recognition_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_mode_panel.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_form.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_section.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_start_panel.dart';
import 'package:flutter/material.dart';

class RecognitionOptions extends StatefulWidget {
  const RecognitionOptions({super.key, required this.repository, required this.onChanged, this.configurationReader, this.onReadyChanged, this.onConfigured});
  final RecognitionRepository repository;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final SmartFollowConfigurationReader? configurationReader;
  final ValueChanged<bool>? onReadyChanged;
  final ValueChanged<SmartFollowConfiguredIntent?>? onConfigured;
  @override
  State<RecognitionOptions> createState() => _RecognitionOptionsState();
}

class _RecognitionOptionsState extends State<RecognitionOptions> {
  bool available = false, enabled = false, loaded = false;
  Object? error;
  SmartFollowConfigurationReader? _reader;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant RecognitionOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository || oldWidget.configurationReader != widget.configurationReader) {
      available = false;
      enabled = false;
      loaded = false;
      error = null;
      _reader = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onChanged(null);
        widget.onConfigured?.call(null);
        widget.onReadyChanged?.call(true);
      });
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final caps = await widget.repository.capabilities();
      if (!mounted || generation != _generation) return;
      setState(() {
        available = SmartFollowCapabilities.fromJson(caps).canShowEntry;
        loaded = true;
      });
    } on ApiException catch (caught) {
      if (mounted && generation == _generation) {
        setState(() {
          loaded = true;
          if (caught.statusCode != 404) error = caught;
        });
      }
    } catch (caught) {
      if (mounted && generation == _generation) {
        setState(() {
          loaded = true;
          error = caught;
        });
      }
    }
  }

  SmartFollowConfigurationReader _configurationReader() {
    if (widget.configurationReader != null) return widget.configurationReader!;
    final dependencies = BirdCompanionScope.maybeOf(context);
    if (dependencies != null) return smartFollowConfigurationReader(dependencies, null);
    // Compatibility for explicitly supplied standalone repositories (tests and
    // embeds). Parse through the same RC3 API, never a partial device Map.
    final api = CopyApi(widget.repository.api);
    final device = widget.repository.deviceId();
    final uri = widget.repository.api.baseUri;
    return SmartFollowConfigurationReader(
      contextKey: '$device|$uri',
      isCurrent: () => device != null && widget.repository.deviceId() == device && widget.repository.api.baseUri == uri,
      readSnapshot: () async {
        final capabilities = SmartFollowCapabilities.fromJson(await widget.repository.capabilities());
        final values = await Future.wait<Object>([api.devices(), api.source(), api.preferences(), api.capabilities()]);
        return SmartFollowConfigurationSnapshot(
          entry: SmartFollowEntryDecision(phase: RecognitionEntryPhase.notStarted, capabilities: capabilities),
          devices: (values[0] as CopyDeviceList).devices,
          binding: values[1] as SourceBinding,
          preferences: values[2] as CopyPreferences,
          copyCapabilities: values[3] as CopyCapabilities,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
    if (error != null) return Text(UserMessageMapper.fromCopyConfigurationError(error!).message);
    if (!available) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('smart-follow-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('识别并复制已识别照片'),
          subtitle: const Text('选择后先确认目标设备与复制策略，相机卡始终只读。'),
          value: enabled,
          onChanged: (value) {
            widget.onChanged(null);
            widget.onConfigured?.call(null);
            widget.onReadyChanged?.call(!value);
            setState(() {
              enabled = value;
              _reader = value ? _configurationReader() : null;
            });
          },
        ),
        if (enabled && _reader != null)
          SmartFollowConfigurationForm(
            reader: _reader!,
            onChanged: (intent) {
              widget.onChanged(enabled ? intent?.request.toJson() : null);
              widget.onConfigured?.call(enabled ? intent : null);
              widget.onReadyChanged?.call(!enabled || intent != null);
            },
          ),
      ],
    );
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}

class RecognitionChoice {
  const RecognitionChoice(this.config, {this.existingSessionId, this.existingRecognitionJobId});
  final Map<String, dynamic>? config;
  final String? existingSessionId;
  final String? existingRecognitionJobId;
}

Future<RecognitionChoice?> chooseRecognitionMode(
  BuildContext context,
  RecognitionRepository repo, {
  SmartFollowEntryReader? entryReader,
  SmartFollowConfigurationReader? configurationReader,
  SmartFollowCreationService? creationService,
}) async {
  if (entryReader != null) {
    final decision = await entryReader.read();
    if (!context.mounted) return null;
    var followSelected = false;
    final choice = await showDialog<RecognitionChoice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('识别与复制'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SmartFollowModePanel(
                    decision: decision,
                    recognitionEntry: true,
                    followSelected: followSelected,
                    onModeChanged: (follow) => setDialogState(() => followSelected = follow),
                    onOpenSession: (id) => Navigator.pop(context, RecognitionChoice(null, existingSessionId: id)),
                    onOpenRecognition: decision.job == null ? null : () => Navigator.pop(context, RecognitionChoice(null, existingRecognitionJobId: decision.job!.id)),
                    configuration: configurationReader == null
                        ? null
                        : creationService == null
                        ? SmartFollowConfigurationForm(reader: configurationReader, expectedRecognitionJobId: decision.job?.id, expectedRecognitionPhase: decision.phase)
                        : SmartFollowStartPanel(
                            reader: configurationReader,
                            service: creationService,
                            expectedJobId: decision.job?.id,
                            expectedPhase: decision.phase,
                            onCreated: (session) => Navigator.pop(context, RecognitionChoice(null, existingSessionId: session.sessionId, existingRecognitionJobId: session.recognitionJobId)),
                          ),
                  ),
                  if (creationService != null)
                    SmartFollowPendingCreation(
                      service: creationService,
                      batchId: entryReader.batchId,
                      isCurrent: entryReader.isCurrent,
                      onRecovered: (session) => Navigator.pop(context, RecognitionChoice(null, existingSessionId: session.sessionId, existingRecognitionJobId: session.recognitionJobId)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('返回')),
            FilledButton(
              key: const Key('recognition-mode-confirm'),
              onPressed: followSelected || decision.phase == RecognitionEntryPhase.unknown ? null : () => Navigator.pop(context, RecognitionChoice(null, existingRecognitionJobId: decision.job?.id)),
              child: Text(decision.job == null ? '仅开始识别' : '查看本轮识别'),
            ),
          ],
        ),
      ),
    );
    return entryReader.isCurrent() ? choice : null;
  }
  Map<String, dynamic> caps;
  try {
    caps = await repo.capabilities();
  } on ApiException catch (error) {
    if (error.statusCode == 404) return const RecognitionChoice(null);
    rethrow;
  }
  if (!context.mounted) return null;
  if (!SmartFollowCapabilities.fromJson(caps).canShowEntry) return const RecognitionChoice(null);
  Map<String, dynamic>? selected;
  var ready = true;
  return showDialog<RecognitionChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('开始识别'),
        content: SingleChildScrollView(
          child: RecognitionOptions(repository: repo, configurationReader: configurationReader, onChanged: (value) => selected = value, onReadyChanged: (value) => setDialogState(() => ready = value)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: ready ? () => Navigator.pop(context, RecognitionChoice(selected)) : null, child: const Text('开始识别')),
        ],
      ),
    ),
  );
}
