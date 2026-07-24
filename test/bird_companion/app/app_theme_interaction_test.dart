import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('全局按钮和点击表面具有清晰的按压颜色', () {
    final theme = AppTheme.light();
    final pressed = theme.filledButtonTheme.style?.overlayColor?.resolve({
      WidgetState.pressed,
    });

    expect(theme.splashColor.a, greaterThan(.1));
    expect(theme.highlightColor.a, greaterThanOrEqualTo(.1));
    expect(pressed, isNotNull);
    expect(pressed!.a, greaterThan(.1));
  });

  testWidgets('自定义照片点击区域按下时颜色加深', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: BirdPressable(
                onTap: () {},
                borderRadius: BorderRadius.circular(12),
                child: const ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BirdPressable)),
    );
    await tester.pump();

    var container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(BirdPressable),
        matching: find.byType(AnimatedContainer),
      ),
    );
    var decoration = container.foregroundDecoration! as BoxDecoration;
    expect(decoration.color!.a, greaterThan(.1));

    await gesture.up();
    await tester.pumpAndSettle();

    container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(BirdPressable),
        matching: find.byType(AnimatedContainer),
      ),
    );
    decoration = container.foregroundDecoration! as BoxDecoration;
    expect(decoration.color!.a, 0);
  });
}
