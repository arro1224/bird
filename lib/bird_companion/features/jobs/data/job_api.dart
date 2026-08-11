import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';

class JobApi {
  JobApi(this._c);
  final ApiClient _c;
  Future<JobPage> page({
    String? cursor,
    int pageSize = 50,
    String? state,
    String? type,
  }) async {
    _validatePageSize(pageSize);
    final d = await _c.get(
      ApiEndpoints.jobs,
      queryParameters: {
        'page_size': pageSize,
        if (cursor?.isNotEmpty == true) 'cursor': cursor,
        if (state?.isNotEmpty == true) 'state': state,
        if (type?.isNotEmpty == true) 'type': type,
      },
    );
    return JobPage(
      items: (d['items'] as List? ?? const []).whereType<Map>().map((x) => BirdJobStatus.fromJson(Map<String, dynamic>.from(x))).toList(),
      hasMore: d['has_more'] == true,
      nextCursor: _cursor(d['next_cursor']),
    );
  }

  Future<BirdJobStatus> detail(String id) {
    _validateId(id, 'jobId');
    return _c.get(ApiEndpoints.jobDetail.replaceFirst('{jobId}', id)).then(BirdJobStatus.fromJson);
  }

  Future<BirdJobStatus> createImport(
    String projectId,
    ImportJobRequest request,
  ) => _c
      .post(
        ApiEndpoints.projectImports.replaceFirst('{projectId}', projectId),
        data: request.toJson(),
      )
      .then(BirdJobStatus.fromJson);

  Future<BirdJobStatus> createAnalysis(
    String projectId,
    AnalysisJobRequest request,
  ) async {
    final normalizedProjectId = projectId.trim();
    _validateId(normalizedProjectId, 'projectId');
    final job = BirdJobStatus.fromJson(
      await _c.post(
        ApiEndpoints.projectAnalysisJobs.replaceFirst(
          '{projectId}',
          normalizedProjectId,
        ),
        data: request.toJson(),
      ),
    );
    if (job.type != BirdJobType.analysis) {
      throw const ProtocolCompatibilityException(
        'job_type',
        'analysis-jobs 必须返回分析任务',
      );
    }
    final sourceProjectId = job.sourceProjectId?.trim();
    if (sourceProjectId != null && sourceProjectId.isNotEmpty && sourceProjectId != normalizedProjectId) {
      throw const ProtocolCompatibilityException(
        'source_project_id',
        '必须与请求项目一致',
      );
    }
    return job;
  }

  Future<BirdJobStatus> control(
    String id,
    String action, {
    required int version,
  }) {
    _validateId(id, 'jobId');
    if (!jobControlActions.contains(action)) {
      throw ArgumentError.value(
        action,
        'action',
        'must match birdbox-v1',
      );
    }
    if (version < 0) {
      throw ArgumentError.value(version, 'version', 'must be non-negative');
    }
    return _c
        .post(
          ApiEndpoints.taskControl.replaceFirst('{jobId}', id),
          data: {'action': action, 'version': version},
        )
        .then(BirdJobStatus.fromJson);
  }

  Future<JobReport> report(String id) async {
    _validateId(id, 'jobId');
    final report = JobReport.fromJson(
      await _c.get(ApiEndpoints.jobReport.replaceFirst('{jobId}', id)),
    );
    if (report.jobId != id) {
      throw const ProtocolCompatibilityException(
        'job_id',
        '必须与请求的任务一致',
      );
    }
    return report;
  }

  Future<void> delete(String id) => _c.delete(ApiEndpoints.jobDelete.replaceFirst('{jobId}', id));
  Future<String?> exportLogs({
    String scope = 'device_and_jobs',
    String? jobId,
  }) async {
    if (!const {'device', 'jobs', 'device_and_jobs'}.contains(scope)) {
      throw ArgumentError.value(scope, 'scope', 'must match birdbox-v1');
    }
    if (jobId != null) _validateId(jobId, 'jobId');
    final data = await _c.post(
      ApiEndpoints.logExport,
      data: {
        'scope': scope,
        'job_id': ?jobId,
      },
    );
    ProtocolValidation.requiredId(data, 'export_id');
    final state = ProtocolValidation.requiredId(data, 'state');
    if (state != 'ready') {
      throw const ProtocolCompatibilityException(
        'state',
        '必须是 ready',
      );
    }
    final downloadUrl = ProtocolValidation.requiredId(data, 'download_url');
    if (Uri.tryParse(downloadUrl) == null) {
      throw const ProtocolCompatibilityException(
        'download_url',
        '必须是有效 URI',
      );
    }
    if (ProtocolValidation.optionalDateTime(data, 'expires_at') == null) {
      throw const ProtocolCompatibilityException('expires_at', '不能为空');
    }
    return downloadUrl;
  }

  Future<JobFailurePage> failurePage(
    String jobId, {
    String? cursor,
    int pageSize = 50,
  }) async {
    _validateId(jobId, 'jobId');
    _validatePageSize(pageSize);
    final data = await _c.get(
      ApiEndpoints.jobFailures.replaceFirst('{jobId}', jobId),
      queryParameters: {
        'page_size': pageSize,
        if (cursor?.isNotEmpty == true) 'cursor': cursor,
      },
    );
    final rawItems = data['items'];
    final hasMore = data['has_more'];
    if (rawItems is! List) {
      throw const ProtocolCompatibilityException(
        'items',
        '必须是失败项列表',
      );
    }
    if (hasMore is! bool) {
      throw const ProtocolCompatibilityException(
        'has_more',
        '必须是布尔值',
      );
    }
    final nextCursor = _cursor(data['next_cursor']);
    if (hasMore && nextCursor == null) {
      throw const ProtocolCompatibilityException(
        'next_cursor',
        '存在下一页时不能为空',
      );
    }
    return JobFailurePage(
      items: rawItems.indexed
          .map((entry) {
            final item = entry.$2;
            if (item is! Map) {
              throw ProtocolCompatibilityException(
                'items[${entry.$1}]',
                '必须是对象',
              );
            }
            return JobFailure.fromJson(Map<String, dynamic>.from(item));
          })
          .toList(growable: false),
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }

  static void _validateId(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }

  static void _validatePageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 200) {
      throw RangeError.range(pageSize, 1, 200, 'pageSize');
    }
  }

  static String? _cursor(Object? value) {
    final cursor = value?.toString().trim();
    return cursor == null || cursor.isEmpty ? null : cursor;
  }
}
