package com.inrego.babymonitarr

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
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
        private const val actionStart = "com.inrego.babymonitarr.action.START_MONITORING"
        private const val actionUpdate = "com.inrego.babymonitarr.action.UPDATE_MONITORING"
        private const val extraTitle = "title"
        private const val extraBody = "body"
        private const val wakeLockTag = "BabyMonitarr:MonitoringCpuWakeLock"
        private const val wifiLockTag = "BabyMonitarr:MonitoringWifiLock"
        private const val mediaSessionTag = "BabyMonitarrMonitoring"
        private const val logger = "MonitoringService"

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

    // Held so OEM freezers (ColorOS "Hans") see an app that owns audio focus
    // and an active media session. flutter_webrtc runs with
    // manageAudioFocus: false, so otherwise nobody requests focus.
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioFocusHeld = false
    private var audioFocusPending = false
    private var mediaSession: MediaSession? = null

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        onAudioFocusChanged(change)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        currentTitle = intent?.getStringExtra(extraTitle) ?: currentTitle
        currentBody = intent?.getStringExtra(extraBody) ?: currentBody

        startAsForeground(currentTitle, currentBody)
        acquireLocks()
        requestAudioFocus()
        updateMediaSession()

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
        releaseMediaSession()
        abandonAudioFocus()
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
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Failed to acquire wake lock", t)
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
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Failed to release wake lock", t)
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
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Failed to acquire Wi-Fi lock", t)
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
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Failed to release Wi-Fi lock", t)
        }
    }

    private fun audioManager(): AudioManager =
        getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun requestAudioFocus() {
        if (audioFocusHeld || audioFocusPending) return
        try {
            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = audioFocusRequest ?: AudioFocusRequest.Builder(
                    AudioManager.AUDIOFOCUS_GAIN,
                )
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setAcceptsDelayedFocusGain(true)
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener(audioFocusListener)
                    .build()
                    .also { audioFocusRequest = it }
                audioManager().requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audioManager().requestAudioFocus(
                    audioFocusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN,
                )
            }
            when (result) {
                AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> {
                    audioFocusHeld = true
                    NativeLog.info(logger, "Audio focus requested: granted")
                }

                AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> {
                    audioFocusPending = true
                    NativeLog.info(logger, "Audio focus requested: delayed")
                }

                else -> NativeLog.warning(logger, "Audio focus requested: failed")
            }
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Audio focus requested: failed", t)
        }
    }

    private fun onAudioFocusChanged(change: Int) {
        NativeLog.info(logger, "Audio focus changed: ${audioFocusChangeName(change)}")
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                audioFocusHeld = true
                audioFocusPending = false
            }

            AudioManager.AUDIOFOCUS_LOSS -> {
                // Permanent loss: don't fight it. The next onStartCommand
                // (Dart calls updateMonitoringService on status changes)
                // re-requests focus.
                audioFocusHeld = false
                audioFocusPending = false
                NativeLog.warning(
                    logger,
                    "Audio focus lost permanently; will re-request on next service update",
                )
            }

            // Transient loss or duck (e.g. a phone call): leave WebRTC
            // playout untouched and wait for the system to return focus.
            else -> Unit
        }
    }

    private fun audioFocusChangeName(change: Int): String = when (change) {
        AudioManager.AUDIOFOCUS_GAIN -> "GAIN"
        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT -> "GAIN_TRANSIENT"
        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK -> "GAIN_TRANSIENT_MAY_DUCK"
        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE -> "GAIN_TRANSIENT_EXCLUSIVE"
        AudioManager.AUDIOFOCUS_LOSS -> "LOSS"
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "LOSS_TRANSIENT"
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "LOSS_TRANSIENT_CAN_DUCK"
        else -> "UNKNOWN($change)"
    }

    private fun abandonAudioFocus() {
        val wasRequested = audioFocusHeld || audioFocusPending
        audioFocusHeld = false
        audioFocusPending = false
        if (!wasRequested) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { audioManager().abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                audioManager().abandonAudioFocus(audioFocusListener)
            }
            NativeLog.info(logger, "Audio focus abandoned")
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Failed to abandon audio focus", t)
        }
    }

    private fun updateMediaSession() {
        try {
            val session = mediaSession ?: MediaSession(this, mediaSessionTag).also {
                it.setCallback(
                    object : MediaSession.Callback() {
                        override fun onPlay() {
                            NativeLog.info(logger, "MediaSession onPlay ignored")
                        }

                        override fun onPause() {
                            NativeLog.info(logger, "MediaSession onPause ignored")
                        }

                        override fun onStop() {
                            NativeLog.info(logger, "MediaSession onStop ignored")
                        }
                    },
                )
                mediaSession = it
            }
            session.setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, "BabyMonitarr")
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, currentBody)
                    .build(),
            )
            session.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY or
                            PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_STOP,
                    )
                    .setState(
                        PlaybackState.STATE_PLAYING,
                        PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                        1.0f,
                    )
                    .build(),
            )
            if (!session.isActive) {
                session.isActive = true
                NativeLog.info(logger, "MediaSession active (PLAYING)")
            }
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Failed to set up MediaSession", t)
        }
    }

    private fun releaseMediaSession() {
        val session = mediaSession
        mediaSession = null
        if (session == null) return
        try {
            session.isActive = false
            session.release()
            NativeLog.info(logger, "MediaSession released")
        } catch (t: Throwable) {
            NativeLog.warning(logger, "Failed to release MediaSession", t)
        }
    }
}
