import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

// The same JSON is schema-validated in the Python repository. This is DTO
// interoperability evidence, NOT evidence that the unfinished HTTP API works.
void main() {
  final fixture = jsonDecode(File('test/fixtures/contracts/smart_follow_v1.json').readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> section(String name) => Map<String, dynamic>.from(fixture[name] as Map);

  test('Python extension start body keeps the exact App configuration', () {
    const request = SmartFollowStartRequest(targetMediaId: 'media_usb_test', reviewExportEnabled: false, pairPolicy: 'both');
    expect(request.toJson(), section('start'));
  });

  test('Python extension snapshot preserves distinct photo and file counts', () {
    final value = SmartFollowSession.fromJson(section('session'));
    expect(value.sessionId, 'sf_contract_test');
    expect(value.recognizedCount, 12);
    expect(value.eligibleCount, 9);
    expect(value.pendingCount, 1);
    expect(value.assignedCount, 8);
    expect(value.copiedAssetCount, 3);
    expect(value.copiedFileCount, 6);
    expect(value.allowedActions, [SmartFollowAction.pause, SmartFollowAction.finishCurrentResults, SmartFollowAction.stopFollowing]);
  });

  test('Python extension disabled capabilities do not open unfinished features', () {
    final value = SmartFollowCapabilities.fromJson(section('capabilities'));
    expect(value.canShowEntry, isFalse);
    expect(value.canUpdateMetadata, isFalse);
    expect(value.copy.eligibilityMode, 'recognized_only_v1');
    expect(value.copy.batchSizeRange, [1, 32]);
    expect(value.copy.collectWindowMsRange, [250, 10000]);
  });

  test('Python extension child page is explicitly complete', () {
    final value = SmartFollowChildJobPage.fromJson(section('child_page'));
    expect(value.paginationValid, isTrue);
    expect(value.hasMore, isFalse);
    expect(value.items.single.assetCount, 8);
    expect(value.items.single.fileCount, 16);
  });

  test('Python extension preview requires partial consent and known counts', () {
    final availability = SmartFollowMetadataAvailability.fromJson(section('availability'));
    expect(availability.updatableAssetCount, 3);
    expect(availability.blockedAssetCount, 1);
    final preview = SmartFollowMetadataPreview.fromJson(section('metadata_preview'));
    expect(preview.knownCounts, SmartFollowMetadataPreview.countKeys);
    expect(preview.partialConfirmationKnown, isTrue);
    expect(preview.needsPartialConsent, isTrue);
    expect(preview.hasKnownWriteMode, isTrue);
    expect(preview.isExpired, isFalse);
  });

  test('Python extension parent report proves all child writes have stopped', () {
    final value = SmartFollowMetadataUpdate.fromJson(section('metadata_update'));
    expect(value.isTerminal, isTrue);
    expect(value.childrenSettled, isTrue);
    expect(value.updatedAssetCount, 3);
    expect(value.updatedFileCount, 6);
    expect(value.childUpdates.single.copyJobId, 'copy_test');
    expect(value.childUpdates.single.count('updated_file_count'), 6);
  });
}
