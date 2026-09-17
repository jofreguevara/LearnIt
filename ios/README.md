# Integración iOS

`AudioSessionCoordinator.swift` prepara `AVAudioSession.playAndRecord` para una sesión iniciada por el usuario. El proyecto Xcode debe añadir:

- `NSMicrophoneUsageDescription` con una explicación visible para el usuario.
- `UIBackgroundModes` con el valor `audio`.
- ARM64 como arquitectura de dispositivo y una versión mínima inicial de iOS 16.

`Runner/AppDelegate.swift` registra `AudioSessionPlugin` junto con `GeneratedPluginRegistrant` para exponer el canal `learnit/audio_session`. Si el host Flutter se regenera y reemplaza ese archivo, conserva ese registro explícito.

El host Flutter debe activar la sesión antes de bloquear la pantalla, observar interrupciones y liberar el audio al pausar o finalizar. No se debe iniciar inferencia GPU/Metal nueva al pasar a background; la ruta de compatibilidad utiliza CPU. Probar bloqueo, llamadas, Siri, auriculares, reinicio, protección de archivos `afterFirstUnlock` y terminación del proceso.
