import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const contractVersion = 'birdbox-v1@1.0.0';

const _frozenContractArtifacts = <String>{
  'docs/contracts/birdbox-v1.openapi.yaml',
  'docs/contracts/schemas/bird-job-status.schema.json',
  'docs/contracts/schemas/device-status.schema.json',
  'docs/contracts/schemas/error-response.schema.json',
  'docs/contracts/schemas/event-envelope.schema.json',
  'docs/contracts/schemas/photo.schema.json',
  'docs/contracts/schemas/project.schema.json',
  'docs/contracts/schemas/user-decision-patch.schema.json',
  'docs/decisions/ADR-001-birdbox-v1.md',
  'docs/盒子端接口说明7.24.md',
};

const _frozenOperations = <String>{
  'GET /device/status',
  'POST /device/pair',
  'GET /events',
  'GET /storage/cards/current/scan',
  'POST /storage/cards/current/rescan',
  'GET /projects',
  'POST /projects',
  'GET /projects/current',
  'POST /projects/{projectId}/resume',
  'POST /projects/{projectId}/imports',
  'POST /projects/{projectId}/analysis-jobs',
  'GET /projects/{projectId}/files',
  'POST /projects/{projectId}/files/actions',
  'GET /projects/{projectId}/groups',
  'GET /projects/{projectId}/scenes',
  'GET /species',
  'GET /files/{fileId}',
  'POST /files/{fileId}/decision',
  'GET /files/{fileId}/history',
  'GET /projects/{projectId}/copy/estimate',
  'POST /projects/{projectId}/copy',
  'GET /jobs',
  'GET /jobs/{jobId}',
  'DELETE /jobs/{jobId}',
  'POST /jobs/{jobId}/actions',
  'GET /jobs/{jobId}/failures',
  'GET /jobs/{jobId}/report',
  'POST /logs/export',
};

const _requiredExternalBaselineValues = <String>[
  'box.repository',
  'box.branch',
  'box.firmware_sha',
  'box.deployment_command',
  'box.database_schema_version',
  'box.database_migration',
  'box.database_rollback',
  'box.integration_base_url',
  'owners.protocol.contact',
  'owners.flutter_core.contact',
  'owners.box_api.contact',
  'owners.qa_release.contact',
];

final class ContractValidationResult {
  const ContractValidationResult(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

Future<ContractValidationResult> validateBirdBoxContracts({
  required Directory repositoryRoot,
  bool strictBaseline = false,
}) async {
  final errors = <String>[];
  errors.addAll(
    validateBirdBoxContractFreeze(repositoryRoot: repositoryRoot).errors,
  );
  final openApiFile = File(
    _join(repositoryRoot.path, 'docs/contracts/birdbox-v1.openapi.yaml'),
  );
  final baselineFile = File(
    _join(repositoryRoot.path, 'docs/contracts/birdbox-v1-baseline.json'),
  );
  final manifestFile = File(
    _join(repositoryRoot.path, 'test/contracts/fixture-manifest.json'),
  );

  final openApi = _readJsonMap(openApiFile, errors);
  if (openApi != null) {
    _validateOpenApi(openApi, openApiFile, errors);
    _ReferenceAuditor(errors).audit(openApi, openApiFile);
  }

  final baseline = _readJsonMap(baselineFile, errors);
  if (baseline != null) {
    _validateBaseline(baseline, errors, strict: strictBaseline);
  }

  final manifest = _readJsonMap(manifestFile, errors);
  if (manifest != null) {
    _validateFixtures(
      repositoryRoot: repositoryRoot,
      manifestFile: manifestFile,
      manifest: manifest,
      errors: errors,
    );
  }
  _validateVersionReferences(repositoryRoot, errors);

  return ContractValidationResult(errors);
}

ContractValidationResult validateBirdBoxContractFreeze({
  required Directory repositoryRoot,
}) {
  final errors = <String>[];
  final freezeFile = File(
    _join(repositoryRoot.path, 'docs/contracts/birdbox-v1-freeze.json'),
  );
  final freeze = _readJsonMap(freezeFile, errors);
  if (freeze == null) {
    return ContractValidationResult(errors);
  }
  if (freeze['contract'] != contractVersion || freeze['api_version'] != 'v1' || freeze['policy'] != 'immutable' || freeze['new_interface_count'] != 0) {
    errors.add(
      '${freezeFile.path}: must freeze $contractVersion / API v1 as immutable with zero new interfaces',
    );
  }

  final rawArtifacts = freeze['artifacts'];
  if (rawArtifacts is! Map) {
    errors.add('${freezeFile.path}: artifacts must be an object');
    return ContractValidationResult(errors);
  }
  final artifacts = rawArtifacts.map(
    (key, value) => MapEntry(key.toString(), value.toString().toLowerCase()),
  );
  final actualPaths = artifacts.keys.toSet();
  for (final path in _frozenContractArtifacts.difference(actualPaths)) {
    errors.add('${freezeFile.path}: missing frozen artifact $path');
  }
  for (final path in actualPaths.difference(_frozenContractArtifacts)) {
    errors.add(
      '${freezeFile.path}: unexpected frozen artifact $path; register new-version work in a separate proposal',
    );
  }

  final digestPattern = RegExp(r'^[0-9a-f]{64}$');
  for (final path in _frozenContractArtifacts) {
    final expectedDigest = artifacts[path];
    if (expectedDigest == null) {
      continue;
    }
    if (!digestPattern.hasMatch(expectedDigest)) {
      errors.add('${freezeFile.path}: invalid SHA-256 for $path');
      continue;
    }
    final artifact = File(_join(repositoryRoot.path, path));
    if (!artifact.existsSync()) {
      errors.add('missing frozen artifact: ${artifact.path}');
      continue;
    }
    final actualDigest = sha256.convert(artifact.readAsBytesSync()).toString();
    if (actualDigest != expectedDigest) {
      errors.add(
        'frozen contract drift: $path changed; do not modify $contractVersion. Create an independent versioned interface proposal.',
      );
    }
  }
  return ContractValidationResult(errors);
}

Map<String, dynamic>? _readJsonMap(File file, List<String> errors) {
  if (!file.existsSync()) {
    errors.add('missing file: ${file.path}');
    return null;
  }
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map) {
      errors.add('${file.path}: root must be an object');
      return null;
    }
    return Map<String, dynamic>.from(value);
  } on FormatException catch (error) {
    errors.add('${file.path}: invalid JSON/YAML-subset: $error');
    return null;
  }
}

void _validateOpenApi(
  Map<String, dynamic> openApi,
  File openApiFile,
  List<String> errors,
) {
  if (openApi['openapi'] != '3.1.0') {
    errors.add('${openApiFile.path}: openapi must be 3.1.0');
  }
  final info = openApi['info'];
  if (info is! Map || info['version'] != '1.0.0') {
    errors.add('${openApiFile.path}: info.version must be 1.0.0');
  }
  final paths = openApi['paths'];
  if (paths is! Map) {
    errors.add('${openApiFile.path}: paths must be an object');
    return;
  }

  const requiredPaths = <String>{
    '/device/status',
    '/device/pair',
    '/events',
    '/storage/cards/current/scan',
    '/storage/cards/current/rescan',
    '/projects',
    '/projects/current',
    '/projects/{projectId}/resume',
    '/projects/{projectId}/imports',
    '/projects/{projectId}/analysis-jobs',
    '/projects/{projectId}/files',
    '/projects/{projectId}/files/actions',
    '/projects/{projectId}/groups',
    '/projects/{projectId}/scenes',
    '/species',
    '/files/{fileId}',
    '/files/{fileId}/decision',
    '/files/{fileId}/history',
    '/projects/{projectId}/copy/estimate',
    '/projects/{projectId}/copy',
    '/jobs',
    '/jobs/{jobId}',
    '/jobs/{jobId}/actions',
    '/jobs/{jobId}/failures',
    '/jobs/{jobId}/report',
    '/logs/export',
  };
  final actualPaths = paths.keys.map((value) => value.toString()).toSet();
  for (final path in requiredPaths.difference(actualPaths)) {
    errors.add('${openApiFile.path}: missing required path $path');
  }

  final actualOperations = <String>{};
  const httpMethods = <String>{'get', 'post', 'put', 'patch', 'delete'};
  for (final entry in paths.entries) {
    final pathItem = entry.value;
    if (pathItem is! Map) {
      continue;
    }
    for (final method in httpMethods) {
      if (pathItem[method] is Map) {
        actualOperations.add('${method.toUpperCase()} ${entry.key}');
      }
    }
  }
  for (final operation in _frozenOperations.difference(actualOperations)) {
    errors.add('${openApiFile.path}: missing frozen operation $operation');
  }
  for (final operation in actualOperations.difference(_frozenOperations)) {
    errors.add(
      '${openApiFile.path}: new v1 operation is forbidden: $operation; create an independent versioned interface proposal',
    );
  }

  for (final entry in paths.entries) {
    final pathItem = entry.value;
    if (pathItem is! Map) {
      continue;
    }
    final pathParameters = pathItem['parameters'];
    final hasApiVersion =
        pathParameters is List &&
        pathParameters.whereType<Map>().any(
          (parameter) => parameter[r'$ref'] == '#/components/parameters/ApiVersion' || parameter['name'] == 'X-Api-Version',
        );
    if (!hasApiVersion) {
      errors.add(
        '${openApiFile.path}: ${entry.key} must require X-Api-Version',
      );
    }
    final post = pathItem['post'];
    if (post is! Map) {
      continue;
    }
    final parameters = post['parameters'];
    final hasIdempotencyHeader =
        parameters is List &&
        parameters.whereType<Map>().any(
          (parameter) => parameter[r'$ref'] == '#/components/parameters/IdempotencyKey' || parameter['name'] == 'X-Idempotency-Key',
        );
    if (!hasIdempotencyHeader) {
      errors.add(
        '${openApiFile.path}: POST ${entry.key} must require X-Idempotency-Key',
      );
    }
    final requestBody = post['requestBody'];
    if (_containsKeyRecursively(requestBody, 'idempotency_key')) {
      errors.add(
        '${openApiFile.path}: POST ${entry.key} must not serialize idempotency_key in the body',
      );
    }
  }
  final encoded = jsonEncode(openApi);
  if (encoded.contains('"generate_xmp"')) {
    errors.add(
      '${openApiFile.path}: generate_xmp is not a writable v1 field; use xmp_enabled',
    );
  }
}

bool _containsKeyRecursively(Object? value, String key) {
  if (value is Map) {
    if (value.containsKey(key)) {
      return true;
    }
    return value.values.any((child) => _containsKeyRecursively(child, key));
  }
  if (value is List) {
    return value.any((child) => _containsKeyRecursively(child, key));
  }
  return false;
}

void _validateBaseline(
  Map<String, dynamic> baseline,
  List<String> errors, {
  required bool strict,
}) {
  if (baseline['contract_id'] != 'birdbox-v1' || baseline['contract_version'] != '1.0.0' || baseline['api_version'] != 'v1') {
    errors.add(
      'docs/contracts/birdbox-v1-baseline.json: contract identity must be $contractVersion / API v1',
    );
  }
  final app = baseline['app'];
  if (app is! Map || app['integration_sha'] != 'fb99f208a4e0ccba7bd8f3abd3154a6d970df92a') {
    errors.add(
      'docs/contracts/birdbox-v1-baseline.json: integration_sha must remain the verified merge baseline',
    );
  }

  final missing = _requiredExternalBaselineValues.where((path) => _isMissing(_valueAtDotPath(baseline, path))).toList();
  final declaredUnresolved = baseline['unresolved_external_inputs'];
  if (declaredUnresolved is! List) {
    errors.add(
      'docs/contracts/birdbox-v1-baseline.json: unresolved_external_inputs must be a list',
    );
  } else {
    final declared = declaredUnresolved.map((value) => value.toString()).toList();
    final declaredSet = declared.toSet();
    final missingSet = missing.toSet();
    if (declared.length != declaredSet.length || declaredSet.length != missingSet.length || !declaredSet.containsAll(missingSet)) {
      errors.add(
        'docs/contracts/birdbox-v1-baseline.json: unresolved_external_inputs must exactly match missing external baseline values',
      );
    }
  }

  final expectedStatus = missing.isEmpty ? 'ready' : 'blocked_external_inputs';
  if (baseline['status'] != expectedStatus) {
    errors.add(
      'docs/contracts/birdbox-v1-baseline.json: status must be $expectedStatus for the declared external inputs',
    );
  }

  if (!strict) {
    return;
  }
  if (baseline['status'] != 'ready') {
    errors.add(
      'strict baseline: status must be ready, got ${baseline['status']}',
    );
  }
  for (final path in missing) {
    errors.add('strict baseline: missing $path');
  }
}

Object? _valueAtDotPath(Map<String, dynamic> root, String path) {
  Object? current = root;
  for (final segment in path.split('.')) {
    if (current is! Map || !current.containsKey(segment)) {
      return null;
    }
    current = current[segment];
  }
  return current;
}

bool _isMissing(Object? value) => value == null || (value is String && value.trim().isEmpty);

void _validateFixtures({
  required Directory repositoryRoot,
  required File manifestFile,
  required Map<String, dynamic> manifest,
  required List<String> errors,
}) {
  if (manifest['contract'] != contractVersion) {
    errors.add(
      '${manifestFile.path}: contract must be $contractVersion',
    );
  }
  final consumers = manifest['consumers'];
  const requiredConsumers = <String>{
    'flutter-client',
    'mock-box',
    'real-box',
  };
  if (consumers is! List ||
      !consumers
          .map((value) => value.toString())
          .toSet()
          .containsAll(
            requiredConsumers,
          )) {
    errors.add(
      '${manifestFile.path}: fixtures must be shared by flutter-client, mock-box and real-box',
    );
  }

  final fixtures = manifest['fixtures'];
  if (fixtures is! List || fixtures.isEmpty) {
    errors.add('${manifestFile.path}: fixtures must be a non-empty list');
    return;
  }
  final validator = JsonSchemaSubsetValidator(repositoryRoot);
  final manifestDirectory = manifestFile.parent.path;

  for (final rawEntry in fixtures) {
    if (rawEntry is! Map) {
      errors.add('${manifestFile.path}: fixture entry must be an object');
      continue;
    }
    final entry = Map<String, dynamic>.from(rawEntry);
    final fixturePath = entry['file']?.toString();
    final schemaPath = entry['schema']?.toString();
    final expectedValid = entry['expected_valid'];
    if (fixturePath == null || schemaPath == null || expectedValid is! bool) {
      errors.add('${manifestFile.path}: malformed fixture entry $entry');
      continue;
    }
    final fixtureFile = File(_join(manifestDirectory, fixturePath));
    final schemaFile = File(_join(repositoryRoot.path, schemaPath));
    final instance = _readJsonValue(fixtureFile, errors);
    final schema = _readJsonValue(schemaFile, errors);
    if (instance == null || schema is! Map) {
      continue;
    }
    final validationErrors = validator.validate(
      instance,
      Map<String, dynamic>.from(schema),
      schemaFile,
    );
    if (expectedValid && validationErrors.isNotEmpty) {
      errors.add(
        '${fixtureFile.path}: expected valid, got ${validationErrors.join(' | ')}',
      );
    } else if (!expectedValid && validationErrors.isEmpty) {
      errors.add('${fixtureFile.path}: expected invalid, but validation passed');
    } else if (!expectedValid) {
      final expectedError = entry['expected_error_contains']?.toString();
      if (expectedError != null && !validationErrors.any((error) => error.contains(expectedError))) {
        errors.add(
          '${fixtureFile.path}: expected an error containing "$expectedError", got ${validationErrors.join(' | ')}',
        );
      }
    }
  }
}

void _validateVersionReferences(
  Directory repositoryRoot,
  List<String> errors,
) {
  const files = <String>[
    'docs/contracts/README.md',
    'docs/decisions/ADR-001-birdbox-v1.md',
    'docs/盒子端接口说明7.24.md',
    'lib/bird_companion/core/network/api_endpoints.dart',
    'test/contracts/README.md',
    'tool/mock_box_server/README.md',
  ];
  for (final relativePath in files) {
    final file = File(_join(repositoryRoot.path, relativePath));
    if (!file.existsSync()) {
      errors.add('missing version reference file: ${file.path}');
      continue;
    }
    if (!file.readAsStringSync().contains(contractVersion)) {
      errors.add('${file.path}: must reference $contractVersion');
    }
  }
}

Object? _readJsonValue(File file, List<String> errors) {
  if (!file.existsSync()) {
    errors.add('missing file: ${file.path}');
    return null;
  }
  try {
    return jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    errors.add('${file.path}: invalid JSON: $error');
    return null;
  }
}

final class _ReferenceAuditor {
  _ReferenceAuditor(this.errors);

  final List<String> errors;
  final Set<String> _visited = <String>{};

  void audit(Object? node, File documentFile) {
    if (node is Map) {
      final reference = node[r'$ref'];
      if (reference is String) {
        final resolved = _resolveReference(reference, documentFile, errors);
        if (resolved != null) {
          final key = '${resolved.file.absolute.path}#${resolved.fragment}';
          if (_visited.add(key)) {
            audit(resolved.schema, resolved.file);
          }
        }
      }
      for (final child in node.values) {
        audit(child, documentFile);
      }
    } else if (node is List) {
      for (final child in node) {
        audit(child, documentFile);
      }
    }
  }
}

final class JsonSchemaSubsetValidator {
  JsonSchemaSubsetValidator(this.repositoryRoot);

  final Directory repositoryRoot;

  List<String> validate(
    Object? instance,
    Map<String, dynamic> schema,
    File schemaFile,
  ) {
    return _validateNode(instance, schema, schemaFile, r'$');
  }

  List<String> _validateNode(
    Object? instance,
    Map<String, dynamic> schema,
    File schemaFile,
    String path,
  ) {
    final errors = <String>[];
    final reference = schema[r'$ref'];
    if (reference is String) {
      final resolved = _resolveReference(reference, schemaFile, errors);
      if (resolved == null) {
        return errors;
      }
      if (resolved.schema is! Map) {
        return ['$path: \$ref does not resolve to a schema object'];
      }
      return _validateNode(
        instance,
        Map<String, dynamic>.from(resolved.schema as Map),
        resolved.file,
        path,
      );
    }

    final allOf = schema['allOf'];
    if (allOf is List) {
      for (final child in allOf.whereType<Map>()) {
        errors.addAll(
          _validateNode(
            instance,
            Map<String, dynamic>.from(child),
            schemaFile,
            path,
          ),
        );
      }
    }

    final oneOf = schema['oneOf'];
    if (oneOf is List) {
      final branchErrors = oneOf
          .whereType<Map>()
          .map(
            (child) => _validateNode(
              instance,
              Map<String, dynamic>.from(child),
              schemaFile,
              path,
            ),
          )
          .toList();
      final matches = branchErrors.where((branch) => branch.isEmpty).length;
      if (matches != 1) {
        errors.add('$path: oneOf matched $matches schemas');
      }
      if (matches != 1) {
        return errors;
      }
    }

    final anyOf = schema['anyOf'];
    if (anyOf is List) {
      final matches = anyOf.whereType<Map>().where((child) {
        return _validateNode(
          instance,
          Map<String, dynamic>.from(child),
          schemaFile,
          path,
        ).isEmpty;
      }).length;
      if (matches == 0) {
        errors.add('$path: anyOf matched 0 schemas');
        return errors;
      }
    }

    if (schema.containsKey('const') && instance != schema['const']) {
      errors.add('$path: value does not equal const ${schema['const']}');
      return errors;
    }
    final enumValues = schema['enum'];
    if (enumValues is List && !enumValues.any((value) => value == instance)) {
      errors.add('$path: value is not in enum');
      return errors;
    }

    final allowedTypes = _allowedTypes(schema['type']);
    if (allowedTypes.isNotEmpty && !allowedTypes.any((type) => _matchesType(instance, type))) {
      errors.add(
        '$path: expected type ${allowedTypes.join('|')}, got ${instance.runtimeType}',
      );
      return errors;
    }

    if (instance is Map) {
      final object = Map<String, dynamic>.from(instance);
      final required = schema['required'];
      if (required is List) {
        for (final key in required.map((value) => value.toString())) {
          if (!object.containsKey(key)) {
            errors.add('$path: missing required property $key');
          }
        }
      }
      final properties = schema['properties'];
      final propertyMap = properties is Map ? Map<String, dynamic>.from(properties) : const {};
      for (final entry in object.entries) {
        final propertySchema = propertyMap[entry.key];
        if (propertySchema is Map) {
          errors.addAll(
            _validateNode(
              entry.value,
              Map<String, dynamic>.from(propertySchema),
              schemaFile,
              '$path.${entry.key}',
            ),
          );
        } else if (schema['additionalProperties'] == false) {
          errors.add('$path: additional property ${entry.key} is not allowed');
        } else if (schema['additionalProperties'] is Map) {
          errors.addAll(
            _validateNode(
              entry.value,
              Map<String, dynamic>.from(
                schema['additionalProperties'] as Map,
              ),
              schemaFile,
              '$path.${entry.key}',
            ),
          );
        }
      }
    }

    if (instance is List) {
      final minItems = schema['minItems'];
      if (minItems is num && instance.length < minItems.toInt()) {
        errors.add('$path: minItems is ${minItems.toInt()}');
      }
      if (schema['uniqueItems'] == true) {
        final encoded = instance.map(jsonEncode).toList();
        if (encoded.toSet().length != encoded.length) {
          errors.add('$path: uniqueItems violated');
        }
      }
      final itemSchema = schema['items'];
      if (itemSchema is Map) {
        for (var index = 0; index < instance.length; index += 1) {
          errors.addAll(
            _validateNode(
              instance[index],
              Map<String, dynamic>.from(itemSchema),
              schemaFile,
              '$path[$index]',
            ),
          );
        }
      }
    }

    if (instance is String) {
      final minLength = schema['minLength'];
      if (minLength is num && instance.length < minLength.toInt()) {
        errors.add('$path: minLength is ${minLength.toInt()}');
      }
      final pattern = schema['pattern'];
      if (pattern is String && !RegExp(pattern).hasMatch(instance)) {
        errors.add('$path: pattern mismatch');
      }
      final format = schema['format'];
      if (format == 'date-time' && DateTime.tryParse(instance) == null) {
        errors.add('$path: invalid date-time');
      } else if (format == 'uri') {
        final uri = Uri.tryParse(instance);
        if (uri == null || !uri.hasScheme) {
          errors.add('$path: invalid absolute URI');
        }
      }
    }

    if (instance is num) {
      final minimum = schema['minimum'];
      final maximum = schema['maximum'];
      if (minimum is num && instance < minimum) {
        errors.add('$path: value is below minimum $minimum');
      }
      if (maximum is num && instance > maximum) {
        errors.add('$path: value exceeds maximum $maximum');
      }
    }
    return errors;
  }
}

List<String> _allowedTypes(Object? rawType) {
  if (rawType is String) {
    return <String>[rawType];
  }
  if (rawType is List) {
    return rawType.map((value) => value.toString()).toList();
  }
  return const <String>[];
}

bool _matchesType(Object? value, String type) => switch (type) {
  'null' => value == null,
  'object' => value is Map,
  'array' => value is List,
  'string' => value is String,
  'integer' => value is int,
  'number' => value is num,
  'boolean' => value is bool,
  _ => false,
};

final class _ResolvedReference {
  const _ResolvedReference(this.file, this.schema, this.fragment);

  final File file;
  final Object? schema;
  final String fragment;
}

_ResolvedReference? _resolveReference(
  String reference,
  File documentFile,
  List<String> errors,
) {
  final hashIndex = reference.indexOf('#');
  final filePart = hashIndex == -1 ? reference : reference.substring(0, hashIndex);
  final fragment = hashIndex == -1 ? '' : reference.substring(hashIndex + 1);
  final targetFile = filePart.isEmpty ? documentFile : File(_join(documentFile.parent.path, filePart));
  if (!targetFile.existsSync()) {
    errors.add('${documentFile.path}: unresolved \$ref $reference');
    return null;
  }
  Object? document;
  try {
    document = jsonDecode(targetFile.readAsStringSync());
  } on FormatException catch (error) {
    errors.add('${targetFile.path}: invalid referenced JSON: $error');
    return null;
  }
  final resolved = _resolveJsonPointer(document, fragment);
  if (resolved == _missingPointer) {
    errors.add('${documentFile.path}: unresolved \$ref fragment $reference');
    return null;
  }
  return _ResolvedReference(targetFile, resolved, fragment);
}

const _missingPointer = Object();

Object? _resolveJsonPointer(Object? document, String fragment) {
  if (fragment.isEmpty) {
    return document;
  }
  if (!fragment.startsWith('/')) {
    return _missingPointer;
  }
  Object? current = document;
  for (final encoded in fragment.substring(1).split('/')) {
    final segment = Uri.decodeComponent(encoded).replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is Map && current.containsKey(segment)) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        return _missingPointer;
      }
      current = current[index];
    } else {
      return _missingPointer;
    }
  }
  return current;
}

String _join(String base, String relative) {
  final normalized = relative.replaceAll('/', Platform.pathSeparator);
  return File('$base${Platform.pathSeparator}$normalized').absolute.path;
}
