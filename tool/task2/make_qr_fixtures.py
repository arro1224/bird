import base64, os
target = r"E:\project\BirdApp\integration_test\task2_qr_fixtures.dart"
parts = [
    "// GENERATED fixture for integration_test/task2_provisioning_test.dart.",
    "//",
    "// Base64 PNGs of standard WIFI: QR codes used to prove on-device decoding:",
    "//   task2QrSingle -> one code (WPA2, SSID 'Studio')",
    "//   task2QrDouble -> two different codes in one image",
    "// Regenerate with tool/task2/make_qr_fixtures.py when the payloads change.",
    "",
]
for const, name, note in [
    ("task2QrSingle", "wifi_qr_ok.png", "single standard Wi-Fi QR"),
    ("task2QrDouble", "wifi_qr_two.png", "two different Wi-Fi QRs in one photo"),
]:
    with open(os.path.join(r"E:\dev-cache\tmp", name), "rb") as f:
        payload = base64.b64encode(f.read()).decode()
    parts.append("/// %s." % note)
    parts.append("const String %s =" % const)
    for i in range(0, len(payload), 120):
        parts.append("    '%s'" % payload[i:i+120])
    parts.append("    ;")
    parts.append("")
with open(target, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(parts))
print(target, os.path.getsize(target), "bytes")
