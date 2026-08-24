abstract final class ApiEndpoints {
  /// Machine-readable API and DTO baseline. This metadata does not change
  /// runtime routing; new endpoints are added only in their implementation
  /// batch after the contract is accepted.
  static const contractVersion = 'birdbox-v1@1.0.0';

  static const health = '/health';
  // rc4 provisioning extension. Compose it separately so the immutable
  // birdbox-v1@1.0.0 endpoint inventory remains exactly frozen.
  static const apiV1Prefix = '/api/v1';
  static const pairing = '$apiV1Prefix/pairing';
  static const deviceStatus = '/api/v1/device/status';
  static const devicePair = '/api/v1/device/pair';
  static const taskControl = '/api/v1/jobs/{jobId}/actions';
  static const events = '/api/v1/events';
  static const currentCardScan = '/api/v1/storage/cards/current/scan';
  static const currentCardRescan = '/api/v1/storage/cards/current/rescan';
  static const batches = '/api/v1/projects';
  static const projectImports = '/api/v1/projects/{projectId}/imports';
  static const projectAnalysisJobs = '/api/v1/projects/{projectId}/analysis-jobs';
  static const currentBatch = '/api/v1/projects/current';
  static const batchResume = '/api/v1/projects/{batchId}/resume';
  static const photos = '/api/v1/projects/{batchId}/files';
  static const batchPhotoOperation = '/api/v1/projects/{batchId}/files/actions';
  static const groups = '/api/v1/projects/{batchId}/groups';
  static const scenes = '/api/v1/projects/{batchId}/scenes';
  static const speciesSearch = '/api/v1/species';
  static const photoDetail = '/api/v1/files/{fileId}';
  static const photoDecision = '/api/v1/files/{fileId}/decision';
  static const photoHistory = '/api/v1/files/{fileId}/history';
  static const copyEstimate = '/api/v1/projects/{batchId}/copy/estimate';
  static const copyCreate = '/api/v1/projects/{batchId}/copy';
  static const jobs = '/api/v1/jobs';
  static const jobDetail = '/api/v1/jobs/{jobId}';
  static const jobFailures = '/api/v1/jobs/{jobId}/failures';
  static const jobReport = '/api/v1/jobs/{jobId}/report';
  static const jobDelete = '/api/v1/jobs/{jobId}';
  static const logExport = '/api/v1/logs/export';
}
