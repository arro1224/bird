package deckers.thibault.aves;

import java.util.Objects;
import java.util.UUID;

/** Tracks one sensitive GATT write invocation without retaining its payload. */
final class BirdBoxSecurityWriteAttemptContext {
    enum Trigger {
        NONE,
        EXPLICIT_GATT_SECURITY_STATUS,
        WRITE_CALLBACK_TIMEOUT,
        SYSTEM_BOND_STATE_OBSERVED
    }

    private String requestId;
    private String attemptId;
    private int connectionGeneration = -1;
    private int gattGeneration = -1;
    private UUID characteristicUuid;
    private long startedAtMs = -1L;
    private boolean active;
    private boolean apiAccepted;
    private boolean callbackReceived;
    private boolean fallbackStarted;
    private Trigger trigger = Trigger.NONE;
    private String bondStateAtTrigger;
    private boolean createBondInvoked;
    private Boolean createBondReturned;
    private String createBondStateBefore;
    private String createBondStateAfter;
    private String createBondException;
    private String stateBefore;
    private String stateAfter;
    private String terminalOutcome;
    private String cleanupOutcome;

    void begin(
            String nextRequestId,
            int nextConnectionGeneration,
            int nextGattGeneration,
            UUID nextCharacteristicUuid,
            long nextStartedAtMs) {
        if (nextRequestId == null || nextRequestId.isEmpty()) {
            throw new IllegalArgumentException("requestId must not be empty");
        }
        if (nextCharacteristicUuid == null) {
            throw new IllegalArgumentException("characteristicUuid must not be null");
        }
        requestId = nextRequestId;
        attemptId = nextRequestId
                + ":" + nextConnectionGeneration
                + ":" + nextGattGeneration
                + ":" + nextStartedAtMs;
        connectionGeneration = nextConnectionGeneration;
        gattGeneration = nextGattGeneration;
        characteristicUuid = nextCharacteristicUuid;
        startedAtMs = nextStartedAtMs;
        active = true;
        apiAccepted = false;
        callbackReceived = false;
        fallbackStarted = false;
        trigger = Trigger.NONE;
        bondStateAtTrigger = null;
        createBondInvoked = false;
        createBondReturned = null;
        createBondStateBefore = null;
        createBondStateAfter = null;
        createBondException = null;
        stateBefore = null;
        stateAfter = null;
        terminalOutcome = null;
        cleanupOutcome = null;
    }

    boolean markApiAccepted(
            String expectedRequestId,
            int expectedConnectionGeneration,
            int expectedGattGeneration,
            UUID expectedCharacteristicUuid) {
        if (!sameAttempt(
                expectedRequestId,
                expectedConnectionGeneration,
                expectedGattGeneration,
                expectedCharacteristicUuid)) {
            return false;
        }
        apiAccepted = true;
        return true;
    }

    boolean completeFromCallback(
            int callbackConnectionGeneration,
            int callbackGattGeneration,
            UUID callbackCharacteristicUuid,
            boolean explicitGattSecurityStatus) {
        if (!matches(
                callbackConnectionGeneration,
                callbackGattGeneration,
                callbackCharacteristicUuid)) {
            return false;
        }
        active = false;
        apiAccepted = true;
        callbackReceived = true;
        if (explicitGattSecurityStatus) {
            trigger = Trigger.EXPLICIT_GATT_SECURITY_STATUS;
        }
        return true;
    }

    boolean completeFromCallbackTimeout(
            String expectedRequestId,
            int expectedConnectionGeneration,
            int expectedGattGeneration,
            UUID expectedCharacteristicUuid) {
        if (!Objects.equals(requestId, expectedRequestId)
                || !apiAccepted
                || !matches(
                expectedConnectionGeneration,
                expectedGattGeneration,
                expectedCharacteristicUuid)) {
            return false;
        }
        active = false;
        trigger = Trigger.WRITE_CALLBACK_TIMEOUT;
        return true;
    }

    boolean completeFromSystemBondState(
            int expectedConnectionGeneration,
            int expectedGattGeneration) {
        if (!active
                || !apiAccepted
                || connectionGeneration != expectedConnectionGeneration
                || gattGeneration != expectedGattGeneration) {
            return false;
        }
        active = false;
        trigger = Trigger.SYSTEM_BOND_STATE_OBSERVED;
        return true;
    }

    boolean completeFromGattSecurityStatus(
            int expectedConnectionGeneration,
            int expectedGattGeneration) {
        if (!active
                || connectionGeneration != expectedConnectionGeneration
                || gattGeneration != expectedGattGeneration) {
            return false;
        }
        active = false;
        trigger = Trigger.EXPLICIT_GATT_SECURITY_STATUS;
        return true;
    }

    boolean tryMarkFallbackStarted() {
        if (trigger == Trigger.NONE || fallbackStarted) return false;
        fallbackStarted = true;
        return true;
    }

    void recordTriggerBondState(String value) {
        if (trigger == Trigger.NONE || bondStateAtTrigger != null) return;
        bondStateAtTrigger = value;
    }

    /** Records the side-effect boundary before BluetoothDevice.createBond() is invoked. */
    void recordCreateBondInvoked(String before) {
        createBondInvoked = true;
        createBondStateBefore = before;
    }

    void recordCreateBondResult(boolean returned, String after) {
        createBondInvoked = true;
        createBondReturned = returned;
        createBondStateAfter = after;
    }

    /**
     * Retains only the exception type: framework messages can contain vendor/device details and
     * must not be included in exported diagnostics.
     */
    void recordCreateBondException(String exceptionType, String after) {
        createBondInvoked = true;
        createBondException = exceptionType;
        createBondStateAfter = after;
    }

    void recordCreateBond(boolean returned, String before, String after) {
        recordCreateBondInvoked(before);
        recordCreateBondResult(returned, after);
    }

    void recordStateTransition(String before, String after) {
        stateBefore = before;
        stateAfter = after;
    }

    void markTerminal(String outcome) {
        terminalOutcome = outcome;
    }

    void markCleanup(String outcome) {
        cleanupOutcome = outcome;
    }

    String attemptId() {
        return attemptId;
    }

    int connectionGeneration() {
        return connectionGeneration;
    }

    int gattGeneration() {
        return gattGeneration;
    }

    Trigger trigger() {
        return trigger;
    }

    UUID characteristicUuid() {
        return characteristicUuid;
    }

    boolean callbackReceived() {
        return callbackReceived;
    }

    boolean apiAccepted() {
        return apiAccepted;
    }

    String bondStateAtTrigger() {
        return bondStateAtTrigger;
    }

    boolean createBondInvoked() {
        return createBondInvoked;
    }

    Boolean createBondReturned() {
        return createBondReturned;
    }

    String createBondStateBefore() {
        return createBondStateBefore;
    }

    String createBondStateAfter() {
        return createBondStateAfter;
    }

    String createBondException() {
        return createBondException;
    }

    String stateBefore() {
        return stateBefore;
    }

    String stateAfter() {
        return stateAfter;
    }

    String terminalOutcome() {
        return terminalOutcome;
    }

    String cleanupOutcome() {
        return cleanupOutcome;
    }

    boolean isWaitingForCallback(
            String expectedRequestId,
            int expectedConnectionGeneration,
            int expectedGattGeneration,
            UUID expectedCharacteristicUuid) {
        return apiAccepted
                && Objects.equals(requestId, expectedRequestId)
                && matches(
                expectedConnectionGeneration,
                expectedGattGeneration,
                expectedCharacteristicUuid
        );
    }

    long elapsedMs(long nowMs) {
        return startedAtMs < 0L ? -1L : Math.max(0L, nowMs - startedAtMs);
    }

    void cancelActive() {
        active = false;
    }

    void reset() {
        requestId = null;
        attemptId = null;
        connectionGeneration = -1;
        gattGeneration = -1;
        characteristicUuid = null;
        startedAtMs = -1L;
        active = false;
        apiAccepted = false;
        callbackReceived = false;
        fallbackStarted = false;
        trigger = Trigger.NONE;
        bondStateAtTrigger = null;
        createBondInvoked = false;
        createBondReturned = null;
        createBondStateBefore = null;
        createBondStateAfter = null;
        createBondException = null;
        stateBefore = null;
        stateAfter = null;
        terminalOutcome = null;
        cleanupOutcome = null;
    }

    private boolean matches(
            int expectedConnectionGeneration,
            int expectedGattGeneration,
            UUID expectedCharacteristicUuid) {
        return active
                && connectionGeneration == expectedConnectionGeneration
                && gattGeneration == expectedGattGeneration
                && Objects.equals(characteristicUuid, expectedCharacteristicUuid);
    }

    private boolean sameAttempt(
            String expectedRequestId,
            int expectedConnectionGeneration,
            int expectedGattGeneration,
            UUID expectedCharacteristicUuid) {
        return Objects.equals(requestId, expectedRequestId)
                && connectionGeneration == expectedConnectionGeneration
                && gattGeneration == expectedGattGeneration
                && Objects.equals(characteristicUuid, expectedCharacteristicUuid);
    }
}
