import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/pairing_code_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'requires the Device Info code length and never pre-fills a pairing code',
    (tester) async {
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PairingCodeForm(
              deviceName: 'BirdBox-1A2B3C4D',
              codeMode: PairingCodeMode.sessionRandom,
              codeLength: 6,
              displayAvailable: true,
              onSubmit: (value) => submitted = value,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('请输入盒子屏幕上显示的 6 位配对码。'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('安全配对并连接'));
      await tester.pump();
      expect(submitted, isNull);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('安全配对并连接'));
      expect(submitted, '123456');
    },
  );
}
