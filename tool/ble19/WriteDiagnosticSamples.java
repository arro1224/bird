package deckers.thibault.aves;

import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

/** Local synthetic Dart exports -> production Android file writer. No handset or RF evidence. */
public final class WriteDiagnosticSamples {
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]).toAbsolutePath();
        for (String kind : new String[]{"plain", "zip"}) {
            String full = Files.readString(root.resolve(kind).resolve("full_trace.json"), StandardCharsets.UTF_8);
            String summary = Files.readString(root.resolve(kind).resolve("summary.json"), StandardCharsets.UTF_8);
            BirdBoxDiagnosticFileWriter.Artifact artifact = BirdBoxDiagnosticFileWriter.write(root.resolve("files").toFile(),
                    "BirdBox_BLE_synthetic_local_" + kind + "_" + UUID.randomUUID(), full, summary,
                    BirdBoxDiagnosticFileWriter.sha256(full.getBytes(StandardCharsets.UTF_8)));
            String report = "{\"evidence_kind\":\"synthetic_local_file_pipeline\",\"path\":\""
                    + artifact.file.getAbsolutePath().replace('\\', '/') + "\",\"file_sha256\":\"" + artifact.sha256
                    + "\",\"payload_sha256\":\"" + artifact.payloadSha256 + "\"}";
            Files.writeString(root.resolve(kind).resolve("file-manifest.json"), report, StandardCharsets.UTF_8);
            System.out.println(report);
        }
    }
}
