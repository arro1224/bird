import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_companion_app.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/widgets/bird_error_boundary.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

void runIntegratedBirdApp() {
  WidgetsFlutterBinding.ensureInitialized();
  BirdErrorBoundary.install();
  runApp(const IntegratedBirdBootstrap());
}

/// The only production bootstrap for Bird Companion.
///
/// It owns one dependency graph and one [MaterialApp]. Alternate entrypoints
/// must delegate here instead of creating another application tree.
class IntegratedBirdBootstrap extends StatefulWidget {
  const IntegratedBirdBootstrap({super.key});

  @override
  State<IntegratedBirdBootstrap> createState() => _IntegratedBirdBootstrapState();
}

class _IntegratedBirdBootstrapState extends State<IntegratedBirdBootstrap> {
  late final Future<BirdCompanionDependencies> _dependencies = BirdCompanionDependencies.create();
  late final Future<String> _version = _readVersionLabel();
  BirdCompanionDependencies? _createdDependencies;

  @override
  void dispose() {
    _createdDependencies?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BirdCompanionDependencies>(
    future: _dependencies,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        _createdDependencies ??= snapshot.data;
        return BirdCompanionApp(dependencies: snapshot.data!);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppColors.brand,
          body: SafeArea(
            child: Center(
              child: snapshot.hasError ? const _StartupError() : _SplashContent(version: _version),
            ),
          ),
        ),
      );
    },
  );
}

class _SplashContent extends StatelessWidget {
  const _SplashContent({required this.version});

  final Future<String> version;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Spacer(flex: 3),
      const _BirdMark(),
      const SizedBox(height: 22),
      const Text(
        '拍鸟伴侣',
        style: TextStyle(
          color: AppColors.cream,
          fontSize: 34,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 12),
      const SizedBox(
        width: 132,
        child: LinearProgressIndicator(
          minHeight: 3,
          color: AppColors.amber,
          backgroundColor: AppColors.brandMid,
        ),
      ),
      const Spacer(flex: 4),
      FutureBuilder<String>(
        future: version,
        builder: (context, snapshot) => Text(
          snapshot.data?.isNotEmpty == true ? '版本 ${snapshot.data}' : '正在读取版本',
          style: const TextStyle(
            color: AppColors.brandLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 28),
    ],
  );
}

Future<String> _readVersionLabel() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version.trim();
    final buildNumber = packageInfo.buildNumber.trim();
    if (version.isEmpty) return '';
    return buildNumber.isEmpty ? version : '$version+$buildNumber';
  } catch (_) {
    return '';
  }
}

class _BirdMark extends StatelessWidget {
  const _BirdMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 118,
    height: 118,
    decoration: const BoxDecoration(
      color: AppColors.cream,
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.flutter_dash_rounded,
      color: AppColors.brand,
      size: 72,
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, color: AppColors.amber, size: 56),
        SizedBox(height: 16),
        Text(
          '拍鸟伴侣启动失败',
          style: TextStyle(
            color: AppColors.cream,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '请完全关闭应用后重新运行。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.brandLight),
        ),
      ],
    ),
  );
}
