import 'package:flutter_test/flutter_test.dart';

/// UIAutomator can request platform semantics while a live transport test runs.
/// Establish that platform-owned handle before testWidgets records its baseline.
/// Ordinary test-owned handles still have to be disposed by the test framework.
/// This is only for the phone transport entrypoint, not production accessibility.
void Function() stabilizePhoneInspectionSemantics(TestWidgetsFlutterBinding binding) {
  binding.platformDispatcher.semanticsEnabledTestValue = true;
  return binding.platformDispatcher.clearSemanticsEnabledTestValue;
}
