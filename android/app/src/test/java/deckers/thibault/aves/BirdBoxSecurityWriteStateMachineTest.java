package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class BirdBoxSecurityWriteStateMachineTest {
    @Test
    public void firstEncryptedWriteCanCompleteWithoutPairingOrRetry() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(1L);

        machine.beginSecurityWrite("request-1", 1L);
        machine.onWriteSucceeded();

        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.WAITING_RESPONSE, machine.phase());
        assertEquals(0, machine.encryptedRetryCount());
        assertTrue(machine.onResponse("request-1"));
        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.COMPLETED, machine.phase());
    }

    @Test
    public void earlyBondingCallbackIsAcceptedBeforeWriteCallback() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(4L);

        machine.beginSecurityWrite("request-early", 4L);
        machine.onBonding();
        machine.onSecurityRequired();
        machine.onBonded(true);
        machine.onNotificationsRestored();
        machine.onWriteSucceeded();

        assertEquals(1, machine.encryptedRetryCount());
        assertTrue(machine.onResponse("request-early"));
    }

    @Test
    public void disconnectedGattMustAdvanceGenerationBeforeExactRetry() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(9L);

        machine.beginSecurityWrite("request-recover", 9L);
        machine.onSecurityRequired();
        machine.onBonded(false);
        assertFalse(machine.acceptsGattCallback(8L));
        assertThrows(IllegalArgumentException.class, () -> machine.onGattRecovered(9L));

        machine.onGattRecovered(10L);
        assertFalse(machine.acceptsGattCallback(9L));
        assertTrue(machine.acceptsGattCallback(10L));
        machine.onNotificationsRestored();
        machine.onWriteSucceeded();
        assertEquals(1, machine.encryptedRetryCount());
    }

    @Test
    public void encryptedRetryCannotStartASecondRecoveryCycle() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(2L);

        machine.beginSecurityWrite("request-retry", 2L);
        machine.onSecurityRequired();
        machine.onBonded(true);
        machine.onNotificationsRestored();
        machine.onSecurityRequired();

        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.FAILED, machine.phase());
        assertEquals(
                BirdBoxSecurityWriteStateMachine.Failure.ENCRYPTED_RETRY_FAILED,
                machine.failure()
        );
        assertEquals(1, machine.encryptedRetryCount());
    }

    @Test
    public void mismatchedResponseDoesNotCompleteTheRequest() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(3L);

        machine.beginSecurityWrite("request-active", 3L);
        machine.onWriteSucceeded();

        assertFalse(machine.onResponse("request-stale"));
        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.WAITING_RESPONSE, machine.phase());
        assertTrue(machine.onResponse("request-active"));
    }

    @Test
    public void doubleStartAndGattReplacementAreRejectedWhileActive() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(5L);

        machine.beginSecurityWrite("request-active", 5L);

        assertThrows(
                IllegalStateException.class,
                () -> machine.beginSecurityWrite("request-second", 5L)
        );
        assertThrows(
                IllegalStateException.class,
                () -> machine.markGattReady(6L)
        );
        machine.onPairingNotStartedTimeout();
        assertEquals(
                BirdBoxSecurityWriteStateMachine.Failure.LE_PAIRING_NOT_STARTED,
                machine.failure()
        );
    }

    @Test
    public void notReadyAndPairingRejectionUseDistinctFailures() {
        final BirdBoxSecurityWriteStateMachine notReady = new BirdBoxSecurityWriteStateMachine();
        notReady.beginSecurityWrite("request", 1L);
        assertEquals(BirdBoxSecurityWriteStateMachine.Failure.GATT_NOT_READY, notReady.failure());

        final BirdBoxSecurityWriteStateMachine rejected = readyMachine(7L);
        rejected.beginSecurityWrite("request", 7L);
        rejected.onBonding();
        rejected.onPairingRejected();
        assertEquals(BirdBoxSecurityWriteStateMachine.Failure.PAIRING_REJECTED, rejected.failure());
    }

    @Test
    public void responseTimeoutIsSeparateFromPairingStartTimeout() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(11L);

        machine.beginSecurityWrite("request-timeout", 11L);
        machine.onWriteSucceeded();
        machine.onResponseTimeout();

        assertEquals(BirdBoxSecurityWriteStateMachine.Failure.PAIRING_OPEN_TIMEOUT, machine.failure());
    }

    @Test
    public void lateSecurityCallbackAndDuplicateBondDoNotRewindRecovery() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(12L);

        machine.beginSecurityWrite("request-race", 12L);
        machine.onBonding();
        machine.onBonded(false);
        machine.onSecurityRequired();
        machine.onBonded(false);

        assertEquals(
                BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT,
                machine.phase()
        );
        assertEquals("request-race", machine.requestId());
    }

    @Test
    public void retryTransportFailureUsesDedicatedFailure() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(13L);

        machine.beginSecurityWrite("request-retry-failure", 13L);
        machine.onSecurityRequired();
        machine.onBonded(true);
        machine.onNotificationsRestored();
        machine.onEncryptedRetryFailed();

        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.FAILED, machine.phase());
        assertEquals(
                BirdBoxSecurityWriteStateMachine.Failure.ENCRYPTED_RETRY_FAILED,
                machine.failure()
        );
    }

    @Test
    public void gattCanDropAfterBondBeforeRecoveryStarts() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(14L);

        machine.beginSecurityWrite("request-drop", 14L);
        machine.onBonded(true);
        machine.onGattLostAfterBond();
        machine.onGattRecovered(15L);

        assertEquals(
                BirdBoxSecurityWriteStateMachine.Phase.RESTORING_NOTIFICATIONS,
                machine.phase()
        );
    }

    @Test
    public void conditionalBondFallbackRequiresARealSecurityTrigger() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(16L);

        machine.beginSecurityWrite("request-fallback-guard", 16L);

        assertThrows(
                IllegalStateException.class,
                machine::tryMarkConditionalBondFallbackAttempted
        );
        assertFalse(machine.conditionalBondFallbackAttempted());
    }

    @Test
    public void conditionalBondFallbackCanRunOnlyOnceBeforeExactRetry() {
        final BirdBoxSecurityWriteStateMachine machine = readyMachine(17L);

        machine.beginSecurityWrite("request-fallback-once", 17L);
        machine.onSecurityRequired();

        assertTrue(machine.tryMarkConditionalBondFallbackAttempted());
        assertFalse(machine.tryMarkConditionalBondFallbackAttempted());
        assertTrue(machine.conditionalBondFallbackAttempted());

        machine.onBonded(true);
        machine.onNotificationsRestored();
        machine.onWriteSucceeded();

        assertEquals(1, machine.encryptedRetryCount());
        assertTrue(machine.onResponse("request-fallback-once"));
    }

    private static BirdBoxSecurityWriteStateMachine readyMachine(long generation) {
        final BirdBoxSecurityWriteStateMachine machine = new BirdBoxSecurityWriteStateMachine();
        machine.markGattReady(generation);
        return machine;
    }
}
