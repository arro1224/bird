import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_page.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_page.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_page.dart';
import 'package:aves/bird_companion/features/review/presentation/comparison_review_page.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_page.dart';
import 'package:aves/bird_companion/features/review/presentation/photo_detail_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/diagnostics_page.dart';
import 'package:flutter/material.dart';

abstract final class BirdRoutes {
  static const connection = '/connection';
  static const shell = '/';
  static const gallery = '/gallery';
  static const groupReview = '/group-review';
  static const comparisonReview = '/comparison-review';
  static const photoDetail = '/photo-detail';
  static const copyConfirmation = '/copy-confirmation';
  static const jobDetail = '/job-detail';
  static const jobCenter = '/job-center';
  static const batches = '/batches';
  static const diagnostics = '/diagnostics';
}

abstract final class BirdAppRouter {
  static Route<void> onGenerateRoute(RouteSettings settings) {
    Widget page;
    switch (settings.name) {
      case BirdRoutes.connection:
        page = const ConnectionPage();
      case BirdRoutes.shell:
        final args = settings.arguments;
        page = BirdAppShell(initialIndex: args is ShellArgs ? args.initialIndex : 0);
      case BirdRoutes.gallery:
        final id = _batchId(settings.arguments);
        page = id == null ? _invalid('图库', '缺少批次编号') : GalleryPage(batchId: id);
      case BirdRoutes.groupReview:
        final id = _groupBatchId(settings.arguments);
        page = id == null ? _invalid('分组审阅', '缺少批次编号') : GroupReviewPage(batchId: id);
      case BirdRoutes.comparisonReview:
        final args = settings.arguments;
        page = args is ComparisonReviewArgs && args.fileIds.length >= 2 ? ComparisonReviewPage(args: args) : _invalid('对比审阅', '至少需要两张照片');
      case BirdRoutes.photoDetail:
        final id = _fileId(settings.arguments);
        page = id == null ? _invalid('照片详情', '缺少照片编号') : PhotoDetailPage(fileId: id);
      case BirdRoutes.copyConfirmation:
        final id = _copyBatchId(settings.arguments);
        page = id == null ? _invalid('复制确认', '缺少批次编号') : CopyConfirmationPage(batchId: id);
      case BirdRoutes.jobDetail:
        final args = settings.arguments;
        final id = args is JobDetailArgs
            ? args.jobId
            : args is String
            ? args
            : null;
        page = JobDetailPage(jobId: id, sourceBatchId: args is JobDetailArgs ? args.sourceBatchId : null);
      case BirdRoutes.jobCenter:
        page = const JobCenterPage();
      case BirdRoutes.batches:
        page = const BatchListPage();
      case BirdRoutes.diagnostics:
        page = const DiagnosticsPage();
      default:
        page = _invalid('页面不存在', '请返回拍鸟伴侣首页后重新选择功能');
    }
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }

  static String? _clean(String? value) => value?.trim().isNotEmpty == true ? value!.trim() : null;
  static String? _batchId(Object? value) => _clean(
    value is GalleryArgs
        ? value.batchId
        : value is String
        ? value
        : null,
  );
  static String? _groupBatchId(Object? value) => _clean(
    value is GroupReviewArgs
        ? value.batchId
        : value is String
        ? value
        : null,
  );
  static String? _copyBatchId(Object? value) => _clean(
    value is CopyConfirmationArgs
        ? value.batchId
        : value is String
        ? value
        : null,
  );
  static String? _fileId(Object? value) => _clean(
    value is PhotoDetailArgs
        ? value.fileId
        : value is String
        ? value
        : null,
  );

  static Widget _invalid(String title, String message) => _RouteErrorPage(title: title, message: message);
}

class _RouteErrorPage extends StatelessWidget {
  const _RouteErrorPage({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: EmptyState(
        icon: Icons.explore_off_outlined,
        title: title,
        message: message,
        actionLabel: '返回',
        onAction: () {
          final navigator = Navigator.of(context);
          navigator.canPop() ? navigator.pop() : navigator.pushReplacementNamed(BirdRoutes.shell);
        },
      ),
    ),
  );
}
