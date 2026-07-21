import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/widgets/disconnected_banner.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/core/widgets/lazy_indexed_stack.dart';
import 'package:aves/bird_companion/features/gallery/presentation/album_home_page.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BirdAppShell extends StatefulWidget {
  const BirdAppShell({super.key, this.initialIndex = 0, this.onGenerateRoute});
  final int initialIndex;
  final RouteFactory? onGenerateRoute;

  @override
  State<BirdAppShell> createState() => _BirdAppShellState();
}

class _BirdAppShellState extends State<BirdAppShell> {
  late int _selectedIndex;
  late final ValueNotifier<int> _selectedTab;
  var _bottomNavigationVisible = true;
  final _navigatorKeys = List.generate(3, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 2).toInt();
    _selectedTab = ValueNotifier(_selectedIndex);
  }

  @override
  void dispose() {
    _selectedTab.dispose();
    super.dispose();
  }

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.photo_outlined), selectedIcon: Icon(Icons.photo), label: '相册'),
    NavigationDestination(icon: Icon(Icons.task_outlined), selectedIcon: Icon(Icons.task), label: '处理进度'),
    NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BirdShellNavigation(
        selectTab: _selectTab,
        setBottomNavigationVisible: _setBottomNavigationVisible,
        child: Column(
          children: [
            if (_selectedIndex != 0)
              BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
                bloc: BirdCompanionScope.of(context).deviceSessionCubit,
                builder: (context, state) => DisconnectedBanner(
                  isConnected: state.isConnected,
                  lastUpdatedAt: state.lastUpdatedAt,
                  onReconnect: () => BirdCompanionScope.of(context).deviceSessionCubit.reconnect(),
                ),
              ),
            Expanded(
              child: LazyIndexedStack(
                index: _selectedIndex,
                itemCount: _destinations.length,
                itemBuilder: (_, index) => _TabNavigator(
                  index: index,
                  selectedTab: _selectedTab,
                  navigatorKey: _navigatorKeys[index],
                  onGenerateRoute: widget.onGenerateRoute,
                  root: switch (index) {
                    0 => const AlbumHomePage(),
                    1 => const JobCenterPage(),
                    _ => const SettingsPage(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNavigationVisible
          ? BirdBottomNavigation(
              selectedIndex: _selectedIndex,
              destinations: _destinations,
              onDestinationSelected: _selectTab,
            )
          : null,
    );
  }

  void _selectTab(int index) {
    BirdFeedback.dismissAll();
    final next = index.clamp(0, 2).toInt();
    if (next == _selectedIndex) {
      _navigatorKeys[next].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _selectedIndex = next);
    _selectedTab.value = next;
  }

  void _setBottomNavigationVisible(bool visible) {
    if (_bottomNavigationVisible == visible || !mounted) return;
    setState(() => _bottomNavigationVisible = visible);
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.index, required this.selectedTab, required this.navigatorKey, required this.root, this.onGenerateRoute});

  final int index;
  final ValueListenable<int> selectedTab;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;
  final RouteFactory? onGenerateRoute;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: selectedTab,
    builder: (context, selected, _) => NavigatorPopHandler<Object?>(
      enabled: selected == index,
      onPopWithResult: (result) => navigatorKey.currentState?.pop(result),
      child: Navigator(
        key: navigatorKey,
        observers: [BirdFeedbackNavigatorObserver()],
        onGenerateRoute: (settings) {
          if (settings.name == Navigator.defaultRouteName) {
            return MaterialPageRoute<void>(settings: settings, builder: (_) => root);
          }
          final route = onGenerateRoute?.call(settings);
          return route ??
              MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Scaffold(body: Center(child: Text('页面暂不可用'))),
              );
        },
      ),
    ),
  );
}

class BirdShellNavigation extends InheritedWidget {
  const BirdShellNavigation({
    super.key,
    required this.selectTab,
    required this.setBottomNavigationVisible,
    required super.child,
  });
  final ValueChanged<int> selectTab;
  final ValueChanged<bool> setBottomNavigationVisible;

  static BirdShellNavigation? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BirdShellNavigation>();

  @override
  bool updateShouldNotify(BirdShellNavigation oldWidget) => selectTab != oldWidget.selectTab || setBottomNavigationVisible != oldWidget.setBottomNavigationVisible;
}
