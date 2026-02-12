package com.babymonitarr.babymonitarr

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val lifecycleChannel = "babymonitarr/lifecycle"
        private const val cleanupMethod = "cleanupWebRtcOrientationReceiver"
        private const val tag = "MainActivity"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, lifecycleChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    cleanupMethod -> {
                        cleanupWebRtcOrientationReceiver()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun cleanupWebRtcOrientationReceiver() {
        try {
            val plugin = com.cloudwebrtc.webrtc.FlutterWebRTCPlugin.sharedSingleton ?: return

            val methodCallHandler = plugin.javaClass
                .getDeclaredField("methodCallHandler")
                .apply { isAccessible = true }
                .get(plugin) ?: return

            val cameraUtils = methodCallHandler.javaClass
                .getDeclaredField("cameraUtils")
                .apply { isAccessible = true }
                .get(methodCallHandler) ?: return

            val orientationManager = cameraUtils.javaClass
                .getDeclaredField("deviceOrientationManager")
                .apply { isAccessible = true }
                .get(cameraUtils) ?: return

            orientationManager.javaClass.getMethod("stop").invoke(orientationManager)
        } catch (t: Throwable) {
            Log.w(tag, "Failed to cleanup WebRTC orientation receiver", t)
        }
    }
}
