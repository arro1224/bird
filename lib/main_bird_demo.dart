import 'package:aves/bird_companion/core/widgets/bird_error_boundary.dart';
import 'package:aves/bird_companion/simulation/embedded_demo/embedded_demo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'package:aves/bird_companion/simulation/embedded_demo/embedded_demo_app.dart';

/// Explicit opt-in entry. Normal main.dart and the bird flavor remain real-box.
void main() {
  if (appFlavor != 'birdDemo') {
    throw StateError('Embedded demo requires --flavor birdDemo -t lib/main_bird_demo.dart.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  BirdErrorBoundary.install();
  runApp(const BirdDemoBootstrap());
}
