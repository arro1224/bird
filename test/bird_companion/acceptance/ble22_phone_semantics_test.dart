import 'package:flutter_test/flutter_test.dart';
import '../../../tool/ble22/phone_inspection_semantics.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final initialEnabled = binding.platformDispatcher.semanticsEnabled;
  final initialHandles = binding.debugOutstandingSemanticsHandles;
  final restore = stabilizePhoneInspectionSemantics(binding);
  tearDownAll(() {
    restore();
    expect(binding.platformDispatcher.semanticsEnabled, initialEnabled);
    expect(binding.debugOutstandingSemanticsHandles, initialHandles);
  });

  testWidgets('platform inspection callbacks preserve the pre-test semantics baseline', (tester) async {
    final handles = binding.debugOutstandingSemanticsHandles;
    expect(binding.platformDispatcher.semanticsEnabled, isTrue);
    for (var i = 0; i < 3; i++) {
      binding.platformDispatcher.onSemanticsEnabledChanged?.call();
    }
    expect(binding.debugOutstandingSemanticsHandles, handles);
  });

  testWidgets('test-owned semantics handles remain separately counted and disposable', (tester) async {
    final handles = binding.debugOutstandingSemanticsHandles;
    final owned = tester.ensureSemantics();
    expect(binding.debugOutstandingSemanticsHandles, handles + 1);
    owned.dispose();
    expect(binding.debugOutstandingSemanticsHandles, handles);
  });
}
