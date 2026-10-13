package deckers.thibault.aves.virtualbirdbox;
import static org.junit.Assert.*;
import org.junit.Test;
public final class VirtualRequestLedgerTest {
    @Test public void retryWithDifferentMtuDeduplicatesTheReassembledCommand() throws Exception {
        VirtualRequestLedger ledger = new VirtualRequestLedger(); int[] calls = {0};
        byte[] message = new byte[123]; java.util.Arrays.fill(message, (byte) 42);
        for (int mtu : new int[]{20, 97, 20}) {
            Rc4BleFrameCodec.Reassembler assembler = new Rc4BleFrameCodec.Reassembler(); byte[] complete = null;
            for (byte[] frame : Rc4BleFrameCodec.fragment(message, 11, mtu)) complete = assembler.add(frame);
            VirtualRequestLedger.Outcome result = ledger.execute("same-request", complete, () -> { calls[0]++; return new byte[]{7}; });
            assertArrayEquals(new byte[]{7}, result.response());
        }
        assertEquals(1, calls[0]);
        assertThrows(IllegalArgumentException.class, () -> ledger.execute("same-request", new byte[]{1}, () -> new byte[]{8}));
        assertEquals(1, calls[0]);
    }
    @Test public void failedOperationDoesNotEnterLedgerAndCachedResponseCannotBeMutated() throws Exception {
        VirtualRequestLedger ledger = new VirtualRequestLedger();
        assertThrows(Exception.class, () -> ledger.execute("request", new byte[]{1}, () -> { throw new Exception("failure"); }));
        VirtualRequestLedger.Outcome first = ledger.execute("request", new byte[]{1}, () -> new byte[]{7});
        first.response()[0] = 99;
        assertArrayEquals(new byte[]{7}, ledger.execute("request", new byte[]{1}, () -> new byte[]{8}).response());
    }
}
