package com.example.earanyak

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.earanyak/content_protection"
    }

    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableProtection" -> {
                    enableFlagSecure()
                    result.success(true)
                }
                "disableProtection" -> {
                    disableFlagSecure()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        setupAndroid14ScreenshotDetection()
    }

    private fun enableFlagSecure() {
        runOnUiThread {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun disableFlagSecure() {
        runOnUiThread {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun setupAndroid14ScreenshotDetection() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                registerScreenCaptureCallback(mainExecutor) {
                    runOnUiThread {
                        methodChannel?.invokeMethod(
                            "onScreenshotDetected",
                            mapOf("timestamp" to System.currentTimeMillis())
                        )
                    }
                }
            } catch (_: Exception) {
            }
        }
    }
}
