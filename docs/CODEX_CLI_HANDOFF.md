# LearnIt — relevo para Codex CLI

## Estado actual

La aplicación tiene una primera versión vertical en Flutter con cinco áreas
(Inicio, Conversación, Temas, Progreso y Ajustes). El flujo local permite
entrada de texto, captura PCM16 temporal, respuesta bilingüe de demostración,
síntesis WAV en memoria, onda de audio, recuerdos confirmables y resúmenes en
SQLite (con fallback en memoria).

También están preparados los puntos de integración para STT, diálogo, TTS,
memoria y gestión de modelos. El núcleo C++ se compila como `learnit_core` y
se empaqueta en Android para `arm64-v8a`, `armeabi-v7a` y `x86_64` mediante
`android/app/src/main/cpp/CMakeLists.txt`.

La versión v0.4.0 inicia la integración real: el ABI v2 expone sesiones opacas,
jobs de STT cancelables y `NativeSpeechRecognizer`; `learnit_core` puede
enlazar el checkout fijado de `whisper.cpp` por CMake y el smoke executable ya
transcribe el audio de muestra con el modelo real. El build y el modo demo
siguen siendo predeterminados sin ese checkout; llama.cpp, Supertonic, iOS y
las pruebas físicas siguen pendientes.

## Entorno instalado

- Flutter 3.47.4 / Dart 3.13.3: `/home/dev/tools/flutter`.
- Android SDK 36: `/home/dev/android-sdk`.
- Java 17, NDK 27.0.12077973, CMake 3.22.1 (SDK) y Ninja 1.11.1.
- Las rutas persistentes están en `/home/dev/.bashrc`; en una sesión nueva se
  puede ejecutar `source /home/dev/.bashrc`.
- El repositorio Git local está en la rama `main`, con el snapshot inicial
  publicado como `v0.1` en GitHub.

## Validación reproducible

Desde `/home/dev/Dev/LearnIt`:

```bash
flutter pub get
flutter analyze
flutter test
cmake -S native/core -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native
flutter build apk --release
flutter build appbundle --release
```

La validación de v0.4.0 produjo 24 tests Flutter pasados, análisis sin
incidencias, CTest nativo con y sin Whisper pasado y una transcripción real
desde la ABI contra el modelo Whisper base q5_1. La validación de artefactos y
los smoke tests de host para Whisper, Qwen3.5 0.8B y Supertonic 3 mantienen sus
cifras y límites en
[`docs/FASE1_VALIDACION.md`](FASE1_VALIDACION.md).

## Artefactos recientes

- APK release: `build/app/outputs/flutter-apk/app-release.apk` (53,3 MB).
- App Bundle: `build/app/outputs/bundle/release/app-release.aab` (51,9 MB).
- Biblioteca C++: `build/native/liblearnit_core.so`.

El APK release usa la clave debug provisional y sirve para pruebas locales;
configurar firma propia antes de distribuirlo. No había ningún dispositivo
conectado por ADB durante la compilación.

## Pendientes prioritarios

1. Integrar llama.cpp y ONNX Runtime en `learnit_core`/FFI, manteniendo las
   interfaces de `lib/services/engines.dart`.
2. Medir latencia, RAM, temperatura y batería en teléfonos físicos; validar
   sesiones bloqueadas, llamadas, auriculares, presión de memoria y modo avión.
3. Ejecutar el corpus bilingüe y los 100 casos educativos con los artefactos
   exactos; conservar la matriz de resultados.
4. Revisar cifrado/backup de SQLite, borrado de datos derivados y migraciones.
5. Compilar iOS en macOS con Xcode; el proyecto ya está configurado para iOS
   16, micrófono y audio en segundo plano.
6. Adjuntar revisión legal de OpenRAIL-M/cuantizaciones y añadir firma Android
   de release antes de preparar fichas de tienda.

## Archivos de referencia

- Especificación: `docs/PLAN_TECNICO.md`.
- Guía de contribución: `AGENTS.md`.
- Estado y comandos generales: `README.md`.
- Orquestación de sesión: `lib/services/session_controller.dart`.
- Catálogo y verificación de modelos: `lib/services/model_manager.dart`.
