package deckers.thibault.aves;

import android.app.Activity;
import android.content.*;
import android.net.Uri;
import android.os.*;
import androidx.core.content.FileProvider;
import java.io.*;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;
import io.flutter.plugin.common.*;

/** Uses only app-private cache and user-selected document URIs. */
final class BirdBoxBleDiagnosticFileChannel implements MethodChannel.MethodCallHandler {
    static final int SAVE_REQUEST = 0xBB32;
    private final Activity activity;
    private final MethodChannel channel;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> { Thread t = new Thread(r, "birdbox-diagnostic-file"); t.setDaemon(true); return t; });
    private final Map<String, BirdBoxDiagnosticFileWriter.Artifact> artifacts = new LinkedHashMap<>();
    private final File directory;
    private volatile boolean disposed;
    private MethodChannel.Result pendingSave;
    private BirdBoxDiagnosticFileWriter.Artifact saveArtifact;
    BirdBoxBleDiagnosticFileChannel(Activity activity, BinaryMessenger messenger) {
        this.activity = activity; directory = new File(activity.getCacheDir(), "ble_diagnostics");
        channel = new MethodChannel(messenger, "bird_companion/ble_diagnostic_files"); channel.setMethodCallHandler(this);
    }
    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (disposed) { result.error("diagnostic_disposed", "Diagnostic service closed.", null); return; }
        switch (call.method) {
            case "getBuildIdentity": run(result, () -> buildIdentity()); break;
            case "prepare": prepare(call, result); break;
            case "share": action(call, result, false); break;
            case "save": action(call, result, true); break;
            default: result.notImplemented();
        }
    }
    private Map<String, Object> buildIdentity() throws IOException {
        final Map<String, Object> build = new LinkedHashMap<>();
        build.put("package_id", activity.getPackageName()); build.put("flavor", BuildConfig.FLAVOR); build.put("build_type", BuildConfig.BUILD_TYPE);
        build.put("version_name", BuildConfig.VERSION_NAME); build.put("version_code", Integer.toString(BuildConfig.VERSION_CODE));
        build.put("git_commit", BuildConfig.GIT_SHA); build.put("build_dirty", BuildConfig.BUILD_DIRTY); build.put("build_id", BuildConfig.BUILD_ID);
        build.put("source_fingerprint", BuildConfig.SOURCE_FINGERPRINT); build.put("source_file_count", BuildConfig.SOURCE_FILE_COUNT);
        build.put("model", Build.MODEL); build.put("manufacturer", Build.MANUFACTURER); build.put("sdk_int", Build.VERSION.SDK_INT);
        build.put("apk_sha256", BirdBoxDiagnosticFileWriter.sha256(new File(activity.getApplicationInfo().sourceDir)));
        return build;
    }
    private void prepare(MethodCall call, MethodChannel.Result result) {
        final String full = call.argument("fullJson"), summary = call.argument("summaryJson"), trace = call.argument("traceId"), expected = call.argument("payloadSha256");
        run(result, () -> {
            if (full == null || summary == null || trace == null || expected == null || trace.isEmpty()) throw new IOException("invalid_file_input");
            if (full.length() > BirdBoxDiagnosticFileWriter.MAX_JSON_BYTES) throw new IOException("diagnostic_too_large");
            final JSONObject fullValue = new JSONObject(full), summaryValue = new JSONObject(summary);
            if (!trace.equals(fullValue.optString("trace_id")) || !trace.equals(summaryValue.optString("trace_id"))
                || fullValue.optJSONArray("connection_events") == null || fullValue.optJSONArray("scan_sessions") == null
                || !sameJson(fullValue.optJSONObject("build"), summaryValue.optJSONObject("build"))) throw new IOException("invalid_file_input");
            final String token = UUID.randomUUID().toString();
            final SimpleDateFormat format = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.ROOT); format.setTimeZone(TimeZone.getTimeZone("UTC"));
            final String basename = "BirdBox_BLE_" + BirdBoxDiagnosticFileWriter.safeComponent(BuildConfig.VERSION_NAME) + "_" + BuildConfig.VERSION_CODE
                + "_" + BirdBoxDiagnosticFileWriter.safeComponent(Build.MODEL) + "_" + format.format(new Date()) + "_" + BirdBoxDiagnosticFileWriter.safeComponent(trace) + "_" + token.substring(0, 8);
            final BirdBoxDiagnosticFileWriter.Artifact artifact = BirdBoxDiagnosticFileWriter.write(directory, basename, full, summary, expected);
            synchronized (artifacts) { artifacts.put(token, artifact); while (artifacts.size() > 32) artifacts.remove(artifacts.keySet().iterator().next()); }
            final Map<String, Object> value = new LinkedHashMap<>();
            value.put("token", token); value.put("fileName", artifact.file.getName()); value.put("mimeType", artifact.mime); value.put("bytes", artifact.file.length());
            value.put("sha256", artifact.sha256); value.put("payloadSha256", artifact.payloadSha256); value.put("verified", true); return value;
        });
    }
    private static boolean sameJson(JSONObject a, JSONObject b) throws JSONException {
        if (a == null || b == null) return a == b;
        if (a.length() != b.length()) return false;
        final Iterator<String> keys = a.keys(); while (keys.hasNext()) { final String key = keys.next(); if (!b.has(key) || !Objects.equals(a.get(key), b.get(key))) return false; }
        return true;
    }
    private void action(MethodCall call, MethodChannel.Result result, boolean save) {
        final String token = call.argument("token"), expected = call.argument("sha256");
        final BirdBoxDiagnosticFileWriter.Artifact artifact;
        synchronized (artifacts) { artifact = artifacts.get(token); }
        if (artifact == null || expected == null || !expected.equals(artifact.sha256)) { result.error("invalid_file_token", "Create a diagnostic file first.", null); return; }
        worker.execute(() -> {
            try {
                if (!BirdBoxDiagnosticFileWriter.verify(artifact.file, artifact.sha256)) throw new IOException("file_verification_failed");
                main.post(() -> {
                    if (disposed) { result.error("diagnostic_disposed", "Diagnostic service closed.", null); return; }
                    try {
                        if (save) {
                            if (pendingSave != null) { result.error("save_busy", "A save location is already being selected.", null); return; }
                            final Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(artifact.mime)
                                .putExtra(Intent.EXTRA_TITLE, artifact.file.getName()).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                            pendingSave = result; saveArtifact = artifact;
                            activity.startActivityForResult(intent, SAVE_REQUEST);
                        } else {
                            final Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".ble_diagnostics", artifact.file);
                            final Intent share = shareIntent(uri, artifact.mime).putExtra(Intent.EXTRA_TEXT, artifact.summaryJson);
                            if (share.resolveActivity(activity.getPackageManager()) == null) {
                                result.error("share_unavailable", "No App can handle this diagnostic file.", null);
                                return;
                            }
                            final Intent chooser = Intent.createChooser(share, "分享完整蓝牙诊断");
                            chooser.setClipData(share.getClipData());
                            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                            activity.startActivity(chooser);
                            result.success(Collections.singletonMap("outcome", "share_opened"));
                        }
                    } catch (RuntimeException error) {
                        if (save) { pendingSave = null; saveArtifact = null; }
                        result.error(save ? "save_unavailable" : "share_unavailable", "System file action is unavailable.", null);
                    }
                });
            } catch (Exception error) { fail(result, error); }
        });
    }
    static Intent shareIntent(Uri uri, String mime) {
        final Intent intent = new Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.setClipData(ClipData.newRawUri("BirdBox BLE diagnostic", uri));
        return intent;
    }
    boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != SAVE_REQUEST) return false;
        final MethodChannel.Result result = pendingSave; final BirdBoxDiagnosticFileWriter.Artifact artifact = saveArtifact;
        pendingSave = null; saveArtifact = null;
        if (result == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) { result.success(Collections.singletonMap("outcome", "cancelled")); return true; }
        final Uri destination = data.getData();
        run(result, () -> {
            if (!"content".equals(destination.getScheme()) || artifact == null || !BirdBoxDiagnosticFileWriter.verify(artifact.file, artifact.sha256)) throw new IOException("file_verification_failed");
            try (InputStream input = new FileInputStream(artifact.file); OutputStream output = activity.getContentResolver().openOutputStream(destination, "wt")) {
                if (output == null) throw new IOException("save_failed");
                final byte[] buffer = new byte[16384]; int count; while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count); output.flush();
            }
            final java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            try (InputStream saved = activity.getContentResolver().openInputStream(destination)) {
                if (saved == null) throw new IOException("save_failed");
                final byte[] buffer = new byte[16384]; int count; while ((count = saved.read(buffer)) != -1) digest.update(buffer, 0, count);
            }
            final StringBuilder hex = new StringBuilder(); for (byte b : digest.digest()) hex.append(String.format(Locale.ROOT, "%02x", b & 255));
            if (!artifact.sha256.equals(hex.toString())) throw new IOException("file_verification_failed");
            return Collections.singletonMap("outcome", "saved");
        });
        return true;
    }
    private interface Job { Object run() throws Exception; }
    private void run(MethodChannel.Result result, Job job) {
        worker.execute(() -> { try { Object value = job.run(); main.post(() -> { if (disposed) result.error("diagnostic_disposed", "Diagnostic service closed.", null); else result.success(value); }); }
            catch (Exception error) { fail(result, error); } });
    }
    private void fail(MethodChannel.Result result, Exception error) {
        final String reason = error.getMessage();
        final String code = Arrays.asList("invalid_file_input", "diagnostic_too_large", "file_verification_failed", "diagnostic_cache_full", "diagnostic_storage_failed", "save_failed").contains(reason) ? reason : "diagnostic_file_failed";
        main.post(() -> result.error(code, "Diagnostic file operation failed.", null));
    }
    void dispose() {
        if (disposed) return; disposed = true; channel.setMethodCallHandler(null);
        if (pendingSave != null) { pendingSave.error("diagnostic_disposed", "Save was interrupted by lifecycle teardown.", null); pendingSave = null; saveArtifact = null; }
        worker.shutdown(); // Queued results are resolved; cache survives chooser reads.
    }
}
