import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:flutter/material.dart';

class BirdCompanionApp extends StatelessWidget {
  const BirdCompanionApp({super.key, required this.dependencies});

  final BirdCompanionDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return BirdCompanionScope(
      dependencies: dependencies,
      child: MaterialApp(
        scaffoldMessengerKey: BirdFeedback.messengerKey,
        navigatorObservers: [BirdFeedbackNavigatorObserver()],
        title: '拍鸟伴侣',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: birdStartupHome(
          dependencies.deviceSessionCubit.state,
          provisioningRepository: dependencies.provisioningRepository,
          onProvisioningCompleted: dependencies.completeProvisioning,
        ),
        onGenerateRoute: (settings) => BirdAppRouter.onGenerateRoute(
          settings,
          provisioningRepository: dependencies.provisioningRepository,
          onProvisioningCompleted: dependencies.completeProvisioning,
        ),
      ),
    );
  }
}

/// Chooses the initial experience after the saved device session has been
/// restored by [BirdCompanionDependencies.create].
///
/// The app always opens the shared three-tab home shell. A retained device is
/// shown there when available, while a first-run user sees the empty album and
/// can enter the connection flow from the home or device tab.
Widget birdStartupHome(
  DeviceSessionState session, {
  ProvisioningRepository? provisioningRepository,
  ProvisioningCompletionHandler? onProvisioningCompleted,
}) {
  return BirdAppShell(
    initialIndex: 0,
    onGenerateRoute: (settings) => BirdAppRouter.onGenerateRoute(
      settings,
      provisioningRepository: provisioningRepository,
      onProvisioningCompleted: onProvisioningCompleted,
    ),
  );
}
