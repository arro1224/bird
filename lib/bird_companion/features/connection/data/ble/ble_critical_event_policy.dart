/// Evidence needed to distinguish system bond, GATT, ATT and business failures.
final class BleCriticalEventPolicy {
  static bool isCritical(Map record) => events.contains(record['event_type']) || record['error_code'] != null || record['terminal_outcome'] != null;

  // Request ID joins Dart events to native attempts and their write children.
  static String? requestKey(Map record, String flow) {
    final id = record['request_id'] ?? record['attempt_id'];
    return id == null ? null : '$flow\u0000$id';
  }

  static const events = {
    'command_started', 'command_succeeded', 'command_failed',
    'user_start_pairing', 'bond_receiver_registered',
    'system_bond_starting', 'system_bond_started', 'system_bond_result', 'bond_state_changed',
    'create_bond_invoked', 'create_bond_returned', 'create_bond_exception',
    'security_write_begin', 'security_old_timers_cancelled', 'security_preparation_failed',
    'gatt_rebuild_started', 'gatt_rebuild_completed', 'gatt_disconnect_requested', 'gatt_disconnected',
    'gatt_connection_state_changed', 'gatt_services_discovered', 'gatt_mtu_changed',
    'gatt_service_discovery_api_invoked', 'gatt_service_discovery_api_returned',
    'gatt_service_discovery_api_exception', 'gatt_service_discovery_timeout',
    'gatt_service_discovery_wait_started', 'gatt_service_discovery_callback_ignored',
    'gatt_service_validation_failed', 'gatt_old_disconnect_confirmed', 'gatt_old_disconnect_timeout', 'gatt_disconnect_settle_started',
    'gatt_mtu_barrier_started', 'gatt_mtu_barrier_api_returned', 'gatt_mtu_barrier_timeout',
    'gatt_old_client_close_deferred', 'gatt_old_client_close_requested',
    'gatt_legacy_registration_retained', 'gatt_legacy_registration_limit',
    'gatt_notification_descriptor_write', 'notifications_ready',
    'security_write_started', 'security_write_api_invoked', 'security_write_callback_received', 'security_write_callback_timeout',
    'security_write_retry_started', 'security_write_retry_result', 'security_write_retrying',
    'security_recovery_started', 'security_recovery_completed', 'security_recovery_failed',
    'security_write_result', 'security_write_completed', 'security_write_terminal',
    'security_write_fact_finalized', 'security_write_cleanup_completed', 'security_cleanup_failed',
    'teardown_started', 'teardown_completed', 'disconnected',
    'ble_host_detached', 'ble_host_attached', 'ble_engine_session_ended',
  };
}
