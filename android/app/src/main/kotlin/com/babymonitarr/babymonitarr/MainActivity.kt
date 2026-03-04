package com.babymonitarr.babymonitarr

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.util.Log
import android.util.Rational
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
        private const val pipChannel = "babymonitarr/pip"
        private const val cleanupMethod = "cleanupWebRtcOrientationReceiver"
        private const val startMonitoringServiceMethod = "startMonitoringService"
        private const val updateMonitoringServiceMethod = "updateMonitoringService"
        private const val stopMonitoringServiceMethod = "stopMonitoringService"
        private const val tag = "MainActivity"
        private const val engineId = "babymonitarr_persistent_engine"
    }

    private var pipMethodChannel: MethodChannel? = null

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

        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannel)
        pipMethodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(
                            android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE
                        )
                    )
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val width = call.argument<Int>("aspectRatioWidth") ?: 16
                            val height = call.argument<Int>("aspectRatioHeight") ?: 9
                            val builder = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(width, height))

                            val left = call.argument<Int>("sourceRectHintLeft")
                            val top = call.argument<Int>("sourceRectHintTop")
                            val right = call.argument<Int>("sourceRectHintRight")
                            val bottom = call.argument<Int>("sourceRectHintBottom")
                            if (left != null && top != null && right != null && bottom != null) {
                                builder.setSourceRectHint(Rect(left, top, right, bottom))
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                builder.setSeamlessResizeEnabled(true)
                            }

                            enterPictureInPictureMode(builder.build())
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(tag, "Failed to enter PIP mode", e)
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "exitPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
                        val i = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(i)
                    }
                    result.success(null)
                }
                "isPipActive" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        result.success(isInPictureInPictureMode)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            pipMethodChannel?.invokeMethod("onPipEntered", null)
        } else {
            pipMethodChannel?.invokeMethod("onPipDismissed", null)
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
