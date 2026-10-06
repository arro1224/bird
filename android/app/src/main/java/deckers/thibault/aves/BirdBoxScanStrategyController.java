package deckers.thibault.aves;

/** Framework-free state machine for Huawei-compatible serial BLE scan strategies. */
final class BirdBoxScanStrategyController {
    static final long STRATEGY_WINDOW_MS = 4000L;

    enum Strategy {
        NULL_FILTER_LOW_LATENCY,
        EMPTY_FILTER_LIST_LOW_LATENCY,
        EMPTY_FILTER_LIST_DEFAULT_SETTINGS
    }

    enum DecisionType {
        IGNORE_STALE,
        KEEP_CURRENT,
        SWITCH,
        FALLBACK_EXHAUSTED
    }

    static final class Snapshot {
        final int generation;
        final int index;
        final Strategy strategy;
        final int rawResultCount;
        final int deviceNameResultCount;
        final int candidateCount;
        final Integer androidScanErrorCode;

        Snapshot(
                int generation,
                int index,
                Strategy strategy,
                int rawResultCount,
                int deviceNameResultCount,
                int candidateCount,
                Integer androidScanErrorCode) {
            this.generation = generation;
            this.index = index;
            this.strategy = strategy;
            this.rawResultCount = rawResultCount;
            this.deviceNameResultCount = deviceNameResultCount;
            this.candidateCount = candidateCount;
            this.androidScanErrorCode = androidScanErrorCode;
        }
    }

    static final class Decision {
        final DecisionType type;
        final Snapshot completed;
        final Snapshot next;
        final String reason;

        Decision(DecisionType type, Snapshot completed, Snapshot next, String reason) {
            this.type = type;
            this.completed = completed;
            this.next = next;
            this.reason = reason;
        }
    }

    private boolean active;
    private int generation;
    private int strategyIndex;
    private int rawResultCount;
    private int deviceNameResultCount;
    private int candidateCount;
    private Integer androidScanErrorCode;

    synchronized Snapshot begin() {
        active = true;
        generation++;
        strategyIndex = 0;
        resetCounts();
        return snapshot();
    }

    synchronized boolean accepts(int callbackGeneration) {
        return active && callbackGeneration == generation;
    }

    synchronized boolean recordResult(
            int callbackGeneration,
            boolean deviceNamePresent,
            boolean candidate) {
        if (!accepts(callbackGeneration)) return false;
        rawResultCount++;
        if (deviceNamePresent) deviceNameResultCount++;
        if (candidate) candidateCount++;
        return true;
    }

    synchronized boolean recordAndroidError(int callbackGeneration, int errorCode) {
        if (!accepts(callbackGeneration)) return false;
        androidScanErrorCode = errorCode;
        return true;
    }

    synchronized Decision onWindowElapsed(int callbackGeneration) {
        if (!accepts(callbackGeneration)) {
            return new Decision(DecisionType.IGNORE_STALE, null, null, "stale_generation");
        }
        final Snapshot completed = snapshot();
        if (rawResultCount > 0) {
            return new Decision(
                    DecisionType.KEEP_CURRENT,
                    completed,
                    null,
                    "raw_results_observed"
            );
        }
        if (strategyIndex + 1 >= Strategy.values().length) {
            return new Decision(
                    DecisionType.FALLBACK_EXHAUSTED,
                    completed,
                    null,
                    "raw_zero_all_strategies"
            );
        }
        strategyIndex++;
        generation++;
        resetCounts();
        return new Decision(
                DecisionType.SWITCH,
                completed,
                snapshot(),
                "raw_zero_after_4000ms"
        );
    }

    synchronized Snapshot current() {
        return active ? snapshot() : null;
    }

    synchronized void stop() {
        active = false;
    }

    private Snapshot snapshot() {
        return new Snapshot(
                generation,
                strategyIndex,
                Strategy.values()[strategyIndex],
                rawResultCount,
                deviceNameResultCount,
                candidateCount,
                androidScanErrorCode
        );
    }

    private void resetCounts() {
        rawResultCount = 0;
        deviceNameResultCount = 0;
        candidateCount = 0;
        androidScanErrorCode = null;
    }
}
