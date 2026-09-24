package deckers.thibault.aves.virtualbirdbox;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.List;

public final class Rc4BleFrameCodecTest {
    @Test
    public void fragmentsAndReassemblesTheFrozenLittleEndianFormat() {
        final byte[] message = "BLE-11 deterministic virtual BirdBox".getBytes(StandardCharsets.UTF_8);
        final List<byte[]> frames = Rc4BleFrameCodec.fragment(message, 0x1234, 20);
        assertEquals(5, frames.size());
        assertEquals(0x34, frames.get(0)[4] & 0xFF);
        assertEquals(0x12, frames.get(0)[5] & 0xFF);

        final Rc4BleFrameCodec.Reassembler reassembler = new Rc4BleFrameCodec.Reassembler();
        byte[] complete = null;
        for (byte[] frame : frames) {
            final byte[] candidate = reassembler.add(frame);
            if (candidate != null) complete = candidate;
        }
        assertArrayEquals(message, complete);
    }

    @Test
    public void acceptsAnIdenticalDuplicateWithoutCompletingEarly() {
        final List<byte[]> frames = Rc4BleFrameCodec.fragment(new byte[20], 7, 20);
        final Rc4BleFrameCodec.Reassembler reassembler = new Rc4BleFrameCodec.Reassembler();
        assertNull(reassembler.add(frames.get(0)));
        assertNull(reassembler.add(frames.get(0)));
        assertNull(reassembler.add(frames.get(1)));
        assertArrayEquals(new byte[20], reassembler.add(frames.get(2)));
    }

    @Test
    public void rejectsMalformedLengthAndFlags() {
        final byte[] frame = Rc4BleFrameCodec.fragment(new byte[]{1, 2, 3}, 1, 20).get(0);
        frame[3] = 0;
        assertThrows(IllegalArgumentException.class, () -> Rc4BleFrameCodec.decode(frame));
    }

    @Test
    public void rejectsMessagesAboveTheFrozenLimit() {
        assertThrows(
                IllegalArgumentException.class,
                () -> Rc4BleFrameCodec.fragment(new byte[4097], 1, 517)
        );
    }
}
