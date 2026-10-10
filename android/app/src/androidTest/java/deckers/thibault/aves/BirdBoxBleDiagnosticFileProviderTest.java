package deckers.thibault.aves;
import android.content.*;
import android.net.Uri;
import androidx.core.content.FileProvider;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import static org.junit.Assert.*;
import java.io.*;
public class BirdBoxBleDiagnosticFileProviderTest {
    @Test public void onlyDedicatedCacheDirectoryIsShareable() throws Exception {
        Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        File directory=new File(context.getCacheDir(),"ble_diagnostics");directory.mkdirs();
        File file=new File(directory,"BirdBox_BLE_provider_test.json");
        try(FileOutputStream out=new FileOutputStream(file)){out.write("{}".getBytes());}
        try {
            Uri uri=FileProvider.getUriForFile(context,context.getPackageName()+".ble_diagnostics",file);
            assertEquals("content",uri.getScheme());
            Intent intent=BirdBoxBleDiagnosticFileChannel.shareIntent(uri,"application/json");
            assertEquals(Intent.ACTION_SEND,intent.getAction());assertEquals(uri,intent.getParcelableExtra(Intent.EXTRA_STREAM));
            assertEquals(uri,intent.getClipData().getItemAt(0).getUri());
            assertTrue((intent.getFlags()&Intent.FLAG_GRANT_READ_URI_PERMISSION)!=0);
            try {FileProvider.getUriForFile(context,context.getPackageName()+".ble_diagnostics",new File(context.getCacheDir(),"outside.json"));fail("outside cache must not be exposed");}
            catch(IllegalArgumentException expected){}
        } finally {file.delete();}
    }
}
