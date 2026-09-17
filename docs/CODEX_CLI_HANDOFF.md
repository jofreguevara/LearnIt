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

La versión v0.5.0 integra la ruta real de host: ABI v3 con jobs de STT, diálogo
y TTS, adaptadores CPU opt-in de `whisper.cpp`, `llama.cpp` y Supertonic/ONNX
Runtime, y engines Dart que consumen solo rutas verificadas por
`ModelManager`. El smoke combinado usa Qwen3.5 0.8B y el bundle Supertonic 3.
El build y el modo demo siguen siendo predeterminados sin los checkouts y
modelos locales; Android/iOS físicos, pantalla bloqueada y métricas de campo
siguen pendientes.

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

La validación de v0.5.0 produjo tests Flutter pasados, análisis sin incidencias,
CTest nativo con ABI vacía y con cada combinación de runtimes, además de un
smoke combinado real contra Qwen3.5 0.8B y Supertonic 3. La validación de
artefactos y las cifras de referencia de host se mantienen en
[`docs/FASE1_VALIDACION.md`](FASE1_VALIDACION.md).

## Artefactos recientes

- APK release: `build/app/outputs/flutter-apk/app-release.apk` (53,3 MB).
- App Bundle: `build/app/outputs/bundle/release/app-release.aab` (51,9 MB).
- Biblioteca C++: `build/native/liblearnit_core.so`.

El APK release usa la clave debug provisional y sirve para pruebas locales;
configurar firma propia antes de distribuirlo. No había ningún dispositivo
conectado por ADB durante la compilación.

## Pendientes prioritarios

1. Medir latencia, RAM, temperatura y batería en teléfonos físicos; validar
   sesiones bloqueadas, llamadas, auriculares, presión de memoria y modo avión.
2. Ejecutar el corpus bilingüe y los 100 casos educativos con los artefactos
   exactos; conservar la matriz de resultados.
3. Revisar cifrado/backup de SQLite, borrado de datos derivados y migraciones.
4. Compilar iOS en macOS con Xcode; el proyecto ya está configurado para iOS
   16, micrófono y audio en segundo plano.
5. Distribuir ONNX Runtime y los runtimes CPU para todas las ABIs móviles.
6. Adjuntar revisión legal de OpenRAIL-M/cuantizaciones y añadir firma Android
   de release antes de preparar fichas de tienda.

## Archivos de referencia

- Especificación: `docs/PLAN_TECNICO.md`.
- Guía de contribución: `AGENTS.md`.
- Estado y comandos generales: `README.md`.
- Orquestación de sesión: `lib/services/session_controller.dart`.
- Catálogo y verificación de modelos: `lib/services/model_manager.dart`.
