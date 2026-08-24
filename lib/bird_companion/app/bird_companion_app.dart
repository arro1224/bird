import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
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
        ),
        onGenerateRoute: (settings) => BirdAppRouter.onGenerateRoute(
          settings,
          provisioningRepository: dependencies.provisioningRepository,
        ),
      ),
    );
  }
}

/// Chooses the initial experience after the saved device session has been
/// restored by [BirdCompanionDependencies.create].
///
/// A retained device means the user has completed setup before. It remains in
/// the session when reconnecting fails, so cached photos stay available while
/// the box is offline. Only users without device history enter initial setup.
Widget birdStartupHome(
  DeviceSessionState session, {
  ProvisioningRepository? provisioningRepository,
}) {
  if (session.device == null) {
    return ConnectionPage(
      entryMode: ConnectionEntryMode.initialSetup,
      provisioningRepository: provisioningRepository,
    );
  }
  return BirdAppShell(
    initialIndex: 0,
    onGenerateRoute: (settings) => BirdAppRouter.onGenerateRoute(
      settings,
      provisioningRepository: provisioningRepository,
    ),
  );
}
