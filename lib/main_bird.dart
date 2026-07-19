import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_companion_app.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/widgets/bird_error_boundary.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BirdErrorBoundary.install();
  runApp(const BirdCompanionBootstrap());
}

class BirdCompanionBootstrap extends StatefulWidget {
  const BirdCompanionBootstrap({super.key});

  @override
  State<BirdCompanionBootstrap> createState() => _BirdCompanionBootstrapState();
}

class _BirdCompanionBootstrapState extends State<BirdCompanionBootstrap> {
  late final Future<BirdCompanionDependencies> _dependencies = BirdCompanionDependencies.create();

  @override
  Widget build(BuildContext context) => FutureBuilder<BirdCompanionDependencies>(
    future: _dependencies,
    builder: (context, snapshot) {
      if (snapshot.hasData) return BirdCompanionApp(dependencies: snapshot.data!);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppColors.brand,
          body: SafeArea(
            child: Center(
              child: snapshot.hasError ? const _StartupError() : const _SplashContent(),
            ),
          ),
        ),
      );
    },
  );
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Spacer(flex: 3),
      _BirdMark(),
      SizedBox(height: 22),
      Text(
        '拍鸟伴侣',
        style: TextStyle(color: AppColors.cream, fontSize: 34, fontWeight: FontWeight.w900),
      ),
      SizedBox(height: 12),
      SizedBox(
        width: 132,
        child: LinearProgressIndicator(minHeight: 3, color: AppColors.amber, backgroundColor: AppColors.brandMid),
      ),
      Spacer(flex: 4),
      Text(
        '版本 1.0.0',
        style: TextStyle(color: AppColors.brandLight, fontWeight: FontWeight.w600),
      ),
      SizedBox(height: 28),
    ],
  );
}

class _BirdMark extends StatelessWidget {
  const _BirdMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 118,
    height: 118,
    decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
    child: const Icon(Icons.flutter_dash_rounded, color: AppColors.brand, size: 72),
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
          style: TextStyle(color: AppColors.cream, fontSize: 22, fontWeight: FontWeight.w900),
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
