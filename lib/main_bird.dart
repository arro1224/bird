import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_companion_app.dart';
import 'package:flutter/material.dart';
import 'package:aves/bird_companion/core/widgets/bird_error_boundary.dart';

/// 拍鸟伴侣独立入口。
///
/// 先绘制启动页，再初始化 Hive 等本地依赖，避免低版本真机在首帧前出现白屏。
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
  Widget build(BuildContext context) {
    return FutureBuilder<BirdCompanionDependencies>(
      future: _dependencies,
      builder: (context, snapshot) {
        if (snapshot.hasData) return BirdCompanionApp(dependencies: snapshot.data!);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('拍鸟伴侣启动失败，请完全停止应用后重新运行。'),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [CircularProgressIndicator(), SizedBox(height: 16), Text('正在启动拍鸟伴侣…')],
                    ),
            ),
          ),
        );
      },
    );
  }
}
