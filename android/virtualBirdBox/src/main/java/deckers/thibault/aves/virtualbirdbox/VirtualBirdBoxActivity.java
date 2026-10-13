package deckers.thibault.aves.virtualbirdbox;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Build;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.ArrayAdapter;
import android.widget.Button;

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
    private String observationRunId;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        status = new TextView(this);
        status.setGravity(Gravity.CENTER);
        status.setTextSize(20f);
        status.setPadding(48, 48, 48, 48);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        Spinner selector = new Spinner(this);
        java.util.List<String> names = new java.util.ArrayList<>();
        for (Ble11ScenarioState.Scenario option : Ble11ScenarioState.Scenario.values()) {
            if (option == Ble11ScenarioState.Scenario.SUCCESS || option == Ble11ScenarioState.Scenario.AUTO_BOND || option == Ble11ScenarioState.Scenario.FALLBACK_ONCE) continue;
            names.add(option.wireValue());
        }
        selector.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, names));
        Button start = new Button(this); start.setText("启动所选测试场景");
        start.setOnClickListener(view -> {
            stopPeripheral();
            configure(new Intent().putExtra("scenario", (String) selector.getSelectedItem()).putExtra("reset_log", true));
        });
        layout.addView(selector); layout.addView(start); layout.addView(status); setContentView(layout);
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
        setIntent(intent);
        try {
            scenario = Ble11ScenarioState.Scenario.parse(intent.getStringExtra("scenario"));
            observationRunId = intent.getStringExtra("run_id");
            if (observationRunId != null && !observationRunId.matches("[A-Za-z0-9][A-Za-z0-9._-]{0,120}")) {
                throw new IllegalArgumentException("Invalid observation run ID");
            }
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
            final Ble11ScenarioState.Fault defaults = Ble11ScenarioState.defaults(scenario);
            final Intent intent = getIntent();
            final String position = intent.getStringExtra("fault_position");
            final Ble11ScenarioState.Fault fault = new Ble11ScenarioState.Fault(
                    intent.hasExtra("fault_characteristic") ? intent.getStringExtra("fault_characteristic") : defaults.characteristic,
                    position == null ? defaults.position : Ble11ScenarioState.Position.valueOf(position.toUpperCase(java.util.Locale.ROOT)),
                    intent.getIntExtra("fault_fragment_index", defaults.fragmentIndex),
                    intent.getIntExtra("fault_status", defaults.status),
                    intent.getIntExtra("att_response_delay_ms", defaults.attDelayMs),
                    intent.getIntExtra("business_response_delay_ms", defaults.responseDelayMs));
            String businessOutcome = intent.getStringExtra("business_outcome");
            String businessBaseUri = intent.getStringExtra("business_base_uri");
            final VirtualBirdBoxProtocol protocol = new VirtualBirdBoxProtocol(System::currentTimeMillis,
                    businessBaseUri == null ? "http://192.0.2.1:8080" : businessBaseUri,
                    businessOutcome == null ? "success" : businessOutcome);
            peripheral = new VirtualBirdBoxPeripheral(this, new Ble11ScenarioState(scenario, fault), this::record, protocol);
            peripheral.setObservationRunId(observationRunId);
            peripheral.start();
            status.setText("BLE-20 Virtual BirdBox\n" + scenario.wireValue() + "\n等待广播成功回调");
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

    private synchronized void record(String eventType, JSONObject fields) {
        final JSONObject event = new JSONObject();
        try {
            event.put("schema_version", 2);
            event.put("evidence_kind", "virtual_birdbox_endpoint");
            event.put("security_flow", "bond_first");
            event.put("endpoint_kind", "virtual_birdbox");
            event.put("model", Build.MODEL);
            event.put("manufacturer", Build.MANUFACTURER);
            event.put("sdk_int", Build.VERSION.SDK_INT);
            event.put("package_id", BuildConfig.APPLICATION_ID);
            event.put("version_name", BuildConfig.VERSION_NAME);
            event.put("version_code", BuildConfig.VERSION_CODE);
            event.put("event_type", eventType);
            event.put("occurred_at", Instant.now().toString());
            event.put("fields", fields);
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
        final String line = event + System.lineSeparator();
        if (eventType.equals("advertising_started")) runOnUiThread(() -> status.setText("BLE-20 Virtual BirdBox\n" + scenario.wireValue() + "\n广播已启动 BirdBox-B1E11001\n加密写权限测试，非真实盒子"));
        if (eventType.equals("startup_failed") || eventType.equals("advertising_failed")) runOnUiThread(() -> status.setText("Virtual BirdBox 启动失败\n" + fields.optString("reason", fields.optString("error_code"))));
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
