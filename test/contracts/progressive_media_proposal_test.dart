import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/contracts/contract_validator.dart';

void main() {
  final validator = JsonSchemaSubsetValidator(Directory.current);

  test('P1 候选 Photo 与 asset_ready fixtures 符合候选 Schema', () {
    final photoSchema = _jsonFile(
      'docs/contracts/proposals/progressive-media/schemas/photo-media-status.schema.json',
    );
    final eventSchema = _jsonFile(
      'docs/contracts/proposals/progressive-media/schemas/asset-ready-event.schema.json',
    );
    final photo = _jsonFile(
      'docs/contracts/proposals/progressive-media/fixtures/photo-progressive.response.json',
    );
    final event = _jsonFile(
      'docs/contracts/proposals/progressive-media/fixtures/asset-ready-event.response.json',
    );

    expect(
      validator.validate(
        photo,
        photoSchema,
        File(
          'docs/contracts/proposals/progressive-media/schemas/photo-media-status.schema.json',
        ),
      ),
      isEmpty,
    );
    expect(
      validator.validate(
        event,
        eventSchema,
        File(
          'docs/contracts/proposals/progressive-media/schemas/asset-ready-event.schema.json',
        ),
      ),
      isEmpty,
    );
  });

  test('P1 三类错误 fixture 沿用 v1 顶层错误结构', () {
    final errorSchema = _jsonFile(
      'docs/contracts/schemas/error-response.schema.json',
    );
    final schemaFile = File(
      'docs/contracts/schemas/error-response.schema.json',
    );

    for (final name in const [
      'asset-not-ready.error.json',
      'asset-failed.error.json',
      'file-not-found.error.json',
    ]) {
      final fixture = _jsonFile(
        'docs/contracts/proposals/progressive-media/fixtures/$name',
      );
      expect(
        validator.validate(fixture, errorSchema, schemaFile),
        isEmpty,
        reason: name,
      );
    }
  });

  test('asset_ready 候选 Schema 拒绝 pending 事件', () {
    const path = 'docs/contracts/proposals/progressive-media/schemas/asset-ready-event.schema.json';
    final schema = _jsonFile(path);
    final event = _jsonFile(
      'docs/contracts/proposals/progressive-media/fixtures/asset-ready-event.response.json',
    );
    final payload = Map<String, dynamic>.from(event['payload'] as Map)..['status'] = 'pending';
    final invalid = {...event, 'payload': payload};

    expect(
      validator.validate(invalid, schema, File(path)),
      isNotEmpty,
    );
  });
}

Map<String, dynamic> _jsonFile(String path) => Map<String, dynamic>.from(
  jsonDecode(File(path).readAsStringSync()) as Map,
);
