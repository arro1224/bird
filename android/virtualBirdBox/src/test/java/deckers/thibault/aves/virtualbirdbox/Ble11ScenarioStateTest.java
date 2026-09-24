package deckers.thibault.aves.virtualbirdbox;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class Ble11ScenarioStateTest {
    @Test
    public void fallbackRejectsFirstMessageAndAcceptsOnlyAfterBond() {
        final Ble11ScenarioState state = new Ble11ScenarioState(
                Ble11ScenarioState.Scenario.FALLBACK_ONCE
        );
        assertEquals(Ble11ScenarioState.Action.REJECT_SECURITY, state.onCompleteMessage(false));
        assertEquals(Ble11ScenarioState.Action.REJECT_SECURITY, state.onCompleteMessage(false));
        assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onCompleteMessage(true));
        assertTrue(state.injected());
        assertFalse(state.requiresEncryptedPermission());
    }

    @Test
    public void disconnectFaultIsConsumedOnce() {
        final Ble11ScenarioState state = new Ble11ScenarioState(
                Ble11ScenarioState.Scenario.DISCONNECT_ONCE
        );
        assertEquals(Ble11ScenarioState.Action.DISCONNECT, state.onCompleteMessage(false));
        assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onCompleteMessage(false));
    }

    @Test
    public void autoBondUsesEncryptedWritePermissionWithoutSyntheticFault() {
        final Ble11ScenarioState state = new Ble11ScenarioState(
                Ble11ScenarioState.Scenario.AUTO_BOND
        );
        assertTrue(state.requiresEncryptedPermission());
        assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onCompleteMessage(false));
        assertFalse(state.injected());
    }

    @Test
    public void parsesOnlyTheAuditedScenarioNames() {
        assertEquals(
                Ble11ScenarioState.Scenario.FALLBACK_ONCE,
                Ble11ScenarioState.Scenario.parse("fallback_once")
        );
        org.junit.Assert.assertThrows(
                IllegalArgumentException.class,
                () -> Ble11ScenarioState.Scenario.parse("hardware_verified")
        );
    }
}
