import 'dart:io';

import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production shell declares three real experience roots', () {
    final source = File(
      'lib/bird_companion/app/app_shell.dart',
    ).readAsStringSync();

    expect(source, contains('AlbumHomePage'));
    expect(source, contains('TaskExperienceRoot'));
    expect(source, contains('SettingsExperienceRoot'));
    expect(source, isNot(contains('_AlbumPlaceholder')));
    expect(source, isNot(contains('JobCenterPage')));
    expect(source, isNot(contains('SettingsPage()')));
  });

  testWidgets('shell navigation forwards tab and named-route requests', (
    tester,
  ) async {
    int? selectedTab;
    int? routeTab;
    String? routeName;
    Object? routeArguments;

    await tester.pumpWidget(
      MaterialApp(
        home: BirdShellNavigation(
          selectTab: (index) => selectedTab = index,
          openTabRoute: (index, route, [arguments]) {
            routeTab = index;
            routeName = route;
            routeArguments = arguments;
          },
          setBottomNavigationVisible: (_) {},
          child: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  key: const Key('select-task-tab'),
                  onPressed: () => BirdShellNavigation.of(context).selectTab(1),
                  child: const Text('tasks'),
                ),
                TextButton(
                  key: const Key('open-gallery-route'),
                  onPressed: () =>
                      BirdShellNavigation.of(
                        context,
                      ).openTabRoute(
                        0,
                        '/gallery',
                        const GalleryArgs(
                          'project-7',
                          restoreSavedView: true,
                        ),
                      ),
                  child: const Text('gallery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('select-task-tab')));
    await tester.tap(find.byKey(const Key('open-gallery-route')));

    expect(selectedTab, 1);
    expect(routeTab, 0);
    expect(routeName, '/gallery');
    expect(routeArguments, isA<GalleryArgs>());
    expect((routeArguments as GalleryArgs).batchId, 'project-7');
    expect((routeArguments as GalleryArgs).restoreSavedView, isTrue);
  });
}
