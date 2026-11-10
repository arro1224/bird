import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';

/// v10 问题 9：华为"盒子有 bond、手机无 bond"场景下，系统配对可能在配对
/// 预检之前由 GATT 加密流程自行发起。此时 bond 消失不能归因为用户拒绝。
///
/// 只有 App 确实发起过预检并收到结果，或原生层有主动 `createBond` 证据时，
/// 才允许把 bond 消失归类为用户拒绝；否则按绑定丢失（可重试）处理。
final class BlePairingEvidence {
  const BlePairingEvidence({
    required this.preflightRequested,
    required this.preflightResultReceived,
    required this.createBondInvoked,
  });

  final bool preflightRequested;
  final bool preflightResultReceived;
  final bool createBondInvoked;

  bool get attributableToUserRejection =>
      createBondInvoked || (preflightRequested && preflightResultReceived);

  ProvisioningErrorCode get bondDisappearedCode =>
      attributableToUserRejection ? ProvisioningErrorCode.blePairingRejected : ProvisioningErrorCode.bleBondLost;

  String get bondDisappearedDiagnostic => attributableToUserRejection
      ? 'bond_removed_after_preflight_exchange'
      : 'bond_disappeared_before_preflight_without_rejection_evidence';
}
