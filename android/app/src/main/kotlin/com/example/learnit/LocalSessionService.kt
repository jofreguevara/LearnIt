package com.example.learnit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Owns the audio session while a user-initiated conversation continues with
 * the screen locked. Inference itself is coordinated by the shared native core.
 */
class LocalSessionService : Service() {
    override fun onCreate() {
        super.onCreate()
        createChannel()
        val notification = buildNotification()
        val foregroundType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        } else {
            0
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, foregroundType)
        } catch (error: Exception) {
            Log.e(TAG, "Unable to start LearnIt foreground audio service", error)
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_FINISH -> stopSelf()
            ACTION_PAUSE -> {
                // The Flutter/native coordinator observes this state through
                // the platform channel and stops microphone capture.
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        // The audio capture implementation releases its recorder before this
        // service is stopped. Do not restart a session without user action.
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        val pauseIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, LocalSessionService::class.java).setAction(ACTION_PAUSE),
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        val finishIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, LocalSessionService::class.java).setAction(ACTION_FINISH),
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("LearnIt está practicando contigo")
            .setContentText("La sesión sigue activa; toca para volver a LearnIt.")
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "Pausar", pauseIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Finalizar", finishIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Sesión de práctica",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    companion object {
        private const val TAG = "LearnItSessionService"
        const val CHANNEL_ID = "learnit-session"
        const val NOTIFICATION_ID = 4201
        const val ACTION_PAUSE = "com.example.learnit.action.PAUSE"
        const val ACTION_FINISH = "com.example.learnit.action.FINISH"
    }
}
