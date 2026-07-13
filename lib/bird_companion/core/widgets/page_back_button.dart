import 'package:aves/bird_companion/app/app_router.dart';
import 'package:flutter/material.dart';

/// 二级页的统一返回按钮。
///
/// 常规场景返回上一页；直接打开页面且导航栈为空时，回到拍鸟伴侣首页。
class BirdPageBackButton extends StatelessWidget {
  const BirdPageBackButton({super.key, this.fallbackRoute = BirdRoutes.shell});

  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacementNamed(fallbackRoute);
        }
      },
    );
  }
}
