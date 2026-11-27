import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';

class ImportAnalysisCapability {
  const ImportAnalysisCapability({required this.available, this.smartFollowAvailable = false});
  factory ImportAnalysisCapability.fromJson(Map<String, dynamic> json) {
    final raw = json['import_analysis_workflow'];
    if (raw == null) return const ImportAnalysisCapability(available: false);
    if (raw is! Map || raw['available'] is! bool) throw const ProtocolCompatibilityException('import_analysis_workflow', '能力字段无效');
    if (raw['available'] == false) return const ImportAnalysisCapability(available: false);
    if (raw['contract_version'] != 'import-analysis-v1' || raw['owner'] != 'box' || raw['request_field'] != 'auto_analysis' || raw['status_path'] != ApiEndpoints.importAnalysisStatusTemplate || raw['smart_follow_available'] is! bool) {
      throw const ProtocolCompatibilityException('import_analysis_workflow', '自动导入识别契约无法确认');
    }
    return ImportAnalysisCapability(available: true, smartFollowAvailable: raw['smart_follow_available'] == true);
  }
  final bool available, smartFollowAvailable;
}

class ImportWorkflow {
  ImportWorkflow.fromJson(Map<String, dynamic> json, {required String expectedProject})
    : projectId = ProtocolValidation.requiredId(json, 'project_id'),
      importJobId = ProtocolValidation.requiredId(json, 'import_job_id'),
      analysisJobId = ProtocolValidation.requiredId(json, 'analysis_job_id'),
      sessionId = json['smart_follow_session_id'] == null ? null : ProtocolValidation.requiredId(json, 'smart_follow_session_id'),
      dispatchState = json['dispatch_state']?.toString() {
    if (json['owner'] != 'box' || json['contract_version'] != 'import-analysis-v1' || projectId != expectedProject || importJobId == analysisJobId) {
      throw const ProtocolCompatibilityException('workflow', '流程所有者或任务归属不一致');
    }
  }
  final String projectId, importJobId, analysisJobId;
  final String? sessionId, dispatchState;
  Map<String, dynamic> toJson() => {
    'contract_version': 'import-analysis-v1',
    'owner': 'box',
    'project_id': projectId,
    'import_job_id': importJobId,
    'analysis_job_id': analysisJobId,
    'smart_follow_session_id': sessionId,
    if (dispatchState != null) 'dispatch_state': dispatchState,
  };
  void checkJobs(BirdJobStatus imported, BirdJobStatus analysis) {
    if (imported.id != importJobId ||
        analysis.id != analysisJobId ||
        imported.type != BirdJobType.import ||
        analysis.type != BirdJobType.analysis ||
        imported.sourceProjectId != projectId ||
        analysis.sourceProjectId != projectId ||
        (analysis.smartFollowSessionId != null && analysis.smartFollowSessionId != sessionId)) {
      throw const ProtocolCompatibilityException('workflow.jobs', '任务与当前流程不一致');
    }
  }
}

class ImportStartResult {
  ImportStartResult({required this.workflow, required this.importJob, required this.analysisJob}) {
    workflow.checkJobs(importJob, analysisJob);
  }
  factory ImportStartResult.fromEnvelope(Map<String, dynamic> json, {required String projectId}) => ImportStartResult(
    workflow: ImportWorkflow.fromJson(_map(json, 'workflow'), expectedProject: projectId),
    importJob: BirdJobStatus.fromJson(_map(json, 'data')),
    analysisJob: BirdJobStatus.fromJson(_map(json, 'analysis_job')),
  );
  factory ImportStartResult.fromSnapshot(Map<String, dynamic> json, {required String projectId}) => ImportStartResult(
    workflow: ImportWorkflow.fromJson(json, expectedProject: projectId),
    importJob: BirdJobStatus.fromJson(_map(json, 'import_job')),
    analysisJob: BirdJobStatus.fromJson(_map(json, 'analysis_job')),
  );
  final ImportWorkflow workflow;
  final BirdJobStatus importJob, analysisJob;
  Map<String, dynamic> toSnapshot() => {...workflow.toJson(), 'import_job': importJob.toJson(), 'analysis_job': analysisJob.toJson()};
  static Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! Map) throw ProtocolCompatibilityException(key, '完整流程响应缺少对象');
    return Map<String, dynamic>.from(value);
  }
}

/// Optional additive boundary; legacy callers keep their single-job result.
abstract interface class ImportWorkflowRepository {
  Future<ImportStartResult> startImportWorkflow(String projectId, Map<String, dynamic> request, String key);
  Future<ImportStartResult> importWorkflow(String projectId);
  Future<BirdJobStatus> controlWorkflowJob(String jobId, String action, int version, String key);
}
