import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/widgets/disconnected_banner.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_page.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_page.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BirdAppShell extends StatefulWidget {
  const BirdAppShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<BirdAppShell> createState() => _BirdAppShellState();
}

class _BirdAppShellState extends State<BirdAppShell> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 3).toInt();
  }

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '首页'),
    NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: '图库'),
    NavigationDestination(icon: Icon(Icons.check_rounded), selectedIcon: Icon(Icons.check_circle_rounded), label: '任务'),
    NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const DeviceStatusPage(),
      const BatchListPage(),
      const JobCenterPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('拍鸟伴侣'),
        actions: [
          IconButton(
            tooltip: '重新连接',
            onPressed: () => Navigator.of(context).pushNamed(BirdRoutes.connection),
            icon: const Icon(Icons.wifi_find_outlined),
          ),
        ],
      ),
      body: BirdShellNavigation(
        selectTab: (index) => setState(() => _selectedIndex = index.clamp(0, 3).toInt()),
        child: Column(
          children: [
            BlocBuilder<DeviceSessionCubit, DeviceSessionState>(
              bloc: BirdCompanionScope.of(context).deviceSessionCubit,
              builder: (context, state) => DisconnectedBanner(
                isConnected: state.isConnected,
                lastUpdatedAt: state.lastUpdatedAt,
                onReconnect: () => BirdCompanionScope.of(context).deviceSessionCubit.reconnect(),
              ),
            ),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: _destinations,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

/// Lets homepage shortcuts switch the existing IndexedStack tab instead of
/// pushing a second copy of a main page (and a second set of network listeners).
class BirdShellNavigation extends InheritedWidget {
  const BirdShellNavigation({super.key, required this.selectTab, required super.child});
  final ValueChanged<int> selectTab;

  static BirdShellNavigation? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BirdShellNavigation>();

  @override
  bool updateShouldNotify(BirdShellNavigation oldWidget) => selectTab != oldWidget.selectTab;
}
