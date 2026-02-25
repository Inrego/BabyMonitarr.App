package com.babymonitarr.babymonitarr

import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    companion object {
        private const val lifecycleChannel = "babymonitarr/lifecycle"
        private const val monitoringServiceChannel = "babymonitarr/monitoring_service"
        private const val cleanupMethod = "cleanupWebRtcOrientationReceiver"
        private const val startMonitoringServiceMethod = "startMonitoringService"
        private const val updateMonitoringServiceMethod = "updateMonitoringService"
        private const val stopMonitoringServiceMethod = "stopMonitoringService"
        private const val tag = "MainActivity"
        private const val engineId = "babymonitarr_persistent_engine"
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cached = FlutterEngineCache.getInstance().get(engineId)
        if (cached != null) {
            return cached
        }

        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        GeneratedPluginRegistrant.registerWith(engine)
        FlutterEngineCache.getInstance().put(engineId, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return false
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, monitoringServiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    startMonitoringServiceMethod -> {
                        val args = call.arguments as? Map<*, *>
                        val title = args?.get("title") as? String
                        val body = args?.get("body") as? String
                        MonitoringForegroundService.start(this, title, body)
                        result.success(true)
                    }

                    updateMonitoringServiceMethod -> {
                        val args = call.arguments as? Map<*, *>
                        val title = args?.get("title") as? String
                        val body = args?.get("body") as? String
                        MonitoringForegroundService.update(this, title, body)
                        result.success(true)
                    }

                    stopMonitoringServiceMethod -> {
                        MonitoringForegroundService.stop(this)
                        result.success(true)
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
