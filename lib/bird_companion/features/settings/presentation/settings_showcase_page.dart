import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/settings/presentation/adapters/device_overview_adapter.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_details_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/device_management_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/display_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/photo_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/storage_target_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_atmosphere.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/device_current_work_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsShowcasePage extends StatefulWidget {
  const SettingsShowcasePage({
    super.key,
    this.deviceSession,
    this.deviceStatus,
    this.onReconnect,
    this.embedded = false,
    this.currentBatchTitle,
    this.currentBatchSummary,
    this.currentTaskTitle,
    this.currentTaskSummary,
    this.onOpenCurrentBatch,
    this.onOpenCurrentTask,
    this.settingsController,
  }) : assert(
         (currentBatchTitle == null &&
                 currentBatchSummary == null &&
                 currentTaskTitle == null &&
                 currentTaskSummary == null) ||
             (currentBatchTitle != null &&
                 currentBatchSummary != null &&
                 currentTaskTitle != null &&
                 currentTaskSummary != null),
         'Current batch and task summaries must be injected together.',
       );

  final StateStreamable<DeviceSessionState>? deviceSession;
  final StateStreamable<DeviceStatusState>? deviceStatus;
  final VoidCallback? onReconnect;
  final bool embedded;
  final String? currentBatchTitle;
  final String? currentBatchSummary;
  final String? currentTaskTitle;
  final String? currentTaskSummary;
  final VoidCallback? onOpenCurrentBatch;
  final VoidCallback? onOpenCurrentTask;
  final BirdSettingsController? settingsController;

  @override
  State<SettingsShowcasePage> createState() => _SettingsShowcasePageState();
}

class _SettingsShowcasePageState extends State<SettingsShowcasePage> {
  late final BirdSettingsController _controller =
      widget.settingsController ?? BirdSettingsController();
  late final bool _ownsController = widget.settingsController == null;
  int _selectedNavigationIndex = 2;

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('settings-showcase-page'),
    backgroundColor: AppColors.paper,
    body: Stack(
      children: [
        const Positioned.fill(child: BirdSettingsAtmosphere(home: true)),
        SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(child: _PageTitle()),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverToBoxAdapter(child: _buildDeviceCard(context)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                sliver: SliverList.list(
                  children: [
                    _buildCurrentWork(context),
                    const SizedBox(height: AppSpacing.sm),
                    _buildSection(
                      context,
                      sectionKey: const Key('device-section-connection'),
                      title: '设备与连接',
                      items: [
                        if (context
                                .dependOnInheritedWidgetOfExactType<
                                  BirdCompanionScope
                                >() !=
                            null)
                          _HomeItem(
                            key: const Key('showcase-network-settings'),
                            title: '网络设置',
                            icon: Icons.router_outlined,
                            onTap: () => _open(_SettingsPage.networkSettings),
                          ),
                        _HomeItem(
                          key: const Key('showcase-device-management'),
                          title: '连接设备',
                          icon: Icons.link_rounded,
                          onTap: () => _open(_SettingsPage.deviceManagement),
                        ),
                        _HomeItem(
                          key: const Key('showcase-device-details'),
                          title: '设备详情',
                          icon: Icons.info_outline_rounded,
                          onTap: () => _open(_SettingsPage.deviceDetails),
                        ),
                        _HomeItem(
                          key: const Key('showcase-network-diagnostics'),
                          title: '网络诊断',
                          icon: Icons.wifi_rounded,
                          onTap: () => _open(_SettingsPage.networkDiagnostics),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildSection(
                      context,
                      sectionKey: const Key('device-section-photo'),
                      title: '照片与审阅',
                      items: [
                        _HomeItem(
                          key: const Key('showcase-display-settings'),
                          title: '浏览与显示',
                          icon: Icons.grid_view_rounded,
                          onTap: () => _open(_SettingsPage.display),
                        ),
                        _HomeItem(
                          key: const Key('showcase-photo-settings'),
                          title: '照片处理默认值',
                          icon: Icons.tune_rounded,
                          onTap: () => _open(_SettingsPage.photos),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildSection(
                      context,
                      sectionKey: const Key('device-section-copy'),
                      title: '复制与导出',
                      items: [
                        _HomeItem(
                          key: const Key('showcase-copy-settings'),
                          title: '复制默认设置',
                          icon: Icons.copy_all_rounded,
                          onTap: () => _open(_SettingsPage.copyBackup),
                        ),
                        _HomeItem(
                          key: const Key('showcase-storage-target'),
                          title: '默认目标位置',
                          icon: Icons.storage_rounded,
                          onTap: () => _open(_SettingsPage.storageTarget),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildSection(
                      context,
                      sectionKey: const Key('device-section-support'),
                      title: '系统支持',
                      items: [
                        _HomeItem(
                          key: const Key('showcase-system-logs'),
                          title: '系统与日志',
                          icon: Icons.receipt_long_outlined,
                          onTap: () => _open(_SettingsPage.systemLogs),
                        ),
                        _HomeItem(
                          key: const Key('showcase-help-center'),
                          title: '帮助中心',
                          icon: Icons.help_outline_rounded,
                          onTap: () => _open(_SettingsPage.help),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    bottomNavigationBar: widget.embedded
        ? null
        : NavigationBar(
            selectedIndex: _selectedNavigationIndex,
            onDestinationSelected: _onNavigationSelected,
            backgroundColor: AppColors.surface.withValues(alpha: .94),
            surfaceTintColor: Colors.transparent,
            indicatorColor: Colors.transparent,
            height: 82,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library_rounded),
                label: '相册',
              ),
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment_rounded),
                label: '任务',
              ),
              NavigationDestination(
                icon: Icon(Icons.devices_outlined),
                selectedIcon: Icon(Icons.devices_rounded),
                label: '设备',
              ),
            ],
          ),
  );

  Widget _buildDeviceCard(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<BirdCompanionScope>();
    final dependencies = scope?.dependencies;
    final session = widget.deviceSession ?? dependencies?.deviceSessionCubit;
    final status = widget.deviceStatus;
    void onReconnect() {
      final injectedReconnect = widget.onReconnect;
      if (injectedReconnect != null) {
        injectedReconnect();
        return;
      }

      openReconnectConnection(context);
    }

    return _LiveDeviceCard(
      session: session,
      status: status,
      onReconnect: onReconnect,
      onOpenDetails: () => _open(_SettingsPage.deviceDetails),
    );
  }

  Widget _buildCurrentWork(BuildContext context) {
    final isDemo = widget.currentBatchTitle == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Text(
            '当前工作',
            style: TextStyle(
              color: AppColors.forestDeep,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        DeviceCurrentWorkCard(
          batchTitle: widget.currentBatchTitle ?? '演示批次',
          batchSummary: widget.currentBatchSummary ?? '湖畔清晨 · 328 张照片 · 24 张待审',
          taskTitle: widget.currentTaskTitle ?? '演示任务',
          taskSummary: widget.currentTaskSummary ?? 'AI 分析 · 65%',
          isDemo: isDemo,
          onOpenBatch:
              widget.onOpenCurrentBatch ?? () => _showMessage('演示批次详情'),
          onOpenTask: widget.onOpenCurrentTask ?? () => _showMessage('演示任务详情'),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required Key sectionKey,
    required String title,
    required List<_HomeItem> items,
  }) => Material(
    key: sectionKey,
    color: AppColors.surface.withValues(alpha: .96),
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    shadowColor: const Color(0x15142A1B),
    elevation: 3,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xxs,
        AppSpacing.sm,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: 2,
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.forestDeep,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          for (final item in items) _buildHomeItem(item),
        ],
      ),
    ),
  );

  Widget _buildHomeItem(_HomeItem item) => InkWell(
    key: item.key,
    onTap: item.onTap,
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Icon(item.icon, size: 24, color: AppColors.forestPrimary),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              item.title,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: AppColors.forestDeep,
          ),
        ],
      ),
    ),
  );

  void _onNavigationSelected(int index) {
    if (index == 2) return;
    setState(() => _selectedNavigationIndex = index);
    _showMessage(index == 0 ? '相册模块将在这里打开' : '任务模块将在这里打开');
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _selectedNavigationIndex = 2);
    });
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _open(_SettingsPage page) async {
    final shell = BirdShellNavigation.maybeOf(context);
    shell?.setBottomNavigationVisible(false);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => _buildPage(context, page),
        ),
      );
    } finally {
      if (mounted) shell?.setBottomNavigationVisible(true);
    }
  }

  Widget _buildPage(BuildContext context, _SettingsPage page) => switch (page) {
    _SettingsPage.deviceManagement => DeviceManagementPage(
      controller: _controller,
      onOpenDetails: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DeviceDetailsPage(controller: _controller),
        ),
      ),
    ),
    _SettingsPage.deviceDetails => DeviceDetailsPage(controller: _controller),
    _SettingsPage.display => DisplaySettingsPage(controller: _controller),
    _SettingsPage.photos => PhotoSettingsPage(controller: _controller),
    _SettingsPage.copyBackup => CopyBackupSettingsPage(controller: _controller),
    _SettingsPage.storageTarget => StorageTargetPage(controller: _controller),
    _SettingsPage.networkSettings => NetworkSettingsPage(
      repository: BirdCompanionScope.of(context).provisioningRepository,
      onProvisioningCompleted:
          BirdCompanionScope.of(context).completeProvisioning,
    ),
    _SettingsPage.networkDiagnostics => const NetworkDiagnosticsPage(),
    _SettingsPage.systemLogs => const SystemLogsPage(),
    _SettingsPage.help => const HelpCenterPage(),
  };
}

class _LiveDeviceCard extends StatelessWidget {
  const _LiveDeviceCard({
    this.session,
    this.status,
    required this.onReconnect,
    required this.onOpenDetails,
  });

  final StateStreamable<DeviceSessionState>? session;
  final StateStreamable<DeviceStatusState>? status;
  final VoidCallback onReconnect;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final initialSession = session?.state ?? const DeviceSessionState();
    final initialStatus = status?.state;
    return StreamBuilder<DeviceSessionState>(
      key: ObjectKey(session),
      stream: session?.stream,
      initialData: initialSession,
      builder: (context, sessionSnapshot) {
        final currentSession = sessionSnapshot.data ?? initialSession;
        return StreamBuilder<DeviceStatusState>(
          key: ObjectKey(status),
          stream: status?.stream,
          initialData: initialStatus,
          builder: (context, statusSnapshot) => SettingsDeviceCard(
            overview: DeviceOverviewAdapter.map(
              session: currentSession,
              status: statusSnapshot.data?.status,
            ),
            onReconnect: onReconnect,
            onOpenDetails: onOpenDetails,
          ),
        );
      },
    );
  }
}

class SettingsDeviceCard extends StatelessWidget {
  const SettingsDeviceCard({
    super.key,
    required this.overview,
    required this.onReconnect,
    required this.onOpenDetails,
  });

  final DeviceOverviewViewModel overview;
  final VoidCallback onReconnect;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('showcase-device-card'),
    color: AppColors.surface.withValues(alpha: .97),
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    elevation: 3,
    shadowColor: const Color(0x241B2E20),
    child: InkWell(
      onTap: _isConnecting ? null : _primaryAction,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 78,
              height: 96,
              child: Center(child: BirdSettingsDeviceIcon(size: 66)),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    overview.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.forestDeep,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Icon(
                        _statusIcon(overview.connectionKind),
                        size: 18,
                        color: _statusColor(overview.connectionKind),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        overview.statusLabel,
                        style: TextStyle(
                          color: _statusColor(overview.connectionKind),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    overview.metricsLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 15,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            OutlinedButton(
              key: const Key('showcase-device-primary-action'),
              onPressed: _isConnecting ? null : _primaryAction,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(86, AppSpacing.minimumControl),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                side: const BorderSide(
                  color: AppColors.forestPrimary,
                  width: 1.5,
                ),
                foregroundColor: AppColors.forestPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusCompact),
                ),
              ),
              child: _isConnecting
                  ? Semantics(
                      label: '正在连接设备',
                      child: const ExcludeSemantics(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      _primaryActionLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  bool get _isConnecting => overview.isBusy;

  VoidCallback get _primaryAction => switch (overview.primaryAction) {
    DeviceOverviewPrimaryAction.reconnect => onReconnect,
    DeviceOverviewPrimaryAction.details => onOpenDetails,
  };

  String get _primaryActionLabel => switch (overview.primaryAction) {
    DeviceOverviewPrimaryAction.reconnect => '重新连接',
    DeviceOverviewPrimaryAction.details => '设备详情',
  };

  static IconData _statusIcon(DeviceOverviewConnectionKind kind) =>
      switch (kind) {
        DeviceOverviewConnectionKind.connected => Icons.wifi_rounded,
        DeviceOverviewConnectionKind.connecting ||
        DeviceOverviewConnectionKind.reconnecting => Icons.sync_rounded,
        DeviceOverviewConnectionKind.incompatible =>
          Icons.error_outline_rounded,
        DeviceOverviewConnectionKind.disconnected => Icons.wifi_off_rounded,
      };

  static Color _statusColor(DeviceOverviewConnectionKind kind) =>
      switch (kind) {
        DeviceOverviewConnectionKind.connected => AppColors.forestPrimary,
        DeviceOverviewConnectionKind.connecting ||
        DeviceOverviewConnectionKind.reconnecting => AppColors.warning,
        DeviceOverviewConnectionKind.incompatible => AppColors.danger,
        DeviceOverviewConnectionKind.disconnected => AppColors.mutedInk,
      };
}

class _PageTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(
    '设备',
    style: Theme.of(context).textTheme.displaySmall?.copyWith(
      color: AppColors.forestDeep,
      fontWeight: FontWeight.w800,
      height: 1,
      fontSize: 34,
    ),
  );
}

class _HomeItem {
  const _HomeItem({
    this.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final Key? key;
  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

enum _SettingsPage {
  deviceManagement,
  deviceDetails,
  display,
  photos,
  copyBackup,
  storageTarget,
  networkSettings,
  networkDiagnostics,
  systemLogs,
  help,
}
