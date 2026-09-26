package com.inrego.babymonitarr

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Logs native events to logcat and forwards them to Dart's file logger via
 * the `babymonitarr/native_log` channel, so native breadcrumbs end up in the
 * same persistent log as the Dart side. Forwarding is best-effort: it is
 * skipped silently when the cached engine isn't available.
 */
object NativeLog {
    private const val tag = "BabyMonitarrNative"
    private const val channelName = "babymonitarr/native_log"
    private const val engineId = "babymonitarr_persistent_engine"

    private val mainHandler = Handler(Looper.getMainLooper())

    fun info(logger: String, message: String) {
        Log.i(tag, "[$logger] $message")
        forward("INFO", logger, message, null)
    }

    fun warning(logger: String, message: String, error: Throwable? = null) {
        Log.w(tag, "[$logger] $message", error)
        forward("WARNING", logger, message, error)
    }

    fun severe(logger: String, message: String, error: Throwable? = null) {
        Log.e(tag, "[$logger] $message", error)
        forward("SEVERE", logger, message, error)
    }

    private fun forward(level: String, logger: String, message: String, error: Throwable?) {
        val errorText = error?.let { Log.getStackTraceString(it) }
        mainHandler.post {
            try {
                val engine = FlutterEngineCache.getInstance().get(engineId) ?: return@post
                MethodChannel(engine.dartExecutor.binaryMessenger, channelName).invokeMethod(
                    "log",
                    mapOf(
                        "level" to level,
                        "logger" to logger,
                        "message" to message,
                        "error" to errorText,
                    ),
                )
            } catch (t: Throwable) {
                Log.w(tag, "Failed to forward native log to Dart", t)
            }
        }
    }
}
