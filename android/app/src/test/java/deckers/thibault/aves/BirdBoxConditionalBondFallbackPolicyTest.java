package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class BirdBoxConditionalBondFallbackPolicyTest {
    @Test
    public void explicitSecurityStatusArmsTwoSecondGraceThenStartsOnce() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-1", 3);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.WAIT_FOR_SYSTEM,
                arm(policy, "request-1", 3, 1000L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
        assertEquals(3000L, policy.dueAtMs());
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.WAIT_FOR_SYSTEM,
                evaluate(policy, "request-1", 3, 2999L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.START_CONDITIONAL_FALLBACK,
                evaluate(policy, "request-1", 3, 3000L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
        assertTrue(policy.attempted());
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.INELIGIBLE,
                evaluate(policy, "request-1", 3, 5000L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
    }

    @Test
    public void missingSecurityTriggerNeverArms() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-2", 4);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.INELIGIBLE,
                arm(policy, "request-2", 4, 1000L,
                        BirdBoxSecurityWriteAttemptContext.Trigger.NONE, false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
        assertEquals(-1L, policy.dueAtMs());
        assertFalse(policy.attempted());
    }

    @Test
    public void callbackTimeoutStartsFallbackImmediatelyAndOnlyOnce() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-timeout", 4);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.START_CONDITIONAL_FALLBACK,
                policy.arm(
                        "request-timeout",
                        4,
                        3000L,
                        false,
                        true,
                        BirdBoxSecurityWriteAttemptContext.Trigger.WRITE_CALLBACK_TIMEOUT,
                        false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE
                )
        );
        assertTrue(policy.attempted());
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.INELIGIBLE,
                policy.evaluate(
                        "request-timeout",
                        4,
                        5000L,
                        true,
                        true,
                        BirdBoxSecurityWriteAttemptContext.Trigger.WRITE_CALLBACK_TIMEOUT,
                        false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE
                )
        );
    }

    @Test
    public void systemBondingBeforeDeadlineCancelsFallback() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-3", 5);
        arm(policy, "request-3", 5, 1000L, explicitGattStatus(), false,
                BirdBoxConditionalBondFallbackPolicy.BondState.NONE);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.OBSERVE_SYSTEM_BONDING,
                evaluate(policy, "request-3", 5, 1500L, explicitGattStatus(), true,
                        BirdBoxConditionalBondFallbackPolicy.BondState.BONDING)
        );
        assertEquals(-1L, policy.dueAtMs());
        assertFalse(policy.attempted());
    }

    @Test
    public void systemBondTriggerIsEligibleBeforeRecoveryCallStarts() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-system", 5);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.OBSERVE_SYSTEM_BONDING,
                policy.arm(
                        "request-system",
                        5,
                        1500L,
                        false,
                        true,
                        BirdBoxSecurityWriteAttemptContext.Trigger.SYSTEM_BOND_STATE_OBSERVED,
                        true,
                        BirdBoxConditionalBondFallbackPolicy.BondState.BONDING
                )
        );
        assertFalse(policy.attempted());
    }

    @Test
    public void bondedBeforeDeadlineGoesDirectlyToRecovery() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-4", 6);
        arm(policy, "request-4", 6, 1000L, explicitGattStatus(), false,
                BirdBoxConditionalBondFallbackPolicy.BondState.NONE);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.RECOVER_BONDED,
                evaluate(policy, "request-4", 6, 1500L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.BONDED)
        );
        assertFalse(policy.attempted());
    }

    @Test
    public void staleRequestAndConnectionGenerationCannotTriggerFallback() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-5", 7);
        arm(policy, "request-5", 7, 1000L, explicitGattStatus(), false,
                BirdBoxConditionalBondFallbackPolicy.BondState.NONE);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.INELIGIBLE,
                evaluate(policy, "request-stale", 7, 3000L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.INELIGIBLE,
                evaluate(policy, "request-5", 8, 3000L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
        assertFalse(policy.attempted());
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.START_CONDITIONAL_FALLBACK,
                evaluate(policy, "request-5", 7, 3000L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
    }

    @Test
    public void teardownOrWrongSecurityPhaseMakesCallbackIneligible() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-6", 9);
        arm(policy, "request-6", 9, 1000L, explicitGattStatus(), false,
                BirdBoxConditionalBondFallbackPolicy.BondState.NONE);

        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.INELIGIBLE,
                policy.evaluate(
                        "request-6",
                        9,
                        3000L,
                        false,
                        true,
                        explicitGattStatus(),
                        false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE
                )
        );
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.INELIGIBLE,
                policy.evaluate(
                        "request-6",
                        9,
                        3000L,
                        true,
                        false,
                        explicitGattStatus(),
                        false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE
                )
        );
        assertFalse(policy.attempted());
    }

    @Test
    public void newRequestResetAllowsOneNewAttempt() {
        final BirdBoxConditionalBondFallbackPolicy policy = readyPolicy("request-old", 10);
        arm(policy, "request-old", 10, 0L, explicitGattStatus(), false,
                BirdBoxConditionalBondFallbackPolicy.BondState.NONE);
        evaluate(policy, "request-old", 10, 2000L, explicitGattStatus(), false,
                BirdBoxConditionalBondFallbackPolicy.BondState.NONE);
        assertTrue(policy.attempted());

        policy.begin("request-new", 11);

        assertFalse(policy.attempted());
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.WAIT_FOR_SYSTEM,
                arm(policy, "request-new", 11, 5000L, explicitGattStatus(), false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE)
        );
    }

    private static BirdBoxConditionalBondFallbackPolicy readyPolicy(
            String requestId,
            int generation) {
        final BirdBoxConditionalBondFallbackPolicy policy =
                new BirdBoxConditionalBondFallbackPolicy();
        policy.begin(requestId, generation);
        return policy;
    }

    private static BirdBoxConditionalBondFallbackPolicy.Decision arm(
            BirdBoxConditionalBondFallbackPolicy policy,
            String requestId,
            int generation,
            long nowMs,
            BirdBoxSecurityWriteAttemptContext.Trigger trigger,
            boolean bondingObserved,
            BirdBoxConditionalBondFallbackPolicy.BondState bondState) {
        return policy.arm(
                requestId,
                generation,
                nowMs,
                true,
                true,
                trigger,
                bondingObserved,
                bondState
        );
    }

    private static BirdBoxConditionalBondFallbackPolicy.Decision evaluate(
            BirdBoxConditionalBondFallbackPolicy policy,
            String requestId,
            int generation,
            long nowMs,
            BirdBoxSecurityWriteAttemptContext.Trigger trigger,
            boolean bondingObserved,
            BirdBoxConditionalBondFallbackPolicy.BondState bondState) {
        return policy.evaluate(
                requestId,
                generation,
                nowMs,
                true,
                true,
                trigger,
                bondingObserved,
                bondState
        );
    }

    private static BirdBoxSecurityWriteAttemptContext.Trigger explicitGattStatus() {
        return BirdBoxSecurityWriteAttemptContext.Trigger.EXPLICIT_GATT_SECURITY_STATUS;
    }
}
