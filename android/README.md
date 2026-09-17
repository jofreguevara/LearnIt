# Integración Android

`LocalSessionService.kt` es el punto de partida para la sesión de voz iniciada desde una actividad visible. El host Flutter debe:

1. Solicitar `RECORD_AUDIO` antes de iniciar la sesión.
2. Lanzar el servicio con `ContextCompat.startForegroundService` mientras la actividad está visible.
3. Detenerlo al pausar o finalizar y liberar el grabador antes de llamar a `stopService`.
4. Declarar en el `AndroidManifest.xml` `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `RECORD_AUDIO` y `android:foregroundServiceType="microphone|mediaPlayback"`.
5. Probar Android 12–17, bloqueo, llamadas, auriculares, presión de memoria y Low Power Standby.

El servicio devuelve `START_NOT_STICKY`: un proceso terminado por el sistema no reanuda el micrófono sin una acción explícita del usuario.
