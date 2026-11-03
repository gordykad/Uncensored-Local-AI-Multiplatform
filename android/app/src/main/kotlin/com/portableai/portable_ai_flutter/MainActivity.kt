package com.portableai.portable_ai_flutter

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Diagnostics channel (MiniX ticket 01): mirrors the iOS
        // os_proc_available_memory readout with ActivityManager availMem.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "minix/diagnostics")
            .setMethodCallHandler { call, result ->
                if (call.method == "availableMemoryBytes") {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val info = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(info)
                    result.success(info.availMem)
                } else {
                    result.notImplemented()
                }
            }
    }
}
