package org.handancampus.app;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;
import org.handancampus.app.diagnostics.AcademicDiagnosticsPlugin;
public class MainActivity extends BridgeActivity {
    @Override public void onCreate(Bundle savedInstanceState) {
        if (BuildConfig.DEBUG && BuildConfig.ACADEMIC_DIAGNOSTICS) registerPlugin(AcademicDiagnosticsPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
