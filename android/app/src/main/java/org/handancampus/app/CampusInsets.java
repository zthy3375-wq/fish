package org.handancampus.app;

import android.graphics.Color;
import android.os.Build;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.WebView;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import com.getcapacitor.WebViewListener;

/** Background draws behind status bar; only CSS foreground content receives top clearance. */
final class CampusInsets {
    static void install(MainActivity activity) {
        if (activity.getBridge() == null) return;
        WebView web = activity.getBridge().getWebView();
        WindowCompat.setDecorFitsSystemWindows(activity.getWindow(), false);
        activity.getWindow().setStatusBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= 29) activity.getWindow().setStatusBarContrastEnforced(false);
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams attributes = activity.getWindow().getAttributes();
            attributes.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            activity.getWindow().setAttributes(attributes);
        }
        int[] top = {0};
        Runnable publish = () -> web.evaluateJavascript(
            "(()=>{const s=document.documentElement.style;const d=window.devicePixelRatio||1;" +
            "s.setProperty('--native-safe-top',(" + top[0] + "/d)+'px');" +
            "s.setProperty('--native-safe-bottom','0px');})()", null);
        ViewCompat.setOnApplyWindowInsetsListener(web, (view, windowInsets) -> {
            Insets bars = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            Insets keyboard = windowInsets.getInsets(WindowInsetsCompat.Type.ime());
            top[0] = bars.top;
            ViewGroup.MarginLayoutParams params = (ViewGroup.MarginLayoutParams) view.getLayoutParams();
            int bottom = Math.max(bars.bottom, keyboard.bottom);
            if (params.topMargin != 0 || params.bottomMargin != bottom || params.leftMargin != bars.left || params.rightMargin != bars.right) {
                params.setMargins(bars.left, 0, bars.right, bottom);
                view.setLayoutParams(params);
            }
            publish.run();
            return WindowInsetsCompat.CONSUMED;
        });
        activity.getBridge().addWebViewListener(new WebViewListener() {
            @Override public void onPageLoaded(WebView view) {
                publish.run();
                ViewCompat.requestApplyInsets(view);
            }
        });
        ViewCompat.requestApplyInsets(web);
    }
}
