# LearnIt

LearnIt es una aplicación Flutter para practicar inglés con inferencia local. El alcance y la secuencia de implementación están en [`docs/PLAN_TECNICO.md`](docs/PLAN_TECNICO.md).

Para retomar el trabajo desde Codex CLI, consulta el [documento de relevo](docs/CODEX_CLI_HANDOFF.md), que registra el entorno, los comandos y los pendientes.

## Versión 0.5.0

Esta versión integra los dos runtimes pendientes de la Fase 1 dentro del
núcleo C++ y los expone a Flutter mediante jobs asíncronos:

- `llama.cpp` genera el diálogo con Qwen3.5 GGUF y recibe nivel, compañero,
  recuerdos y resumen como contexto verificado;
- Supertonic 3 usa su helper C++ y ONNX Runtime para producir WAV PCM16 mono,
  con la voz `M1` y etiquetas `en`/`es`;
- la ABI C pasa a v3, con entradas separadas para diálogo y TTS, cancelación y
  polling no bloqueante;
- `NativeLlamaDialogueEngine` y `NativeSupertonicSynthesizer` validan los
  sobres nativos y conservan los contratos de Flutter;
- los motores reales solo se activan con modelos instalados y verificados por
  `ModelManager`; sin ellos, la aplicación conserva el modo demo.

El build por defecto sigue sin descargar runtimes. Para reproducir la cadena
real en host se necesitan los checkouts fijados de Fase 1 y un paquete de
desarrollo C++ de ONNX Runtime:

```bash
cmake -S native/core -B build/native-v0.5-all \
  -DBUILD_TESTING=ON \
  -DLEARNIT_WITH_LLAMA=ON \
  -DLEARNIT_LLAMA_ROOT="$PWD/build/phase1/upstream/llama.cpp" \
  -DLEARNIT_WITH_WHISPER=ON \
  -DLEARNIT_WHISPER_ROOT="$PWD/build/phase1/upstream/whisper.cpp" \
  -DLEARNIT_WITH_SUPERTONIC=ON \
  -DLEARNIT_SUPERTONIC_ROOT="$PWD/build/phase1/upstream/supertonic" \
  -DLEARNIT_ONNXRUNTIME_ROOT="$PWD/build/phase1/onnxruntime-1.23.1"
cmake --build build/native-v0.5-all --parallel 2
ctest --test-dir build/native-v0.5-all --output-on-failure
LD_LIBRARY_PATH="$PWD/build/phase1/onnxruntime-1.23.1/lib" \
  build/native-v0.5-all/learnit_native_smoke \
  --llama build/phase1/models/Qwen3.5-0.8B-Q4_0.gguf \
  --tts-dir build/phase1/models/supertonic-3/onnx \
  --voice build/phase1/models/supertonic-3/voice_styles/M1.json
```

El mismo configure, build, CTest y smoke se puede repetir con
[`tool/v05_native_smoke.sh`](tool/v05_native_smoke.sh); acepta variables
`V05_*` para sustituir checkouts, modelos o el directorio de build.

La compilación Android real requiere además una distribución ONNX Runtime
con headers y bibliotecas para cada ABI Android; el archivo Linux usado para
el smoke de host no se puede reutilizar en el APK. La validación en Android e
iOS físicos, pantalla bloqueada y métricas de rendimiento sigue pendiente.

## Versión 0.4.0

Esta versión inicia la integración nativa real de STT:

- el ABI C pasa a v2 con sesiones opacas, carga diferida de modelos y jobs de
  transcripción cancelables sin bloquear el hilo de Flutter;
- `NativeSpeechRecognizer` valida el sobre JSON de Whisper y convierte errores
  nativos en fallos recuperables del `SessionController`;
- `ModelManager.verifiedFileFor()` entrega una ruta local únicamente después
  de comprobar tamaño y SHA-256;
- el núcleo puede enlazar un checkout fijado de `whisper.cpp` mediante CMake,
  manteniendo el build demo sin dependencias externas por defecto;
- se incluye un smoke executable que prueba la transcripción real con el
  modelo Whisper seleccionado y audio PCM16 mono a 16 kHz.

Para compilar el núcleo con el checkout de `whisper.cpp` usado en la matriz de
Fase 1 (`da54572229bcf64ba367d96c7ef15770376c4280`):

```bash
cmake -S native/core -B build/native-v0.4-whisper \
  -DLEARNIT_WITH_WHISPER=ON \
  -DLEARNIT_WHISPER_ROOT="$PWD/build/phase1/upstream/whisper.cpp"
cmake --build build/native-v0.4-whisper --parallel 2
LD_LIBRARY_PATH="$PWD/build/native-v0.4-whisper/whisper.cpp/bin:$PWD/build/native-v0.4-whisper" \
  build/native-v0.4-whisper/learnit_whisper_smoke \
  build/phase1/models/ggml-base-q5_1.bin build/phase1/jfk.wav
```

El APK continúa en modo demo si no se proporciona el checkout de Whisper.
Al cambiar entre builds con y sin runtime, limpia primero los artefactos nativos
para que Gradle regenere la configuración CMake. Para habilitar el backend
durante una compilación Android desde `android/`:

```bash
./gradlew :app:clean
LEARNIT_WITH_WHISPER=ON \
LEARNIT_WHISPER_ROOT="$PWD/../build/phase1/upstream/whisper.cpp" \
  ./gradlew :app:assembleDebug
```

La integración de llama.cpp y Supertonic queda cubierta por v0.5.0; iOS y la
validación en dispositivos físicos siguen siendo los siguientes incrementos.

## Versión 0.3.0

Esta versión cierra el paquete reproducible de ingeniería de la Fase 1:

- `ModelPackage` usa revisiones inmutables y redirecciones HTTPS seguras;
- `ModelBundle` instala de forma atómica los siete artefactos de Supertonic 3;
- el catálogo fija Whisper base `q5_1` y Qwen3.5 0.8B `Q4_0`, con tiny/2B/4B
  descritos como candidatos de comparación;
- el ABI nativo publica capacidades y tiene un smoke test CTest;
- [`docs/FASE1_VALIDACION.md`](docs/FASE1_VALIDACION.md) conserva la matriz,
  las mediciones de host y las puertas que todavía requieren hardware.

Los nueve artefactos seleccionados se verificaron fuera de Git por tamaño y
SHA-256. La aplicación seguía usando modo demo por defecto; v0.4.0 habilita
Whisper únicamente mediante un build explícito y la certificación en teléfonos
continúa pendiente.

Para repetir la validación de artefactos:

```bash
./tool/validate_phase1_artifacts.sh
```

Para repetir los smoke tests de host, después de preparar los ejecutables de
`whisper.cpp`, `llama.cpp` y el ejemplo ONNX de Supertonic:

```bash
./tool/phase1_host_smoke.sh
```

## Versión 0.2.0

Esta versión prepara la infraestructura del spike nativo de la Fase 1:

- `ModelManager` rechaza metadatos de modelos sin versión, tamaño o SHA-256
  fijados antes de descargar o activar un paquete;
- las importaciones y descargas verifican el archivo temporal antes de
  sustituir un modelo instalado;
- el manifiesto local de modelos se puede leer y escribir de forma atómica;
- `NativeDialogueEngine` valida el sobre JSON del puente nativo y mantiene los
  contratos Dart listos para el runtime real.

Los pesos reales todavía no se incluyen ni se seleccionan como paquetes de
producción. El modo demo sigue siendo el comportamiento predeterminado hasta
cerrar las mediciones de la Fase 1.

Para ejecutar el smoke test del diálogo nativo en una build Android que incluya
`liblearnit_core.so`, añade
`--dart-define=LEARNIT_NATIVE_SPIKE=true`. El reconocimiento y la síntesis
continúan en modo demo hasta integrar los runtimes seleccionados.

## Versión 0.6.0

Esta versión añade una distribución móvil reproducible de ONNX Runtime para
Supertonic 3:

- ONNX Runtime 1.23.1 se compila desde el commit fijado
  d9b2048791efb5804fe3d53a04b4971256addebf para arm64-v8a y x86_64;
- cada ABI usa Android API 24, NDK 28.2, c++_shared, biblioteca compartida
  y únicamente los operadores requeridos por los cuatro modelos ONNX de
  Supertonic;
- el paquete se instala en
  build/phase1/onnxruntime-android/1.23.1/<abi>/, con headers, biblioteca,
  metadatos, hashes y manifiesto;
- CMake selecciona automáticamente el subdirectorio de ANDROID_ABI y
  rechaza un abi.txt o versión incompatibles; el validador comprueba además
  la arquitectura ELF;
- learnit_core_capabilities expone la versión de ONNX Runtime y el ABI
  móvil cuando se compila el backend Supertonic.

Para construir y validar los dos paquetes:

    ./tool/build_onnxruntime_android.sh
    ./tool/validate_onnxruntime_android.sh

El builder usa el checkout de ONNX Runtime en
build/phase1/upstream/onnxruntime, una caché local de paquetes Python en
build/phase1/python-packages y el SDK en /home/dev/android-sdk. Se pueden
reemplazar estas rutas con LEARNIT_ORT_SOURCE, LEARNIT_ORT_PYTHONPATH,
ANDROID_SDK_ROOT, LEARNIT_ANDROID_NDK, LEARNIT_ANDROID_API,
LEARNIT_ANDROID_ABIS y LEARNIT_ORT_JOBS.

Para compilar el APK con el paquete real, después de generar ONNX Runtime:

    LEARNIT_ANDROID_ABIS=x86_64 \
    LEARNIT_WITH_SUPERTONIC=ON \
    LEARNIT_SUPERTONIC_ROOT="$PWD/build/phase1/upstream/supertonic" \
    LEARNIT_ONNXRUNTIME_ROOT="$PWD/build/phase1/onnxruntime-android/1.23.1" \
    LEARNIT_NLOHMANN_ROOT="$PWD/build/phase1/upstream/llama.cpp/vendor" \
      flutter build apk --debug --target-platform android-x64

Para arm64-v8a cambia LEARNIT_ANDROID_ABIS a arm64-v8a y usa
android-arm64 en --target-platform. La compilación cruzada y la inspección ELF
no sustituyen las pruebas con teléfono:
siguen pendientes el enlace iOS, audio con pantalla bloqueada y las mediciones
de latencia, RAM, temperatura y batería en dispositivos físicos. El método de
build sigue los parámetros Android documentados por
[ONNX Runtime](https://onnxruntime.ai/docs/build/android.html).

## Versión 0.7.0

Esta versión incorpora la instalación de pesos desde la propia aplicación:

- Ajustes muestra los paquetes básicos de Whisper base y Qwen3.5 0.8B, además
  del bundle de siete artefactos de Supertonic 3 con tamaño y estado local;
- cada descarga informa el progreso, valida tamaño y SHA-256, activa el paquete
  solo después de verificarlo y permite eliminarlo;
- las transferencias se pueden cancelar y reanudar porque conservan su archivo
  `.part`; el bundle se promueve completo para no dejar una instalación parcial;
- el APK release declara permiso de Internet únicamente para descargar pesos;
  los pesos no se incluyen dentro del APK y la práctica posterior puede ser
  offline;
- tras activar un paquete hay que reiniciar la aplicación para que el arranque
  cree la sesión nativa con las nuevas rutas verificadas. Si falta un backend o
  un modelo, se conserva el modo demo.

La pantalla está preparada para una instalación inicial visible, pero todavía
no descarga en segundo plano después de terminar la actividad ni sustituye la
validación física de Android/iOS, audio con pantalla bloqueada y métricas de
latencia, RAM, temperatura y batería.

La APK release arm64 validada se puede regenerar con los tres backends nativos
así (los pesos siguen siendo una descarga posterior desde Ajustes):

```bash
LEARNIT_ANDROID_ABIS=arm64-v8a \
LEARNIT_WITH_LLAMA=ON \
LEARNIT_LLAMA_ROOT="$PWD/build/phase1/upstream/llama.cpp" \
LEARNIT_WITH_WHISPER=ON \
LEARNIT_WHISPER_ROOT="$PWD/build/phase1/upstream/whisper.cpp" \
LEARNIT_WITH_SUPERTONIC=ON \
LEARNIT_SUPERTONIC_ROOT="$PWD/build/phase1/upstream/supertonic" \
LEARNIT_ONNXRUNTIME_ROOT="$PWD/build/phase1/onnxruntime-android/1.23.1" \
LEARNIT_NLOHMANN_ROOT="$PWD/build/phase1/upstream/llama.cpp/vendor" \
  flutter build apk --release --target-platform android-arm64
```

## Estado actual

La base inicial contiene:

- una interfaz Flutter ligera con Inicio, Conversación, Temas, Progreso y Ajustes;
- un flujo de conversación textual local para probar estados y persistencia sin descargar modelos;
- captura PCM16 temporal y reproducción de audio local para validar el ciclo de un turno;
- configuración de personalidad, correcciones, velocidad de voz y recuerdos con confirmación/edición/borrado;
- contratos sustituibles para STT, LLM, TTS, memoria y gestión de modelos;
- un núcleo C++ con ABI v3 y adaptadores opcionales de `whisper.cpp`,
  `llama.cpp` y Supertonic/ONNX Runtime;
- integración nativa inicial para las sesiones de audio en Android e iOS.

Los modelos y sus pesos no se incluyen en el repositorio. La aplicación muestra
el modo de demostración hasta que se instalen paquetes/bundles verificados por
`ModelManager`; cada runtime real recibe únicamente la ruta local resultante de
esa verificación.

## Desarrollo y compilación

El entorno verificado usa Flutter 3.47.4/Dart 3.13.3 en
`/home/dev/tools/flutter`, Android SDK 36 en `/home/dev/android-sdk`, Java 17,
NDK 27.0.12077973, CMake 3.28 y Ninja 1.11. Las nuevas terminales cargan estas
rutas desde `/home/dev/.bashrc`.

```bash
flutter pub get
flutter analyze
flutter test
cmake -S native/core -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native
ctest --test-dir build/native --output-on-failure
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
```

Si se elimina un host de plataforma, se puede regenerar con
`flutter create --platforms=android,ios .`. La compilación iOS requiere macOS y
Xcode; el proyecto y la integración nativa están versionados para ejecutarla
allí.

Para ejecutar la validación de audio bloqueado se necesitan dispositivos físicos. Consulta la guía de contribución en [`AGENTS.md`](AGENTS.md) antes de modificar el núcleo nativo.
