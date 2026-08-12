import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
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
        home: BirdAppShell(
          initialIndex: initialBirdTabFor(
            dependencies.deviceSessionCubit.state,
          ),
          onGenerateRoute: BirdAppRouter.onGenerateRoute,
        ),
        onGenerateRoute: BirdAppRouter.onGenerateRoute,
      ),
    );
  }
}

/// Selects the production startup destination after saved-session recovery.
///
/// A verified box session goes straight to the cached album experience. A
/// first install or an unavailable saved box stays on the device tab so the
/// user can connect explicitly.
int initialBirdTabFor(DeviceSessionState session) => session.isConnected ? 0 : 2;
