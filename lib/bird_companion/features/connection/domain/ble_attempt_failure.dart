import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

/// Optional app-local reporting for repository and page cleanup evidence.
abstract interface class BleFailureDiagnostics {
  Future<void> recordFailureDetails(ProvisioningException error);
}

/// One logical operation owns this ledger, including all of its cleanup.
/// Raw exception messages may contain a token, password or address. Keep a
/// redacted representation and only Dart source locations from the stack.
final class BleAttemptFailure {
  BleAttemptFailure({required this.attemptId, this.requestId, this.connectionGeneration, this.gattGeneration, this.traceId, this.flowId});
  final String attemptId;
  final String? requestId;
  final int? connectionGeneration;
  final int? gattGeneration;
  final String? traceId, flowId;
  ProvisioningException? _first;
  Object? _firstOriginal;
  Map<String, Object?>? _firstFact;
  final List<Map<String, Object?>> _secondary = [];
  int _secondaryCount = 0;
  static const maximumSecondaryErrors = 16;

  bool get hasFailure => _first != null;
  Map<String, Object?>? get firstTerminalError => _firstFact;

  void capture(
    Object error,
    StackTrace? stack, {
    required String method,
    required String expectedState,
    required String currentState,
    String? previousBondState,
    String? currentBondState,
    String? nativeAttemptId,
    bool secondaryOnly = false,
  }) {
    if (identical(error, _firstOriginal)) return;
    if (_firstFact != null && error is ProvisioningException && identical(error.failureDetails?['first_terminal_error'], _firstFact)) return;
    // Keep structured evidence when crossing repository/presentation boundaries.
    if (!secondaryOnly && _first == null && error is ProvisioningException && error.failureDetails?['first_terminal_error'] is Map) {
      _first = error;
      _firstOriginal = error;
      _firstFact = Map<String, Object?>.unmodifiable(error.failureDetails!['first_terminal_error'] as Map);
      final details = error.failureDetails!;
      _secondary.addAll((details['secondary_errors'] as List? ?? const []).cast<Map>().take(maximumSecondaryErrors).map(Map<String, Object?>.unmodifiable));
      _secondaryCount = details['secondary_error_count'] as int? ?? _secondary.length;
      return;
    }
    if (_first != null && error is ProvisioningException && error.failureDetails?['first_terminal_error'] is Map) {
      // A nested cleanup operation may already have normalized StateError.
      // Keep its original type and stack rather than recording the wrapper.
      final details = error.failureDetails!;
      final fact = details['first_terminal_error'] as Map;
      _appendSecondary(Map<String, Object?>.unmodifiable({...fact, 'origin_method': fact['trigger_method'], 'trigger_method': method}));
      for (final child in details['secondary_errors'] as List? ?? const []) {
        _appendSecondary(Map<String, Object?>.unmodifiable(child as Map));
      }
      _secondaryCount += details['secondary_errors_dropped'] as int? ?? 0;
      return;
    }
    final normalized = normalize(error);
    final type = error.runtimeType.toString();
    final safeType = RegExp(r'^[A-Za-z0-9_<>]+$').hasMatch(type) ? type : 'Error';
    final fact = Map<String, Object?>.unmodifiable({
      'error_code': normalized.code.wireValue,
      'runtime_type': safeType,
      'to_string': error is ProvisioningException ? error.toString() : '$safeType(<redacted>)',
      'stack_trace': [for (final match in RegExp(r'[A-Za-z0-9_]+\.dart:\d+(?::\d+)?').allMatches(stack?.toString() ?? '').take(12)) match.group(0)!].join('\n'),
      'stack_trace_available': stack != null && stack != StackTrace.empty,
      'message_redacted': error is! ProvisioningException,
      'trigger_method': method,
      'attempt_id': attemptId,
      if (requestId != null) 'request_id': requestId,
      if (connectionGeneration != null) 'connection_generation': connectionGeneration,
      if (gattGeneration != null) 'gatt_generation': gattGeneration,
      if (traceId != null) 'trace_id': traceId,
      if (flowId != null) 'flow_id': flowId,
      'expected_state': expectedState,
      'current_state': currentState,
      'previous_bond_state': ?previousBondState,
      'current_bond_state': ?currentBondState,
      'native_attempt_id': ?nativeAttemptId,
    });
    if (_first == null && !secondaryOnly) {
      _first = normalized;
      _firstOriginal = error;
      _firstFact = fact;
    } else {
      _appendSecondary(fact);
    }
  }

  void _appendSecondary(Map<String, Object?> fact) {
    _secondaryCount++;
    if (_secondary.length < maximumSecondaryErrors) _secondary.add(fact);
  }

  Map<String, Object?> toJson() => Map.unmodifiable({
    'first_terminal_error': _firstFact,
    'secondary_errors': List.unmodifiable(_secondary),
    'secondary_error_count': _secondaryCount,
    'secondary_errors_dropped': _secondaryCount - _secondary.length,
  });

  ProvisioningException get exception {
    final first = _first!;
    return ProvisioningException(code: first.code, retryable: first.retryable, retryAfter: first.retryAfter, diagnosticMessage: first.diagnosticMessage, failureDetails: toJson());
  }

  static ProvisioningException normalize(Object error) => switch (error) {
    ProvisioningException() => error,
    FormatException() => const ProvisioningException(code: ProvisioningErrorCode.bleFragmentInvalid, retryable: false),
    _ => const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true),
  };
}
