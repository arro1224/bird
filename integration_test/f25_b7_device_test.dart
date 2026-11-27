import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/jobs/data/import_analysis_service.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_repository_impl.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import '../test/bird_companion/features/tasks/import_analysis_service_test.dart' as fixture;
import 'task1_connection_test.dart' as task1;
import 'task2_provisioning_test.dart' as task2;

/// B7 runs in the separate birdSim package so runner cleanup preserves bird.
void main() {
  task1.main();
  task2.main();
  testWidgets('F25 vivo uses production HTTP and resumes one box-owned workflow', (tester) async {
    await tester.runAsync(() async {
      final uri = Uri.parse(const String.fromEnvironment('B7_LAB_BASE_URI', defaultValue: 'http://127.0.0.1:8787'));
      const device = 'bbx-b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7';
      final client = ApiClient()..configure(uri);
      try {
        final health = await client.get(ApiEndpoints.health);
        expect(health['device_id'], device);
        final credential = await PairingApi(client).exchangeSession(uri, deviceId: device, clientId: 'f25b7001-1234-4abc-8def-0123456789ab', pairingSessionId: 'ps_mock_pairing_session');
        client.setSession(accessToken: credential.accessToken);
        final jobs = JobRepositoryImpl(JobApi(client));
        final projects = BatchRepositoryImpl(BatchApi(client));
        final cache = fixture.Store();
        ImportAnalysisService service() => ImportAnalysisService(repository: jobs, batches: projects, cache: cache, readCapabilities: () => client.get(ApiEndpoints.recognitionCapabilities), deviceId: () => device, contextKey: uri.toString);
        final first = await service().start(name: 'F25 vivo synthetic B7', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest());
        expect(first.analysisJob.workflowStage, 'waiting_import');
        final reopened = service();
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await reopened.restoreActive();
          if (reopened.snapshot(first.workflow.projectId)!.analysisJob.isTerminal) break;
        }
        final finished = reopened.snapshot(first.workflow.projectId)!;
        expect(finished.importJob.id, first.importJob.id);
        expect(finished.analysisJob.id, first.analysisJob.id);
        expect(finished.importJob.state, BirdJobState.completed);
        expect(finished.analysisJob.state, BirdJobState.completed);
        debugPrint('F25_HTTP_WORKFLOW=passed transport=${uri.host == '127.0.0.1' ? 'usb_reverse' : 'lan'} project=${first.workflow.projectId} import=${first.importJob.id} analysis=${first.analysisJob.id}');
      } finally {
        await client.dispose();
      }
    });
  });
}
