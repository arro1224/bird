import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/project.response.json').readAsStringSync()) as Map);
  test('legacy project snapshots remain readable without inventing a CAS', () {
    expect(BatchSummary.fromJson(fixture).projectVersion, isNull);
  });
  test('zero and positive project versions survive copies and cache serialization', () {
    for (final version in [0, 12]) {
      final project = BatchSummary.fromJson({...fixture, 'version': version});
      final copied = project.copyWith(keepCount: 2, countsFromCache: true);
      expect(BatchSummary.fromJson(copied.toJson()).projectVersion, version);
    }
  });
  test('invalid project versions never become zero or a photo version', () {
    for (final version in [-1, 0.5, '3', true]) {
      expect(() => BatchSummary.fromJson({...fixture, 'version': version}), throwsA(isA<ProtocolCompatibilityException>()));
    }
  });
}
