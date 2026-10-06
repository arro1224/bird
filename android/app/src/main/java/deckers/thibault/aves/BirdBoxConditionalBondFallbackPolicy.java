package deckers.thibault.aves;

import java.util.Objects;

/**
 * Framework-free timing and eligibility policy for the one-shot post-write Bond fallback.
 *
 * <p>The Android bridge owns all Bluetooth side effects. This class only decides whether a
 * request should keep waiting for system pairing, recover an already-changing Bond state, or
 * perform the single compatibility fallback after the grace period.</p>
 */
final class BirdBoxConditionalBondFallbackPolicy {
    static final long GRACE_PERIOD_MS = 2000L;

    enum BondState {
        NONE,
        BONDING,
        BONDED,
        UNKNOWN
    }

    enum Decision {
        INELIGIBLE,
        WAIT_FOR_SYSTEM,
        OBSERVE_SYSTEM_BONDING,
        RECOVER_BONDED,
        START_CONDITIONAL_FALLBACK
    }

    private String requestId;
    private int connectionGeneration = -1;
    private boolean armed;
    private boolean attempted;
    private long dueAtMs = -1L;

    void begin(String nextRequestId, int nextConnectionGeneration) {
        if (nextRequestId == null || nextRequestId.isEmpty()) {
            throw new IllegalArgumentException("requestId must not be empty");
        }
        requestId = nextRequestId;
        connectionGeneration = nextConnectionGeneration;
        armed = false;
        attempted = false;
        dueAtMs = -1L;
    }

    Decision arm(
            String activeRequestId,
            int activeConnectionGeneration,
            long nowMs,
            boolean securityRecoveryPending,
            boolean securityPhaseEligible,
            BirdBoxSecurityWriteAttemptContext.Trigger trigger,
            boolean bondingObserved,
            BondState bondState) {
        final Decision immediate = immediateDecision(
                activeRequestId,
                activeConnectionGeneration,
                securityRecoveryPending,
                securityPhaseEligible,
                trigger,
                bondingObserved,
                bondState
        );
        if (immediate != Decision.WAIT_FOR_SYSTEM) {
            if (immediate == Decision.START_CONDITIONAL_FALLBACK) {
                if (attempted) return Decision.INELIGIBLE;
                attempted = true;
            }
            if (immediate == Decision.OBSERVE_SYSTEM_BONDING
                    || immediate == Decision.RECOVER_BONDED
                    || immediate == Decision.START_CONDITIONAL_FALLBACK) {
                cancelPending();
            }
            return immediate;
        }
        if (attempted) return Decision.INELIGIBLE;
        if (!armed) {
            armed = true;
            dueAtMs = nowMs + GRACE_PERIOD_MS;
        }
        return Decision.WAIT_FOR_SYSTEM;
    }

    Decision evaluate(
            String activeRequestId,
            int activeConnectionGeneration,
            long nowMs,
            boolean securityRecoveryPending,
            boolean securityPhaseEligible,
            BirdBoxSecurityWriteAttemptContext.Trigger trigger,
            boolean bondingObserved,
            BondState bondState) {
        final Decision immediate = immediateDecision(
                activeRequestId,
                activeConnectionGeneration,
                securityRecoveryPending,
                securityPhaseEligible,
                trigger,
                bondingObserved,
                bondState
        );
        if (immediate != Decision.WAIT_FOR_SYSTEM) {
            if (immediate == Decision.START_CONDITIONAL_FALLBACK) {
                if (attempted) return Decision.INELIGIBLE;
                attempted = true;
            }
            if (sameSession(activeRequestId, activeConnectionGeneration)) {
                cancelPending();
            }
            return immediate;
        }
        if (!armed || attempted || nowMs < dueAtMs) {
            return armed && !attempted
                    ? Decision.WAIT_FOR_SYSTEM
                    : Decision.INELIGIBLE;
        }
        armed = false;
        attempted = true;
        dueAtMs = -1L;
        return Decision.START_CONDITIONAL_FALLBACK;
    }

    long dueAtMs() {
        return dueAtMs;
    }

    boolean attempted() {
        return attempted;
    }

    void cancelPending() {
        armed = false;
        dueAtMs = -1L;
    }

    void reset() {
        requestId = null;
        connectionGeneration = -1;
        armed = false;
        attempted = false;
        dueAtMs = -1L;
    }

    private Decision immediateDecision(
            String activeRequestId,
            int activeConnectionGeneration,
            boolean securityRecoveryPending,
            boolean securityPhaseEligible,
            BirdBoxSecurityWriteAttemptContext.Trigger trigger,
            boolean bondingObserved,
            BondState bondState) {
        if (!sameSession(activeRequestId, activeConnectionGeneration)
                || !securityPhaseEligible
                || trigger == null
                || trigger == BirdBoxSecurityWriteAttemptContext.Trigger.NONE) {
            return Decision.INELIGIBLE;
        }
        if (bondState == BondState.BONDED) return Decision.RECOVER_BONDED;
        if (bondingObserved || bondState == BondState.BONDING) {
            return Decision.OBSERVE_SYSTEM_BONDING;
        }
        if (bondState != BondState.NONE) return Decision.INELIGIBLE;
        if (trigger == BirdBoxSecurityWriteAttemptContext.Trigger.WRITE_CALLBACK_TIMEOUT) {
            return Decision.START_CONDITIONAL_FALLBACK;
        }
        return securityRecoveryPending
                && trigger
                == BirdBoxSecurityWriteAttemptContext.Trigger.EXPLICIT_GATT_SECURITY_STATUS
                ? Decision.WAIT_FOR_SYSTEM
                : Decision.INELIGIBLE;
    }

    private boolean sameSession(String activeRequestId, int activeConnectionGeneration) {
        return Objects.equals(requestId, activeRequestId)
                && connectionGeneration == activeConnectionGeneration;
    }
}
