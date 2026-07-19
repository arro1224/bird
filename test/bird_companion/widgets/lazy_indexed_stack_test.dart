import 'package:aves/bird_companion/core/widgets/lazy_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('主页面仅在首次访问时创建并保留状态', (tester) async {
    final builds = <int>[0, 0, 0];

    Widget app(int index) => MaterialApp(
      home: LazyIndexedStack(
        key: const ValueKey('tabs'),
        index: index,
        itemCount: builds.length,
        itemBuilder: (_, tab) => _TrackedPage(tab: tab, onBuild: () => builds[tab]++),
      ),
    );

    await tester.pumpWidget(app(0));
    expect(builds, [1, 0, 0]);
    await tester.tap(find.text('0 次'));
    await tester.pump();
    expect(find.text('1 次'), findsOneWidget);
    expect(builds, [2, 0, 0]);

    await tester.pumpWidget(app(1));
    expect(builds, [2, 1, 0]);

    await tester.pumpWidget(app(0));
    expect(builds, [2, 1, 0]);
    expect(find.text('1 次'), findsOneWidget);
  });
}

class _TrackedPage extends StatefulWidget {
  const _TrackedPage({required this.tab, required this.onBuild});

  final int tab;
  final VoidCallback onBuild;

  @override
  State<_TrackedPage> createState() => _TrackedPageState();
}

class _TrackedPageState extends State<_TrackedPage> {
  var count = 0;

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return TextButton(onPressed: () => setState(() => count++), child: Text('$count 次'));
  }
}
