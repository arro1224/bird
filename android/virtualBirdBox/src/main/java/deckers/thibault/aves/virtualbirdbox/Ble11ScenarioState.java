package deckers.thibault.aves.virtualbirdbox;

import java.util.Locale;

/** Fault decisions precede reassembly and remain separate from business responses. */
final class Ble11ScenarioState {
    enum Scenario {
        SUCCESS, AUTO_BOND, FALLBACK_ONCE, // Legacy launch aliases; new evidence is always schema 2.
        BOND_FIRST, ALREADY_BONDED, AUTH_ONCE, AUTH_PERSISTENT,
        ATT_TIMEOUT_FIRST, ATT_TIMEOUT_MIDDLE, ATT_TIMEOUT_LAST,
        NOTIFICATION_FAILURE, DISCONNECT_ONCE, RESPONSE_DELAY, RESPONSE_WRONG,
        RESPONSE_DUPLICATE, BUSINESS_TIMEOUT;
        static Scenario parse(String value) {
            if (value == null) return BOND_FIRST;
            try { return valueOf(value.trim().toUpperCase(Locale.ROOT)); }
            catch (IllegalArgumentException error) { throw new IllegalArgumentException("Unsupported virtual BirdBox scenario: " + value); }
        }
        String wireValue() { return name().toLowerCase(Locale.ROOT); }
    }
    enum Action { ACCEPT, REJECT_SECURITY, IGNORE_ATT, DISCONNECT }
    enum Position { FIRST, MIDDLE, LAST, INDEX }
    static final String COMMAND_CHARACTERISTIC = "6f7d0005";
    static final class Fault {
        final String characteristic;
        final Position position;
        final int fragmentIndex, status, attDelayMs, responseDelayMs;
        Fault(String characteristic, Position position, int fragmentIndex, int status, int attDelayMs, int responseDelayMs) {
            if (!characteristic.equals(COMMAND_CHARACTERISTIC) && !characteristic.equals("6f7d0004")) throw new IllegalArgumentException("fault characteristic");
            if (fragmentIndex < 1 || fragmentIndex > 256 || (status != 5 && status != 15) || attDelayMs < 0 || attDelayMs > 60000 || responseDelayMs < 0 || responseDelayMs > 60000) throw new IllegalArgumentException("fault limits");
            this.characteristic = characteristic; this.position = position; this.fragmentIndex = fragmentIndex;
            this.status = status; this.attDelayMs = attDelayMs; this.responseDelayMs = responseDelayMs;
        }
        boolean matches(String uuid, int index, int count) {
            int target = switch (position) { case FIRST -> 1; case MIDDLE -> (count + 1) / 2; case LAST -> count; case INDEX -> fragmentIndex; };
            return characteristic.equals(uuid) && index + 1 == target;
        }
    }
    private final Scenario scenario;
    private final Fault fault;
    private boolean injected;
    private int faultCount;
    private int gattEpoch, lastFaultEpoch = -1, faultRoundCount;
    void onGattDisconnected() { gattEpoch++; }
    private boolean initialNotificationsEstablished;
    void onGattNotificationsRestored() { gattEpoch++; initialNotificationsEstablished = true; }
    int faultRoundCount() { return faultRoundCount; }
    Ble11ScenarioState(Scenario scenario) { this(scenario, defaults(scenario)); }
    Ble11ScenarioState(Scenario scenario, Fault fault) { this.scenario = scenario; this.fault = fault; }
    static Fault defaults(Scenario scenario) {
        Position position = scenario == Scenario.ATT_TIMEOUT_MIDDLE ? Position.MIDDLE : scenario == Scenario.ATT_TIMEOUT_LAST ? Position.LAST : Position.FIRST;
        return new Fault(COMMAND_CHARACTERISTIC, position, 1, 5, 0, scenario == Scenario.RESPONSE_DELAY ? 1000 : 80);
    }
    Scenario scenario() { return scenario; }
    Fault fault() { return fault; }
    boolean requiresEncryptedPermission() { return true; }
    Action onFragment(String uuid, int index, int count, boolean bonded) {
        if (!bonded) return Action.REJECT_SECURITY;
        if (!fault.matches(uuid, index, count)) return Action.ACCEPT;
        final boolean persistent = scenario == Scenario.AUTH_PERSISTENT;
        final boolean authOnce = scenario == Scenario.AUTH_ONCE || scenario == Scenario.FALLBACK_ONCE;
        // Android can internally retry a security status within one write API call.
        // Keep that round faulty until a real disconnect or both CCCDs restore.
        // A client GATT rebuild can retain the physical ACL connection.
        if (injected && !persistent && (!authOnce || lastFaultEpoch != gattEpoch)) return Action.ACCEPT;
        final Action action = switch (scenario) {
            case AUTH_ONCE, AUTH_PERSISTENT, FALLBACK_ONCE -> Action.REJECT_SECURITY;
            case ATT_TIMEOUT_FIRST, ATT_TIMEOUT_MIDDLE, ATT_TIMEOUT_LAST -> Action.IGNORE_ATT;
            case DISCONNECT_ONCE -> Action.DISCONNECT;
            default -> Action.ACCEPT;
        };
        if (action != Action.ACCEPT) {
            injected = true; faultCount++;
            if (lastFaultEpoch != gattEpoch) { lastFaultEpoch = gattEpoch; faultRoundCount++; }
        }
        return action;
    }
    boolean rejectNotification(String uuid) {
        // Allow the public preflight subscription. This scenario targets the
        // second CCCD during secured GATT preparation, before protected writes.
        if (scenario != Scenario.NOTIFICATION_FAILURE || !initialNotificationsEstablished || !uuid.equals("6f7d0006")) return false;
        injected = true; faultCount++; return true;
    }
    boolean injected() { return injected; }
    int faultCount() { return faultCount; }
}
