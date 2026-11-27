import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:flutter/material.dart';

/// Device/settings tab using the shared production session and repositories.
class SettingsExperienceRoot extends StatefulWidget {
  const SettingsExperienceRoot({
    super.key,
  });

  @override
  State<SettingsExperienceRoot> createState() => _SettingsExperienceRootState();
}

class _SettingsExperienceRootState extends State<SettingsExperienceRoot> {
  BirdCompanionDependencies? _dependencies;
  DeviceStatusCubit? _deviceStatus;
  BirdSettingsController? _settingsController;
  StreamSubscription<DeviceSessionState>? _sessionSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependencies != null) return;
    final dependencies = BirdCompanionScope.of(context);
    _dependencies = dependencies;
    _settingsController = BirdSettingsController(
      store: dependencies.settingsStore,
      dataChangeBus: dependencies.dataChangeBus,
    );
    final deviceStatus = DeviceStatusCubit(
      dependencies.deviceRepository,
      dependencies.deviceSessionCubit,
      dependencies.refreshCoordinator,
      dependencies.dataChangeBus,
    );
    _deviceStatus = deviceStatus;
    if (dependencies.deviceSessionCubit.state.isConnected) {
      unawaited(deviceStatus.load());
    }
    _sessionSubscription = dependencies.deviceSessionCubit.stream.listen((
      state,
    ) {
      if (state.isConnected) unawaited(deviceStatus.load());
    });
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    unawaited(_deviceStatus?.close());
    _settingsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    final deviceStatus = _deviceStatus;
    if (dependencies == null || deviceStatus == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DeviceStatusState>(
      stream: deviceStatus.stream,
      initialData: deviceStatus.state,
      builder: (context, snapshot) {
        return SettingsShowcasePage(
          embedded: true,
          deviceSession: dependencies.deviceSessionCubit,
          deviceStatus: deviceStatus,
          settingsController: _settingsController,
          onReconnect: () => openReconnectConnection(context),
        );
      },
    );
  }

}
