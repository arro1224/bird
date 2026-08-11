import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';

class JobPage {
  const JobPage({required this.items, required this.hasMore, this.nextCursor});

  final List<BirdJobStatus> items;
  final bool hasMore;
  final String? nextCursor;
}

class JobFailurePage {
  const JobFailurePage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  const JobFailurePage.empty() : items = const [], hasMore = false, nextCursor = null;

  final List<JobFailure> items;
  final bool hasMore;
  final String? nextCursor;
}
