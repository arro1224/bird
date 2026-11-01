import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_form.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_mode_panel.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_start_panel.dart';
import 'package:flutter/material.dart';

SmartFollowEntryReader smartFollowEntryReader(BirdCompanionDependencies dependencies, String batchId, {String? recognitionJobId}) {
  final generation = dependencies.smartFollowRepository.deviceGeneration;
  final deviceId = dependencies.deviceSessionCubit.state.device?.id;
  final baseUri = dependencies.apiClient.baseUri;
  return SmartFollowEntryReader(
    batchId: batchId,
    recognitionJobId: recognitionJobId,
    readPage: (cursor) => dependencies.jobRepository.page(cursor: cursor, type: 'analysis'),
    readCapabilities: () => dependencies.smartFollowRepository.capabilities(forceRefresh: true),
    readSession: dependencies.smartFollowRepository.refreshForJob,
    isCurrent: () =>
        generation == dependencies.smartFollowRepository.deviceGeneration &&
        deviceId != null &&
        dependencies.deviceSessionCubit.state.isConnected &&
        dependencies.deviceSessionCubit.state.device?.id == deviceId &&
        dependencies.apiClient.baseUri == baseUri,
  );
}

SmartFollowConfigurationReader smartFollowConfigurationReader(BirdCompanionDependencies dependencies, String? batchId, {String? recognitionJobId}) {
  final generation = dependencies.smartFollowRepository.deviceGeneration;
  final deviceId = dependencies.deviceSessionCubit.state.device?.id;
  final baseUri = dependencies.apiClient.baseUri;
  return SmartFollowConfigurationReader(
    contextKey: '$deviceId|$baseUri|$generation',
    batchId: batchId,
    isCurrent: () =>
        generation == dependencies.smartFollowRepository.deviceGeneration &&
        deviceId != null &&
        dependencies.deviceSessionCubit.state.isConnected &&
        dependencies.deviceSessionCubit.state.device?.id == deviceId &&
        dependencies.apiClient.baseUri == baseUri,
    changes: Stream<void>.multi((signals) {
      final subscriptions = [
        dependencies.deviceSessionCubit.stream.listen((_) => signals.add(null)),
        dependencies.refreshCoordinator.changes.listen((_) => signals.add(null)),
        dependencies.dataChangeBus.changes.where((change) => change.affects(AppDataResource.device) || change.affects(AppDataResource.copyPreferences)).listen((_) => signals.add(null)),
      ];
      signals.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    }),
    readSnapshot: () async {
      final entry = batchId == null
          ? SmartFollowEntryDecision(phase: RecognitionEntryPhase.notStarted, capabilities: await dependencies.smartFollowRepository.capabilities(forceRefresh: true))
          : await smartFollowEntryReader(dependencies, batchId, recognitionJobId: recognitionJobId).read();
      final values = await Future.wait<Object>([
        dependencies.copyRepository.devices(),
        dependencies.copyRepository.source(batchId: batchId),
        dependencies.copyRepository.preferences(),
        dependencies.copyRepository.capabilities(),
      ]);
      return SmartFollowConfigurationSnapshot(entry: entry, devices: (values[0] as CopyDeviceList).devices, binding: values[1] as SourceBinding, preferences: values[2] as CopyPreferences, copyCapabilities: values[3] as CopyCapabilities);
    },
  );
}

class SmartFollowEntrySection extends StatefulWidget {
  const SmartFollowEntrySection({
    super.key,
    required this.batchId,
    required this.onModeChanged,
    this.recognitionJobId,
    this.onOpenRecognition,
    this.reader,
    this.sessionChanges,
    this.onOpenSession,
    this.onSnapshot,
    this.configurationReader,
    this.onConfigurationChanged,
    this.creationService,
  });

  final String batchId;
  final String? recognitionJobId;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOpenRecognition;
  final SmartFollowEntryReader? reader;
  final Stream<void>? sessionChanges;
  final ValueChanged<String>? onOpenSession;
  final VoidCallback? onSnapshot;
  final SmartFollowConfigurationReader? configurationReader;
  final ValueChanged<SmartFollowConfiguredIntent?>? onConfigurationChanged;
  final SmartFollowCreationService? creationService;

  @override
  State<SmartFollowEntrySection> createState() => _SmartFollowEntrySectionState();
}

class _SmartFollowEntrySectionState extends State<SmartFollowEntrySection> {
  SmartFollowEntryDecision? _decision;
  StreamSubscription<void>? _subscription;
  BirdCompanionDependencies? _dependencies;
  int _generation = 0;
  bool _followSelected = false;
  SmartFollowConfigurationReader? _configurationReader;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = widget.reader == null ? BirdCompanionScope.of(context) : null;
    if (_generation == 0 || !identical(_dependencies, dependencies)) {
      _dependencies = dependencies;
      _bind();
    }
  }

  @override
  void didUpdateWidget(covariant SmartFollowEntrySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batchId != widget.batchId ||
        oldWidget.recognitionJobId != widget.recognitionJobId ||
        oldWidget.reader != widget.reader ||
        oldWidget.sessionChanges != widget.sessionChanges ||
        oldWidget.configurationReader != widget.configurationReader) {
      _bind();
    }
  }

  void _bind() {
    unawaited(_subscription?.cancel());
    _subscription = (widget.sessionChanges ?? _dependencies?.deviceSessionCubit.stream.map((_) {}))?.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _configurationReader = null;
    if (_followSelected) {
      _followSelected = false;
      // Do not mutate a parent that may currently be building this section.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_followSelected) widget.onModeChanged(false);
        if (mounted && !_followSelected) widget.onConfigurationChanged?.call(null);
      });
    }
    setState(() => _decision = null);
    final reader = widget.reader ?? smartFollowEntryReader(_dependencies!, widget.batchId, recognitionJobId: widget.recognitionJobId);
    final decision = await reader.read();
    if (mounted && generation == _generation) setState(() => _decision = decision);
  }

  void _select(bool follow) {
    if (follow == _followSelected) {
      if (!follow) widget.onSnapshot?.call();
      return;
    }
    if (follow && _configurationReader == null) {
      _configurationReader = widget.configurationReader ?? (_dependencies == null ? null : smartFollowConfigurationReader(_dependencies!, widget.batchId, recognitionJobId: widget.recognitionJobId));
    }
    setState(() => _followSelected = follow);
    widget.onModeChanged(follow);
    widget.onConfigurationChanged?.call(null);
    if (!follow) widget.onSnapshot?.call();
  }

  void _open(String sessionId) {
    final callback = widget.onOpenSession;
    if (callback != null) {
      callback(sessionId);
    } else {
      Navigator.of(context).pushNamed(BirdRoutes.smartFollowRun, arguments: SmartFollowRunArgs(sessionId, recognitionJobId: _decision?.job?.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = _decision;
    if (decision == null) return const Padding(padding: EdgeInsets.all(12), child: Text('正在确认本轮识别与复制方式…'));
    final service = widget.creationService ?? _dependencies?.smartFollowCreation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SmartFollowModePanel(
          decision: decision,
          followSelected: _followSelected,
          onModeChanged: _select,
          onOpenSession: _open,
          onOpenRecognition: widget.onOpenRecognition,
          configuration: _configurationReader == null
              ? null
              : service == null
              ? SmartFollowConfigurationForm(reader: _configurationReader!, expectedRecognitionJobId: decision.job?.id, expectedRecognitionPhase: decision.phase, onChanged: widget.onConfigurationChanged)
              : SmartFollowStartPanel(
                  reader: _configurationReader!,
                  service: service,
                  expectedJobId: decision.job?.id,
                  expectedPhase: decision.phase,
                  onConfigurationChanged: widget.onConfigurationChanged,
                  onCreated: (session) => _open(session.sessionId),
                ),
        ),
        if (service != null && !_followSelected)
          SmartFollowPendingCreation(
            service: service,
            batchId: widget.batchId,
            isCurrent: () => widget.reader?.isCurrent() ?? (_dependencies?.deviceSessionCubit.state.isConnected ?? false),
            onRecovered: (session) => _open(session.sessionId),
          ),
        TextButton(onPressed: _load, child: Text(decision.phase == RecognitionEntryPhase.unknown ? '重新检测识别状态' : '刷新识别状态')),
      ],
    );
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
