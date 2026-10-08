package deckers.thibault.aves.virtualbirdbox;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Build;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;

import android.app.Activity;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;

public final class VirtualBirdBoxActivity extends Activity {
    private static final String TAG = "BLE11_VIRTUAL_BOX";
    private static final int PERMISSION_REQUEST = 1101;
    private static final String[] PERMISSIONS = {
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
    };

    private TextView status;
    private VirtualBirdBoxPeripheral peripheral;
    private Ble11ScenarioState.Scenario scenario;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        status = new TextView(this);
        status.setGravity(Gravity.CENTER);
        status.setTextSize(20f);
        status.setPadding(48, 48, 48, 48);
        setContentView(status);
        configure(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        stopPeripheral();
        configure(intent);
    }

    private void configure(Intent intent) {
        try {
            scenario = Ble11ScenarioState.Scenario.parse(intent.getStringExtra("scenario"));
        } catch (IllegalArgumentException error) {
            status.setText(error.getMessage());
            record("startup_failed", field("reason", "invalid_scenario"));
            return;
        }
        if (intent.getBooleanExtra("reset_log", true)) {
            final File log = eventLog();
            if (log.exists() && !log.delete()) Log.w(TAG, "Unable to reset previous event log");
        }
        status.setText("BLE-11 Virtual BirdBox\n" + scenario.wireValue() + "\nstarting…");
        if (hasRequiredPermissions()) {
            startPeripheral();
        } else {
            requestPermissions(PERMISSIONS, PERMISSION_REQUEST);
        }
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            String[] permissions,
            int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != PERMISSION_REQUEST) return;
        if (hasRequiredPermissions()) {
            startPeripheral();
        } else {
            status.setText("BLE permissions denied");
            record("startup_failed", field("reason", "permission_denied"));
        }
    }

    private boolean hasRequiredPermissions() {
        // BLUETOOTH_ADVERTISE and BLUETOOTH_CONNECT are runtime permissions only
        // from Android 12. Android 5--11 use the legacy manifest declarations.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true;
        for (String permission : PERMISSIONS) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) return false;
        }
        return true;
    }

    private void startPeripheral() {
        try {
            peripheral = new VirtualBirdBoxPeripheral(this, scenario, this::record);
            peripheral.start();
            status.setText("BLE-11 Virtual BirdBox\n" + scenario.wireValue() + "\nAdvertising BirdBox-B1E11001");
        } catch (RuntimeException error) {
            status.setText("Virtual BirdBox failed\n" + error.getClass().getSimpleName());
            record("startup_failed", field("reason", error.getClass().getSimpleName()));
        }
    }

    private void stopPeripheral() {
        if (peripheral != null) peripheral.stop();
        peripheral = null;
    }

    @Override
    protected void onDestroy() {
        stopPeripheral();
        super.onDestroy();
    }

    private void record(String eventType, JSONObject fields) {
        final JSONObject event = new JSONObject();
        try {
            event.put("schema_version", 1);
            event.put("evidence_kind", "simulated");
            event.put("event_type", eventType);
            event.put("occurred_at", Instant.now().toString());
            event.put("fields", fields);
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
        final String line = event + System.lineSeparator();
        Log.i(TAG, event.toString());
        try (FileOutputStream output = new FileOutputStream(eventLog(), true)) {
            output.write(line.getBytes(StandardCharsets.UTF_8));
        } catch (IOException error) {
            Log.e(TAG, "Unable to write simulated evidence", error);
        }
    }

    private File eventLog() {
        return new File(getFilesDir(), "ble11-events.jsonl");
    }

    private static JSONObject field(String name, Object value) {
        final JSONObject result = new JSONObject();
        try {
            result.put(name, value);
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
        return result;
    }
}
