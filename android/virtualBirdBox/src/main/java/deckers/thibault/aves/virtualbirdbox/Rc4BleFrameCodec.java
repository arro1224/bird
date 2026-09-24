package deckers.thibault.aves.virtualbirdbox;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class Rc4BleFrameCodec {
    static final int HEADER_LENGTH = 12;
    static final int MAXIMUM_MESSAGE_BYTES = 4096;
    static final int MAXIMUM_FRAGMENT_COUNT = 256;

    private Rc4BleFrameCodec() {}

    static List<byte[]> fragment(byte[] message, int messageId, int maximumFragmentBytes) {
        if (messageId < 0 || messageId > 0xFFFF) throw new IllegalArgumentException("messageId");
        if (message.length > MAXIMUM_MESSAGE_BYTES) throw new IllegalArgumentException("message too large");
        if (maximumFragmentBytes <= HEADER_LENGTH) throw new IllegalArgumentException("fragment too small");
        final int payloadLimit = maximumFragmentBytes - HEADER_LENGTH;
        final int fragmentCount = Math.max(1, (message.length + payloadLimit - 1) / payloadLimit);
        if (fragmentCount > MAXIMUM_FRAGMENT_COUNT) throw new IllegalArgumentException("too many fragments");
        final List<byte[]> frames = new ArrayList<>(fragmentCount);
        for (int index = 0; index < fragmentCount; index++) {
            final int start = index * payloadLimit;
            final int payloadLength = Math.min(payloadLimit, Math.max(0, message.length - start));
            final byte[] frame = new byte[HEADER_LENGTH + payloadLength];
            frame[0] = 0x42;
            frame[1] = 0x42;
            frame[2] = 0x01;
            frame[3] = (byte) ((index == 0 ? 0x01 : 0) | (index == fragmentCount - 1 ? 0x02 : 0));
            putUint16(frame, 4, messageId);
            putUint16(frame, 6, index);
            putUint16(frame, 8, fragmentCount);
            putUint16(frame, 10, payloadLength);
            if (payloadLength > 0) System.arraycopy(message, start, frame, HEADER_LENGTH, payloadLength);
            frames.add(frame);
        }
        return frames;
    }

    static Frame decode(byte[] frame) {
        if (frame.length < HEADER_LENGTH) throw new IllegalArgumentException("short frame");
        if (frame[0] != 0x42 || frame[1] != 0x42) throw new IllegalArgumentException("magic");
        if ((frame[2] & 0xFF) != 1) throw new IllegalArgumentException("version");
        final int flags = frame[3] & 0xFF;
        if ((flags & ~0x03) != 0) throw new IllegalArgumentException("flags");
        final int messageId = uint16(frame, 4);
        final int index = uint16(frame, 6);
        final int count = uint16(frame, 8);
        final int payloadLength = uint16(frame, 10);
        if (count < 1 || count > MAXIMUM_FRAGMENT_COUNT || index >= count) {
            throw new IllegalArgumentException("fragment index/count");
        }
        if (payloadLength != frame.length - HEADER_LENGTH) throw new IllegalArgumentException("payload length");
        if (((flags & 0x01) != 0) != (index == 0) || ((flags & 0x02) != 0) != (index == count - 1)) {
            throw new IllegalArgumentException("first/last flags");
        }
        final byte[] payload = new byte[payloadLength];
        System.arraycopy(frame, HEADER_LENGTH, payload, 0, payloadLength);
        return new Frame(messageId, index, count, payload);
    }

    private static int uint16(byte[] value, int offset) {
        return (value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8);
    }

    private static void putUint16(byte[] value, int offset, int number) {
        value[offset] = (byte) (number & 0xFF);
        value[offset + 1] = (byte) ((number >>> 8) & 0xFF);
    }

    record Frame(int messageId, int index, int count, byte[] payload) {}

    static final class Reassembler {
        private final Map<Integer, Pending> pending = new HashMap<>();

        byte[] add(byte[] encoded) {
            final Frame frame = decode(encoded);
            final Pending message = pending.computeIfAbsent(frame.messageId(), ignored -> new Pending(frame.count()));
            if (message.count != frame.count()) {
                pending.remove(frame.messageId());
                throw new IllegalArgumentException("fragment count changed");
            }
            final byte[] existing = message.fragments[frame.index()];
            if (existing != null) {
                if (java.util.Arrays.equals(existing, frame.payload())) return null;
                pending.remove(frame.messageId());
                throw new IllegalArgumentException("conflicting duplicate");
            }
            message.fragments[frame.index()] = frame.payload();
            message.received++;
            message.totalBytes += frame.payload().length;
            if (message.totalBytes > MAXIMUM_MESSAGE_BYTES) {
                pending.remove(frame.messageId());
                throw new IllegalArgumentException("message too large");
            }
            if (message.received != message.count) return null;
            final ByteArrayOutputStream output = new ByteArrayOutputStream(message.totalBytes);
            for (byte[] payload : message.fragments) {
                if (payload == null) throw new IllegalArgumentException("missing fragment");
                output.writeBytes(payload);
            }
            pending.remove(frame.messageId());
            return output.toByteArray();
        }

        void reset() {
            pending.clear();
        }
    }

    private static final class Pending {
        final int count;
        final byte[][] fragments;
        int received;
        int totalBytes;

        Pending(int count) {
            this.count = count;
            fragments = new byte[count][];
        }
    }
}
