package deckers.thibault.aves;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Looper;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.*;
import java.util.zip.*;
import org.junit.*;
import org.junit.rules.TemporaryFolder;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.*;
import org.json.JSONObject;
import io.flutter.plugin.common.*;

/** Production file-channel calls and document streams; no handset/RF acceptance claim. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {27, 31}, manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
public final class BirdBoxBleDiagnosticFileChannelTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();
    private Activity activity;
    private BirdBoxBleDiagnosticFileChannel channel;
    private final Uri destination = Uri.parse("content://ble19-test/received");
    private final ByteArrayOutputStream received = new ByteArrayOutputStream();

    private static final class DirectExecutor extends AbstractExecutorService {
        boolean stopped;
        public void shutdown() { stopped = true; }
        public List<Runnable> shutdownNow() { stopped = true; return Collections.emptyList(); }
        public boolean isShutdown() { return stopped; }
        public boolean isTerminated() { return stopped; }
        public boolean awaitTermination(long timeout, TimeUnit unit) { return stopped; }
        public void execute(Runnable task) { if (stopped) throw new RejectedExecutionException(); task.run(); }
    }
    private static final class Result implements MethodChannel.Result {
        int completions; Object value; String code;
        public void success(Object value) { completions++; this.value = value; }
        public void error(String code, String message, Object details) { completions++; this.code = code; }
        public void notImplemented() { fail("Unimplemented method"); }
        @SuppressWarnings("unchecked") Map<String, Object> map() { assertEquals(1, completions); assertNull(code); return (Map<String, Object>) value; }
        void failed(String expected) { assertEquals(1, completions); assertEquals(expected, code); }
    }
    @Before public void setup() throws Exception {
        activity = mock(Activity.class);
        when(activity.getCacheDir()).thenReturn(temporary.newFolder("cache"));
        when(activity.getContentResolver()).thenReturn(RuntimeEnvironment.getApplication().getContentResolver());
        when(activity.getPackageName()).thenReturn("synthetic.ble19.test");
        channel = new BirdBoxBleDiagnosticFileChannel(activity, mock(BinaryMessenger.class), new DirectExecutor());
        shadowOf(activity.getContentResolver()).registerOutputStream(destination, received);
        shadowOf(activity.getContentResolver()).registerInputStreamSupplier(destination, () -> new ByteArrayInputStream(received.toByteArray()));
    }
    @After public void teardown() { channel.dispose(); drain(); }
    private static void drain() { shadowOf(Looper.getMainLooper()).idle(); }
    private Result call(String method, Map<String, Object> args) {
        Result result = new Result(); channel.onMethodCall(new MethodCall(method, args), result); drain(); return result;
    }
    private Map<String, Object> prepare(boolean zipped) throws Exception {
        JSONObject full = new JSONObject().put("trace_id", "synthetic-local")
                .put("connection_events", new org.json.JSONArray()).put("scan_sessions", new org.json.JSONArray())
                .put("build", new JSONObject().put("evidence_kind", "synthetic_local_test"));
        if (zipped) full.put("padding", String.join("", Collections.nCopies(90000, "鸟🐦")));
        String payload = full.toString();
        String summary = new JSONObject().put("trace_id", "synthetic-local").put("build", full.getJSONObject("build")).toString();
        Map<String, Object> args = new HashMap<>(); args.put("fullJson", payload); args.put("summaryJson", summary);
        args.put("traceId", "synthetic-local"); args.put("payloadSha256", BirdBoxDiagnosticFileWriter.sha256(payload.getBytes(StandardCharsets.UTF_8)));
        return call("prepare", args).map();
    }
    private Map<String, Object> actionArgs(Map<String, Object> artifact) {
        Map<String, Object> args = new HashMap<>(); args.put("token", artifact.get("token")); args.put("sha256", artifact.get("sha256")); return args;
    }
    private void finishSave() {
        assertTrue(channel.onActivityResult(BirdBoxBleDiagnosticFileChannel.SAVE_REQUEST, Activity.RESULT_OK, new Intent().setData(destination))); drain();
    }
    private void assertReceived(Map<String, Object> artifact) {
        assertEquals(artifact.get("bytes"), (long) received.size());
        assertEquals(artifact.get("sha256"), BirdBoxDiagnosticFileWriter.sha256(received.toByteArray()));
    }
    @Test public void savesJsonThenRereadsDestinationBeforeReportingSaved() throws Exception {
        Map<String, Object> artifact = prepare(false);
        Result save = call("save", actionArgs(artifact)); assertEquals(0, save.completions);
        org.mockito.ArgumentCaptor<Intent> intent = org.mockito.ArgumentCaptor.forClass(Intent.class);
        verify(activity).startActivityForResult(intent.capture(), eq(BirdBoxBleDiagnosticFileChannel.SAVE_REQUEST));
        assertEquals(Intent.ACTION_CREATE_DOCUMENT, intent.getValue().getAction());
        assertEquals(artifact.get("fileName"), intent.getValue().getStringExtra(Intent.EXTRA_TITLE));
        finishSave(); assertEquals("saved", save.map().get("outcome")); assertReceived(artifact);
        JSONObject actual = new JSONObject(received.toString("UTF-8")); assertEquals("synthetic-local", actual.getString("trace_id"));
        finishSave(); assertEquals(1, save.completions);
    }
    @Test public void savesZipWithAllEntriesAndDifferentPayloadAndFileHashes() throws Exception {
        Map<String, Object> artifact = prepare(true); Result save = call("save", actionArgs(artifact)); finishSave();
        assertEquals("saved", save.map().get("outcome")); assertReceived(artifact);
        assertNotEquals(artifact.get("sha256"), artifact.get("payloadSha256"));
        Map<String, byte[]> entries = new HashMap<>();
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(received.toByteArray()))) {
            ZipEntry entry; while ((entry = zip.getNextEntry()) != null) {
                ByteArrayOutputStream body = new ByteArrayOutputStream(); byte[] buffer = new byte[4096]; int count;
                while ((count = zip.read(buffer)) != -1) body.write(buffer, 0, count);
                entries.put(entry.getName(), body.toByteArray());
            }
        }
        assertEquals(new HashSet<>(Arrays.asList("summary.json", "full_trace.json", "README.txt")), entries.keySet());
        assertEquals(artifact.get("payloadSha256"), BirdBoxDiagnosticFileWriter.sha256(entries.get("full_trace.json")));
        assertTrue(new String(entries.get("README.txt"), StandardCharsets.UTF_8).contains((String) artifact.get("payloadSha256")));
    }
    @Test public void cancelAndRepeatedExportReusePreparedFileWithoutCompletingTwice() throws Exception {
        Map<String, Object> artifact = prepare(false); Result first = call("save", actionArgs(artifact));
        channel.onActivityResult(BirdBoxBleDiagnosticFileChannel.SAVE_REQUEST, Activity.RESULT_CANCELED, null); drain();
        assertEquals("cancelled", first.map().get("outcome"));
        Result retry = call("save", actionArgs(artifact)); finishSave();
        assertEquals("saved", retry.map().get("outcome")); assertEquals(1, first.completions); assertReceived(artifact);
    }
    @Test public void corruptedDestinationCannotReportSaved() throws Exception {
        Map<String, Object> artifact = prepare(false);
        shadowOf(activity.getContentResolver()).registerInputStreamSupplier(destination, () -> new ByteArrayInputStream(new byte[]{1, 2, 3}));
        Result save = call("save", actionArgs(artifact)); finishSave(); save.failed("file_verification_failed");
    }
    @Test public void failedOutputCanRetryAndCacheCorruptionIsRejectedBeforeChooser() throws Exception {
        Map<String, Object> artifact = prepare(false);
        shadowOf(activity.getContentResolver()).registerOutputStream(destination, new OutputStream() {
            public void write(int value) throws IOException { throw new IOException("save_failed"); }
        });
        Result save = call("save", actionArgs(artifact)); finishSave(); save.failed("save_failed");
        shadowOf(activity.getContentResolver()).registerOutputStream(destination, received);
        Result retry = call("save", actionArgs(artifact)); finishSave(); assertEquals("saved", retry.map().get("outcome"));
        File cached = new File(new File(activity.getCacheDir(), "ble_diagnostics"), (String) artifact.get("fileName"));
        Files.write(cached.toPath(), new byte[]{1}); clearInvocations(activity);
        call("save", actionArgs(artifact)).failed("file_verification_failed");
        verify(activity, never()).startActivityForResult(any(Intent.class), anyInt());
    }
    @Test public void pendingChooserIsCompletedOnDisposeAndLateReplyIgnored() throws Exception {
        Map<String, Object> artifact = prepare(false); Result save = call("save", actionArgs(artifact));
        call("save", actionArgs(artifact)).failed("save_busy");
        channel.dispose(); save.failed("diagnostic_disposed"); finishSave(); assertEquals(1, save.completions);
        call("save", actionArgs(artifact)).failed("diagnostic_disposed");
    }
}
