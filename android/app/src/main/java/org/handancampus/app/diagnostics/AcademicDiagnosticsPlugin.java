package org.handancampus.app.diagnostics;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.content.Context;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import androidx.activity.result.ActivityResult;
import com.getcapacitor.annotation.CapacitorPlugin;
import org.handancampus.app.BuildConfig;

/** App-local, test-build-only commands. Never installed in an external browser or school page. */
@CapacitorPlugin(name = "AcademicDiagnostics")
public class AcademicDiagnosticsPlugin extends Plugin {
    private boolean permitted(PluginCall call) {
        if (!(android.os.Build.VERSION.SDK_INT >= 28 && DiagnosticPolicy.enabled(BuildConfig.DEBUG, BuildConfig.ACADEMIC_DIAGNOSTICS))) {
            call.reject("Diagnostic mode is unavailable", "DIAGNOSTICS_DISABLED");
            return false;
        }
        return true;
    }
    @PluginMethod
    public void getCapabilities(PluginCall call) {
        JSObject result = new JSObject();
        result.put("enabled", android.os.Build.VERSION.SDK_INT >= 28 && DiagnosticPolicy.enabled(BuildConfig.DEBUG, BuildConfig.ACADEMIC_DIAGNOSTICS));
        result.put("schoolPermission", "unverified");
        result.put("canReadPage", false);
        result.put("browser", "external-system-browser");
        call.resolve(result);
    }
    @PluginMethod
    public void openOfficialBrowser(PluginCall call) {
        if (!permitted(call)) return;
        // No URL argument exists: even a hostile caller cannot substitute an origin or deep link.
        if (!DiagnosticPolicy.allowedLaunch(DiagnosticPolicy.OFFICIAL_LOGIN)) {
            call.reject("Official launch policy blocked", "NAVIGATION_BLOCKED"); return;
        }
        ConnectivityManager manager = (ConnectivityManager) getContext().getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkCapabilities network = manager == null ? null : manager.getNetworkCapabilities(manager.getActiveNetwork());
        if (network == null || !network.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            call.reject("Network unavailable", "NETWORK_UNAVAILABLE"); return;
        }
        getActivity().runOnUiThread(() -> {
            try {
                Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(DiagnosticPolicy.OFFICIAL_LOGIN));
                intent.addCategory(Intent.CATEGORY_BROWSABLE);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getActivity().startActivity(intent);
                JSObject result = new JSObject();
                result.put("opened", true);
                result.put("loginStatus", "not-observable");
                call.resolve(result);
            } catch (ActivityNotFoundException e) {
                call.reject("No browser installed", "BROWSER_UNAVAILABLE");
            } catch (SecurityException e) {
                call.reject("Browser launch blocked by device", "BROWSER_BLOCKED");
            }
        });
    }
    @PluginMethod
    public void openSchoolWindow(PluginCall call) {
        if (!permitted(call)) return;
        Intent intent = new Intent(getContext(), SchoolWebActivity.class);
        startActivityForResult(call, intent, "schoolWindowResult");
    }
    @ActivityCallback
    private void schoolWindowResult(PluginCall call, ActivityResult activityResult) {
        if (call == null) return;
        JSObject result = new JSObject();
        Intent data = activityResult.getData();
        if (activityResult.getResultCode() != android.app.Activity.RESULT_OK || data == null) {
            result.put("cancelled", true); call.resolve(result); return;
        }
        try {
            String observation = data.getStringExtra("observation");
            if (observation == null || observation.length()>12000) throw new Exception();
            result.put("observation", new org.json.JSONObject(observation));
            String courses = data.getStringExtra("courses");
            if (courses != null) {
                if (courses.length()>300000) throw new Exception();
                result.put("kbList", new org.json.JSONArray(courses));
            }
            call.resolve(result);
        } catch (Exception e) { call.reject("Invalid structural response", "UNSAFE_RESULT"); }
    }
    @PluginMethod
    public void checkCurrentPage(PluginCall call) {
        if (!permitted(call)) return;
        JSObject result = new JSObject();
        result.put("readPerformed", DiagnosticPolicy.mayReadSchoolPage());
        result.put("reason", "permission-and-browser-isolation");
        // Not a login failure or a compatible-page verdict. No page has been read at all.
        call.resolve(result);
    }
}
