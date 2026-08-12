import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
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
        home: const BirdAppShell(
          initialIndex: birdStartupTab,
          onGenerateRoute: BirdAppRouter.onGenerateRoute,
        ),
        onGenerateRoute: BirdAppRouter.onGenerateRoute,
      ),
    );
  }
}

/// The device module is a destination inside the app, never the app entry.
/// Cached photos remain available from the album while the box is offline.
const birdStartupTab = 0;
