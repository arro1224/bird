package deckers.thibault.aves;
import org.junit.*;
import org.junit.rules.TemporaryFolder;
import static org.junit.Assert.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.zip.*;
public class BirdBoxDiagnosticFileWriterTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();
    private BirdBoxDiagnosticFileWriter.Artifact write(String name,String payload) throws IOException {
        return BirdBoxDiagnosticFileWriter.write(temporary.getRoot(),name,payload,"{\"export_kind\":\"summary\"}",BirdBoxDiagnosticFileWriter.sha256(payload.getBytes(StandardCharsets.UTF_8)));
    }
    @Test public void jsonUtf8IsLosslessAndFinalDigestMatchesActualBytes() throws Exception {
        String payload="{\"trace_id\":\"鸟🐦\",\"scan_sessions\":[],\"connection_events\":[]}";
        BirdBoxDiagnosticFileWriter.Artifact a=write("BirdBox_BLE_1.14.11_176_model_trace",payload);
        assertEquals("application/json",a.mime);assertEquals(payload,new String(Files.readAllBytes(a.file.toPath()),StandardCharsets.UTF_8));
        assertEquals(a.payloadSha256,a.sha256);assertTrue(BirdBoxDiagnosticFileWriter.verify(a.file,a.sha256));
        assertEquals(1,Objects.requireNonNull(temporary.getRoot().listFiles()).length);
    }
    @Test public void zipContainsSummaryFullUtf8AndReadmeWithDistinctPayloadDigest() throws Exception {
        String payload="{\"data\":\""+"鸟🐦".repeat(100000)+"\"}";
        BirdBoxDiagnosticFileWriter.Artifact a=write("BirdBox_BLE_zip",payload);
        assertEquals("application/zip",a.mime);assertNotEquals(a.sha256,a.payloadSha256);assertEquals(BirdBoxDiagnosticFileWriter.sha256(a.file),a.sha256);
        try(ZipFile zip=new ZipFile(a.file,StandardCharsets.UTF_8)) {
            assertEquals(3,zip.size());
            assertEquals(payload,new String(zip.getInputStream(zip.getEntry("full_trace.json")).readAllBytes(),StandardCharsets.UTF_8));
            String readme=new String(zip.getInputStream(zip.getEntry("README.txt")).readAllBytes(),StandardCharsets.UTF_8);
            assertTrue(readme.contains(a.payloadSha256));assertFalse(readme.contains(a.sha256));assertNotNull(zip.getEntry("summary.json"));
        }
    }
    @Test public void wrongExpectedDigestIsRejectedWithoutWriting() throws Exception {
        try {BirdBoxDiagnosticFileWriter.write(temporary.getRoot(),"BirdBox_BLE_bad","{}","{}","0".repeat(64));fail();}
        catch(IOException e){assertEquals("file_verification_failed",e.getMessage());}
        assertEquals(0,Objects.requireNonNull(temporary.getRoot().listFiles()).length);
    }
    @Test public void subsequentCorruptionFailsVerification() throws Exception {
        BirdBoxDiagnosticFileWriter.Artifact a=write("BirdBox_BLE_corrupt","{}");Files.write(a.file.toPath(),"changed".getBytes(StandardCharsets.UTF_8));assertFalse(BirdBoxDiagnosticFileWriter.verify(a.file,a.sha256));
    }
    @Test public void filenameTraversalIsRejectedAndComponentsAreSanitized() throws Exception {
        assertEquals("model__path___",BirdBoxDiagnosticFileWriter.safeComponent("model:/path ?*"));
        try{write("BirdBox_BLE_../outside","{}");fail();}catch(IOException e){assertEquals("invalid_file_input",e.getMessage());}
    }
    @Test public void chooserFilesAreProtectedAndCacheLimitReturnsAnExplicitFailure() throws Exception {
        for(int i=0;i<BirdBoxDiagnosticFileWriter.MAX_CACHE_FILES;i++){write("BirdBox_BLE_"+i,"{}");}
        try{write("BirdBox_BLE_overflow","{}");fail();}catch(IOException e){assertEquals("diagnostic_cache_full",e.getMessage());}
        assertEquals(32,Objects.requireNonNull(temporary.getRoot().listFiles()).length);
        File oldest=new File(temporary.getRoot(),"BirdBox_BLE_0.json");assertTrue(oldest.setLastModified(System.currentTimeMillis()-8*BirdBoxDiagnosticFileWriter.PROTECTED_AGE_MS));
        assertNotNull(write("BirdBox_BLE_after_expiry","{}"));assertFalse(oldest.exists());
    }
}
