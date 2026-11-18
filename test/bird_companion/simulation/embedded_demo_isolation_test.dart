import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production import graph cannot reach the embedded service or demo UI', () {
    final pending = ['lib/main.dart', 'lib/main_bird.dart'];
    final visited = <String>{};
    final imports = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!visited.add(path)) continue;
      expect(path, isNot(contains('/simulation/')), reason: 'reachable from the normal app');
      expect(path, isNot(endsWith('main_bird_demo.dart')));
      final file = File(path);
      for (final match in imports.allMatches(file.readAsStringSync())) {
        final uri = match.group(1)!;
        if (uri.startsWith('package:aves/')) {
          pending.add('lib/${uri.substring('package:aves/'.length)}');
        } else if (!uri.contains(':')) {
          final absolute = file.parent.uri.resolve(uri).toFilePath();
          final relative = File(absolute).absolute.path.substring(Directory.current.absolute.path.length + 1).replaceAll('\\', '/');
          if (relative.startsWith('lib/')) pending.add(relative);
        }
      }
    }
    expect(visited.length, greaterThan(30));
  });

  test('CLI and embedded runtime share one server and assets are demo-flavor-only', () {
    final shim = File('tool/mock_box_server/mock_box_server.dart').readAsStringSync();
    final runtime = File('lib/bird_companion/simulation/embedded_demo/demo_runtime.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(shim, contains("export '../../lib/bird_companion/simulation/mock_box_server.dart'"));
    expect(runtime, contains('embeddedDemo: true'));
    expect(runtime, contains("import '../mock_box_server.dart'"));
    expect(pubspec, contains('default-flavor: bird'));
    expect(pubspec.replaceAll('\r\n', '\n'), contains('path: tool/mock_box_server/assets/\n      flavors:\n        - birdDemo'));
  });
}
