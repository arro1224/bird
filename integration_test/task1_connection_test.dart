import 'package:integration_test/integration_test.dart';

import '../test/bird_companion/features/connection/task1_ui_scenarios.dart';

/// Android widget integration entry for task 1. Uses a simulated BLE transport;
/// real Wi-Fi requests, permissions and board recovery remain B7 device gates.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTask1UiScenarios();
}
