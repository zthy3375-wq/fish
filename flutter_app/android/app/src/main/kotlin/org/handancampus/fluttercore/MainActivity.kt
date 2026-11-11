package org.handancampus.fluttercore

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var academic: AcademicSession? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        academic = AcademicSession(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.handancampus.flutter/academic")
            .setMethodCallHandler { call, result -> academic?.handle(call, result) ?: result.error("CANCELLED", "学校连接已关闭", null) }
    }
    override fun onDestroy() {
        academic?.dispose()
        academic = null
        super.onDestroy()
    }
}
