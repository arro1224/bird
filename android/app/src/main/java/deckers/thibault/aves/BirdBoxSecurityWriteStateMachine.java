package deckers.thibault.aves;

import java.util.Objects;

/**
 * Framework-free contract for one encrypted BirdBox request.
 *
 * <p>The platform bridge owns one instance and uses it to serialize the security-trigger write,
 * Bond observation, GATT recovery, notification restoration and the single exact retry required
 * by RC4-HF-BLE-02.</p>
 */
final class BirdBoxSecurityWriteStateMachine {
    enum Phase {
        IDLE,
        GATT_READY,
        SECURITY_WRITE_STARTING,
        BONDING,
        BONDED_RECOVERING_GATT,
        RESTORING_NOTIFICATIONS,
        RETRYING_ENCRYPTED_WRITE,
        WAITING_RESPONSE,
        COMPLETED,
        FAILED
    }

    enum Failure {
        NONE,
        GATT_NOT_READY,
        LE_PAIRING_NOT_STARTED,
        PAIRING_REJECTED,
        GATT_RECOVERY_FAILED,
        ENCRYPTED_RETRY_FAILED,
        PAIRING_OPEN_TIMEOUT
    }

    private Phase phase = Phase.IDLE;
    private Failure failure = Failure.NONE;
    private String requestId;
    private long gattGeneration = -1L;
    private int encryptedRetryCount;

    Phase phase() {
        return phase;
    }

    Failure failure() {
        return failure;
    }

    int encryptedRetryCount() {
        return encryptedRetryCount;
    }

    String requestId() {
        return requestId;
    }

    boolean isActive() {
        return phase != Phase.IDLE
                && phase != Phase.GATT_READY
                && phase != Phase.COMPLETED
                && phase != Phase.FAILED;
    }

    boolean acceptsGattCallback(long generation) {
        return generation == gattGeneration;
    }

    void markGattReady(long generation) {
        requireTerminalOrReady("mark GATT ready");
        gattGeneration = generation;
        requestId = null;
        encryptedRetryCount = 0;
        failure = Failure.NONE;
        phase = Phase.GATT_READY;
    }

    void beginSecurityWrite(String nextRequestId, long generation) {
        if (isActive()) {
            throw new IllegalStateException(
                    "start security write while request is active in " + phase
            );
        }
        if (phase != Phase.GATT_READY || generation != gattGeneration) {
            fail(Failure.GATT_NOT_READY);
            return;
        }
        if (nextRequestId == null || nextRequestId.isEmpty()) {
            throw new IllegalArgumentException("requestId must not be empty");
        }
        requestId = nextRequestId;
        failure = Failure.NONE;
        encryptedRetryCount = 0;
        phase = Phase.SECURITY_WRITE_STARTING;
    }

    void onBonding() {
        requirePhase("observe bonding", Phase.SECURITY_WRITE_STARTING, Phase.BONDING);
        phase = Phase.BONDING;
    }

    void onSecurityRequired() {
        if (phase == Phase.RETRYING_ENCRYPTED_WRITE) {
            fail(Failure.ENCRYPTED_RETRY_FAILED);
            return;
        }
        // A vendor stack may publish BOND_BONDED before it delivers the failed write callback.
        // Bond/GATT recovery has already won that race, so the late callback must not rewind it.
        if (phase == Phase.BONDED_RECOVERING_GATT
                || phase == Phase.RESTORING_NOTIFICATIONS) return;
        requirePhase("observe security requirement", Phase.SECURITY_WRITE_STARTING, Phase.BONDING);
        phase = Phase.BONDING;
    }

    void onPairingRejected() {
        requirePhase("reject pairing", Phase.SECURITY_WRITE_STARTING, Phase.BONDING);
        fail(Failure.PAIRING_REJECTED);
    }

    void onPairingNotStartedTimeout() {
        requirePhase("time out pairing start", Phase.SECURITY_WRITE_STARTING, Phase.BONDING);
        fail(Failure.LE_PAIRING_NOT_STARTED);
    }

    void onBonded(boolean currentGattUsable) {
        if (phase == Phase.BONDED_RECOVERING_GATT
                || phase == Phase.RESTORING_NOTIFICATIONS) return;
        requirePhase("complete bonding", Phase.SECURITY_WRITE_STARTING, Phase.BONDING);
        phase = currentGattUsable
                ? Phase.RESTORING_NOTIFICATIONS
                : Phase.BONDED_RECOVERING_GATT;
    }

    void onGattRecovered(long newGeneration) {
        requirePhase("recover GATT", Phase.BONDED_RECOVERING_GATT);
        if (newGeneration <= gattGeneration) {
            throw new IllegalArgumentException("recovered GATT generation must advance");
        }
        gattGeneration = newGeneration;
        phase = Phase.RESTORING_NOTIFICATIONS;
    }

    void onGattLostAfterBond() {
        requirePhase("lose GATT after bonding", Phase.RESTORING_NOTIFICATIONS);
        phase = Phase.BONDED_RECOVERING_GATT;
    }

    void onGattRecoveryFailed() {
        requirePhase(
                "fail GATT recovery",
                Phase.BONDED_RECOVERING_GATT,
                Phase.RESTORING_NOTIFICATIONS
        );
        fail(Failure.GATT_RECOVERY_FAILED);
    }

    void onNotificationsRestored() {
        requirePhase("restore notifications", Phase.RESTORING_NOTIFICATIONS);
        if (encryptedRetryCount != 0) {
            fail(Failure.ENCRYPTED_RETRY_FAILED);
            return;
        }
        encryptedRetryCount = 1;
        phase = Phase.RETRYING_ENCRYPTED_WRITE;
    }

    void onEncryptedRetryFailed() {
        requirePhase("fail encrypted retry", Phase.RETRYING_ENCRYPTED_WRITE);
        fail(Failure.ENCRYPTED_RETRY_FAILED);
    }

    void onWriteSucceeded() {
        requirePhase(
                "complete encrypted write",
                Phase.SECURITY_WRITE_STARTING,
                Phase.BONDING,
                Phase.RESTORING_NOTIFICATIONS,
                Phase.RETRYING_ENCRYPTED_WRITE
        );
        phase = Phase.WAITING_RESPONSE;
    }

    boolean onResponse(String responseRequestId) {
        requirePhase("accept response", Phase.WAITING_RESPONSE);
        if (!Objects.equals(requestId, responseRequestId)) return false;
        phase = Phase.COMPLETED;
        return true;
    }

    void onResponseTimeout() {
        requirePhase("time out response", Phase.WAITING_RESPONSE);
        fail(Failure.PAIRING_OPEN_TIMEOUT);
    }

    void reset() {
        phase = Phase.IDLE;
        failure = Failure.NONE;
        requestId = null;
        gattGeneration = -1L;
        encryptedRetryCount = 0;
    }

    private void fail(Failure reason) {
        failure = reason;
        phase = Phase.FAILED;
    }

    private void requireTerminalOrReady(String action) {
        if (isActive()) {
            throw new IllegalStateException(action + " while request is active in " + phase);
        }
    }

    private void requirePhase(String action, Phase... allowed) {
        for (Phase candidate : allowed) {
            if (phase == candidate) return;
        }
        throw new IllegalStateException(action + " from " + phase);
    }
}
