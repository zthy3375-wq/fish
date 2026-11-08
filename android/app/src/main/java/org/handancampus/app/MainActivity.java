package org.handancampus.app;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;
public class MainActivity extends BridgeActivity {
    @Override public void onCreate(Bundle savedInstanceState) {
        registerPlugin(org.handancampus.app.academic.HandanAcademicPlugin.class);
        registerPlugin(org.handancampus.app.learning.ChaoxingPlugin.class);
        registerPlugin(org.handancampus.app.life.QuzhiPlugin.class);
        registerPlugin(org.handancampus.app.life.ParcelShortcutsPlugin.class);
        registerPlugin(org.handancampus.app.life.PangguaiOfficialPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
