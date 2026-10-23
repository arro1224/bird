import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_recovery.dart';
import 'package:flutter/material.dart';

/// A cold-start entry back into saved tasks, without forcing navigation.
class ActiveCopyJobsBanner extends StatelessWidget {
  const ActiveCopyJobsBanner({super.key, required this.recovery});
  final CopyJobRecovery recovery;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([recovery, recovery.store]),
    builder: (context, _) {
      final device = recovery.currentDeviceId();
      if (device == null) return const SizedBox.shrink();
      final active = recovery.store.activeForDevice(device);
      final recent = recovery.store.forDevice(device);
      final jobs = active.isNotEmpty ? active : recent.take(1);
      if (jobs.isEmpty) return const SizedBox.shrink();
      return Card(
        key: const Key('active-copy-jobs-banner'),
        child: Column(
          children: [
            for (final job in jobs)
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: Text(job.state.isTerminal ? '查看最近复制结果' : '继续查看复制任务'),
                subtitle: Text('上次读取：${job.state.label}${recovery.canRead(device) ? '' : ' · 等待盒子连接'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed(BirdRoutes.copyJobDetail, arguments: CopyJobDetailArgs(job.jobId, deviceId: device)),
              ),
          ],
        ),
      );
    },
  );
}
