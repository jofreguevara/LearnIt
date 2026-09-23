package com.example.learnit

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter channel for starting and stopping a user-initiated audio session. */
class AudioSessionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: android.content.Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "learnit/audio_session")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                try {
                    val intent = Intent(context, LocalSessionService::class.java)
                    ContextCompat.startForegroundService(context, intent)
                    result.success(null)
                } catch (error: SecurityException) {
                    result.error(
                        "BACKGROUND_AUDIO_PERMISSION",
                        "Activa el permiso de micrófono y la actividad en segundo plano para LearnIt.",
                        error.message,
                    )
                } catch (error: Exception) {
                    result.error(
                        "BACKGROUND_AUDIO_UNAVAILABLE",
                        "No se pudo mantener la sesión en segundo plano.",
                        error.message,
                    )
                }
            }
            "pause" -> result.success(null)
            "resume" -> result.success(null)
            "finish" -> {
                context.stopService(Intent(context, LocalSessionService::class.java))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
