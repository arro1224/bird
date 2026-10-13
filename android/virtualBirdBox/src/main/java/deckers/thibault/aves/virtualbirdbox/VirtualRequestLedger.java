package deckers.thibault.aves.virtualbirdbox;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

/** Bounded business deduplication across a GATT rebuild, without persisting commands. */
final class VirtualRequestLedger {
    interface Operation { byte[] run() throws Exception; }
    record Outcome(byte[] response, boolean duplicate) {}
    private record Entry(byte[] command, byte[] response) {}
    private final Map<String, Entry> requests = new LinkedHashMap<>();
    Outcome execute(String requestId, byte[] command, Operation operation) throws Exception {
        final Entry known = requests.get(requestId);
        if (known != null) {
            if (!Arrays.equals(known.command(), command)) throw new IllegalArgumentException("request_id_conflict");
            return new Outcome(known.response().clone(), true);
        }
        final byte[] response = operation.run();
        requests.put(requestId, new Entry(command.clone(), response.clone()));
        if (requests.size() > 128) requests.remove(requests.keySet().iterator().next());
        return new Outcome(response, false);
    }
}
