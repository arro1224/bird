package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.UUID;

import org.junit.Test;

public final class BirdBoxSecurityWriteAttemptContextTest {
    private static final UUID CHARACTERISTIC_UUID =
            UUID.fromString("6f7d0005-7a66-4c45-a1b9-5f4d2e3c1000");

    @Test
    public void callbackTimeoutWinsOnceAndRejectsLateCallback() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertTrue(context.completeFromCallbackTimeout(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
        assertEquals(
                BirdBoxSecurityWriteAttemptContext.Trigger.WRITE_CALLBACK_TIMEOUT,
                context.trigger()
        );
        assertEquals(2000L, context.elapsedMs(3000L));
        assertFalse(context.completeFromCallback(3, 7, CHARACTERISTIC_UUID, false));
        assertFalse(context.callbackReceived());
    }

    @Test
    public void timeoutCannotRunUntilWriteApiIsAccepted() {
        final BirdBoxSecurityWriteAttemptContext context = newContext();

        assertFalse(context.completeFromCallbackTimeout(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
        assertTrue(context.markApiAccepted("request-1", 3, 7, CHARACTERISTIC_UUID));
        assertTrue(context.apiAccepted());
        assertTrue(context.completeFromCallbackTimeout(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
    }

    @Test
    public void callbackBeforeApiReturnStillWinsTheAttempt() {
        final BirdBoxSecurityWriteAttemptContext context = newContext();

        assertTrue(context.completeFromCallback(3, 7, CHARACTERISTIC_UUID, false));
        assertTrue(context.apiAccepted());
        assertTrue(context.callbackReceived());
        assertTrue(context.markApiAccepted("request-1", 3, 7, CHARACTERISTIC_UUID));
        assertFalse(context.isWaitingForCallback(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
    }

    @Test
    public void callbackCancelsTimeoutEligibilityAndCapturesSecurityStatus() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertTrue(context.completeFromCallback(3, 7, CHARACTERISTIC_UUID, true));
        assertFalse(context.completeFromCallbackTimeout(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
        assertTrue(context.callbackReceived());
        assertEquals(
                BirdBoxSecurityWriteAttemptContext.Trigger.EXPLICIT_GATT_SECURITY_STATUS,
                context.trigger()
        );
    }

    @Test
    public void staleConnectionAndGattGenerationCannotCompleteAttempt() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertFalse(context.completeFromCallback(2, 7, CHARACTERISTIC_UUID, false));
        assertFalse(context.completeFromCallback(3, 6, CHARACTERISTIC_UUID, false));
        assertFalse(context.completeFromCallbackTimeout(
                "request-stale",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
        assertTrue(context.completeFromCallback(3, 7, CHARACTERISTIC_UUID, false));
    }

    @Test
    public void systemBondStateReleasesAcceptedAttempt() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertTrue(context.completeFromSystemBondState(3, 7));
        assertEquals(
                BirdBoxSecurityWriteAttemptContext.Trigger.SYSTEM_BOND_STATE_OBSERVED,
                context.trigger()
        );
        assertFalse(context.completeFromCallback(3, 7, CHARACTERISTIC_UUID, false));
    }

    @Test
    public void callbackTimeoutCanOwnFallbackOnlyOnce() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertTrue(context.completeFromCallbackTimeout(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
        assertTrue(context.tryMarkFallbackStarted());
        assertFalse(context.tryMarkFallbackStarted());
    }

    @Test
    public void transportSecurityStatusPreservesExplicitFallbackTrigger() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertTrue(context.completeFromGattSecurityStatus(3, 7));
        assertFalse(context.callbackReceived());
        assertEquals(
                BirdBoxSecurityWriteAttemptContext.Trigger.EXPLICIT_GATT_SECURITY_STATUS,
                context.trigger()
        );
    }

    @Test
    public void diagnosticsDescribeAttemptWithoutRetainingPayload() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertTrue(context.completeFromCallbackTimeout(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
        context.recordTriggerBondState("not_bonded");
        context.recordCreateBond(true, "bonding", "bonded");
        context.recordStateTransition("bonding", "bonded_recovering_gatt");
        context.markTerminal("success");
        context.markCleanup("complete");

        assertEquals("request-1:3:7:1000", context.attemptId());
        assertEquals(3, context.connectionGeneration());
        assertEquals(7, context.gattGeneration());
        assertEquals("not_bonded", context.bondStateAtTrigger());
        assertTrue(context.createBondInvoked());
        assertEquals(Boolean.TRUE, context.createBondReturned());
        assertEquals("bonding", context.stateBefore());
        assertEquals("bonded_recovering_gatt", context.stateAfter());
        assertEquals("success", context.terminalOutcome());
        assertEquals("complete", context.cleanupOutcome());
    }

    @Test
    public void createBondInvocationIsRetainedWhenTheFrameworkThrows() {
        final BirdBoxSecurityWriteAttemptContext context = acceptedContext();

        assertTrue(context.completeFromCallbackTimeout(
                "request-1",
                3,
                7,
                CHARACTERISTIC_UUID
        ));
        context.recordCreateBondInvoked("not_bonded");
        context.recordCreateBondException("SecurityException", "not_bonded");

        assertTrue(context.createBondInvoked());
        assertEquals("not_bonded", context.createBondStateBefore());
        assertEquals("not_bonded", context.createBondStateAfter());
        assertEquals("SecurityException", context.createBondException());
        assertFalse(context.createBondReturned() != null);
    }

    private static BirdBoxSecurityWriteAttemptContext acceptedContext() {
        final BirdBoxSecurityWriteAttemptContext context = newContext();
        context.markApiAccepted("request-1", 3, 7, CHARACTERISTIC_UUID);
        return context;
    }

    private static BirdBoxSecurityWriteAttemptContext newContext() {
        final BirdBoxSecurityWriteAttemptContext context =
                new BirdBoxSecurityWriteAttemptContext();
        context.begin("request-1", 3, 7, CHARACTERISTIC_UUID, 1000L);
        return context;
    }
}
