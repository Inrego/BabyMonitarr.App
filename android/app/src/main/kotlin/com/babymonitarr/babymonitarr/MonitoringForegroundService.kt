package com.babymonitarr.babymonitarr

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class MonitoringForegroundService : Service() {
    companion object {
        private const val channelId = "babymonitarr_monitoring_service_native"
        private const val channelName = "BabyMonitarr Monitoring"
        private const val notificationId = 17001
        private const val actionStart = "com.babymonitarr.babymonitarr.action.START_MONITORING"
        private const val actionUpdate = "com.babymonitarr.babymonitarr.action.UPDATE_MONITORING"
        private const val extraTitle = "title"
        private const val extraBody = "body"
        private const val wakeLockTag = "BabyMonitarr:MonitoringCpuWakeLock"
        private const val wifiLockTag = "BabyMonitarr:MonitoringWifiLock"

        fun start(context: Context, title: String?, body: String?) {
            val intent = Intent(context, MonitoringForegroundService::class.java).apply {
                action = actionStart
                putExtra(extraTitle, title)
                putExtra(extraBody, body)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun update(context: Context, title: String?, body: String?) {
            val intent = Intent(context, MonitoringForegroundService::class.java).apply {
                action = actionUpdate
                putExtra(extraTitle, title)
                putExtra(extraBody, body)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MonitoringForegroundService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var currentTitle = "BabyMonitarr"
    private var currentBody = "Monitoring active in background"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        currentTitle = intent?.getStringExtra(extraTitle) ?: currentTitle
        currentBody = intent?.getStringExtra(extraBody) ?: currentBody

        startAsForeground(currentTitle, currentBody)
        acquireLocks()

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val restartIntent = Intent(applicationContext, MonitoringForegroundService::class.java).apply {
            action = actionUpdate
            putExtra(extraTitle, currentTitle)
            putExtra(extraBody, currentBody)
        }
        ContextCompat.startForegroundService(applicationContext, restartIntent)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseLocks()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun startAsForeground(title: String, body: String) {
        createChannelIfNeeded()
        val notification = buildNotification(title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(notificationId, notification)
        }
    }

    private fun buildNotification(title: String, body: String): Notification {
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            } ?: Intent(this, MainActivity::class.java)

        val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            pendingIntentFlags,
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows when baby monitoring is actively running."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireLocks() {
        acquireWakeLock()
        acquireWifiLock()
    }

    private fun releaseLocks() {
        releaseWakeLock()
        releaseWifiLock()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val manager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = manager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, wakeLockTag).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Throwable) {
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock
        wakeLock = null
        if (lock == null) return
        try {
            if (lock.isHeld) {
                lock.release()
            }
        } catch (_: Throwable) {
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireWifiLock() {
        if (wifiLock?.isHeld == true) return
        try {
            val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = manager.createWifiLock(mode, wifiLockTag).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Throwable) {
        }
    }

    private fun releaseWifiLock() {
        val lock = wifiLock
        wifiLock = null
        if (lock == null) return
        try {
            if (lock.isHeld) {
                lock.release()
            }
        } catch (_: Throwable) {
        }
    }
}
