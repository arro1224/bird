import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/b12a_k7_acceptance.dart';
import '../../../tool/mock_box_server/mock_box_server.dart';

void main() {
  test('B12-A K7 gate crosses pages and exercises frozen task writes', () async {
    final server = MockBoxServer(
      photoCount: 3672,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
    );
    final baseUri = await server.start();
    addTearDown(server.close);

    final report = await runB12AK7Acceptance(baseUri);

    expect(report.apiVersion, 'v1');
    expect(report.advertisedPhotos, 3672);
    expect(report.scannedPhotos, 3672);
    expect(report.egretMatches, greaterThan(0));
    expect(report.kingfisherMatches, greaterThan(0));
    expect(report.combinedFilterMatches, greaterThan(0));
    expect(report.progressEvents, greaterThan(2));
    expect(report.exercisedJobIds, hasLength(4));
    expect(report.conflict409Verified, isTrue);
    expect(report.unavailable422Verified, isTrue);
    expect(report.cancelledReportVerified, isTrue);
    expect(report.logBytes, greaterThan(0));
  });
}
