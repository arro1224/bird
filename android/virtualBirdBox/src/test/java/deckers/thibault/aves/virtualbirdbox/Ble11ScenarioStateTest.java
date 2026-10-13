package deckers.thibault.aves.virtualbirdbox;
import static org.junit.Assert.*;
import org.junit.Test;

public final class Ble11ScenarioStateTest {
    @Test public void allScenariosRequireEncryptedWrites() {
        for (Ble11ScenarioState.Scenario scenario : Ble11ScenarioState.Scenario.values())
            assertTrue(new Ble11ScenarioState(scenario).requiresEncryptedPermission());
    }
    @Test public void authFaultRequiresBondAndTargetsOnlyTheChosenCharacteristicAndFragment() {
        Ble11ScenarioState state = new Ble11ScenarioState(Ble11ScenarioState.Scenario.AUTH_ONCE,
                new Ble11ScenarioState.Fault("6f7d0004", Ble11ScenarioState.Position.INDEX, 3, 15, 40, 100));
        assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onFragment("6f7d0005", 2, 5, true));
        assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onFragment("6f7d0004", 1, 5, true));
        assertEquals(Ble11ScenarioState.Action.REJECT_SECURITY, state.onFragment("6f7d0004", 2, 5, true));
        assertEquals(Ble11ScenarioState.Action.REJECT_SECURITY, state.onFragment("6f7d0004", 2, 5, true));
        assertEquals(1, state.faultRoundCount());
        state.onGattDisconnected();
        assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onFragment("6f7d0004", 2, 3, true));
        assertEquals(2, state.faultCount());
    }
    @Test public void persistentAuthFaultContinuesAcrossRebuild() {
        Ble11ScenarioState state = new Ble11ScenarioState(Ble11ScenarioState.Scenario.AUTH_PERSISTENT);
        for (int attempt = 0; attempt < 2; attempt++) {
            assertEquals(Ble11ScenarioState.Action.REJECT_SECURITY, state.onFragment("6f7d0005", 0, 5, true));
            state.onGattDisconnected();
        }
        assertEquals(2, state.faultCount());
        assertEquals(2, state.faultRoundCount());
    }
    @Test public void omissionTargetsFirstMiddleAndLastBeforeMessageCompletion() {
        for (Ble11ScenarioState.Scenario scenario : new Ble11ScenarioState.Scenario[]{
                Ble11ScenarioState.Scenario.ATT_TIMEOUT_FIRST, Ble11ScenarioState.Scenario.ATT_TIMEOUT_MIDDLE,
                Ble11ScenarioState.Scenario.ATT_TIMEOUT_LAST}) {
            Ble11ScenarioState state = new Ble11ScenarioState(scenario);
            int omissions = 0;
            for (int index = 0; index < 5; index++)
                if (state.onFragment("6f7d0005", index, 5, true) == Ble11ScenarioState.Action.IGNORE_ATT) omissions++;
            assertEquals(1, omissions);
            assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onFragment("6f7d0005", 0, 3, true));
        }
    }
    @Test public void unbondedCallsCannotConsumeThePostBondFault() {
        Ble11ScenarioState state = new Ble11ScenarioState(Ble11ScenarioState.Scenario.AUTH_ONCE);
        assertEquals(Ble11ScenarioState.Action.REJECT_SECURITY, state.onFragment("6f7d0005", 0, 2, false));
        assertFalse(state.injected());
        assertEquals(Ble11ScenarioState.Action.REJECT_SECURITY, state.onFragment("6f7d0005", 0, 2, true));
    }
    @Test public void disconnectIsConsumedOnceAndNotificationFailureTargetsSecondCccd() {
        Ble11ScenarioState state = new Ble11ScenarioState(Ble11ScenarioState.Scenario.DISCONNECT_ONCE);
        assertEquals(Ble11ScenarioState.Action.DISCONNECT, state.onFragment("6f7d0005", 0, 5, true));
        assertEquals(Ble11ScenarioState.Action.ACCEPT, state.onFragment("6f7d0005", 0, 5, true));
        state = new Ble11ScenarioState(Ble11ScenarioState.Scenario.NOTIFICATION_FAILURE);
        assertFalse(state.rejectNotification("6f7d0003"));
        assertFalse(state.rejectNotification("6f7d0006"));
        state.onGattNotificationsRestored();
        assertFalse(state.rejectNotification("6f7d0003"));
        assertTrue(state.rejectNotification("6f7d0006"));
    }
    @Test public void invalidFaultArgumentsAndUnknownScenariosAreRejected() {
        assertThrows(IllegalArgumentException.class, () -> Ble11ScenarioState.Scenario.parse("hardware_verified"));
        assertThrows(IllegalArgumentException.class, () -> new Ble11ScenarioState.Fault("invalid", Ble11ScenarioState.Position.FIRST, 1, 5, 0, 80));
        assertThrows(IllegalArgumentException.class, () -> new Ble11ScenarioState.Fault("6f7d0005", Ble11ScenarioState.Position.INDEX, 0, 5, 0, 80));
    }
}
