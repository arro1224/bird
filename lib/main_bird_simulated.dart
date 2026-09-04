import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:aves/bird_companion/simulation/simulated_bird_box_debug_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) {
    throw UnsupportedError(
      'main_bird_simulated.dart is restricted to Debug builds.',
    );
  }
  const baseUrl = String.fromEnvironment(
    'BIRD_TEST_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );
  const deviceId = String.fromEnvironment(
    'BIRD_SIMULATED_DEVICE_ID',
    defaultValue: simulatedBirdBoxDeviceId,
  );
  final config = SimulatedBirdBoxDebugConfig.parse(
    baseUrl: baseUrl,
    deviceId: deviceId,
  );
  runApp(SimulatedBirdBoxDebugApp(config: config));
}
