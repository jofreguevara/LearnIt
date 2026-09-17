# LearnIt

LearnIt es una aplicación Flutter para practicar inglés con inferencia local. El alcance y la secuencia de implementación están en [`docs/PLAN_TECNICO.md`](docs/PLAN_TECNICO.md).

Para retomar el trabajo desde Codex CLI, consulta el [documento de relevo](docs/CODEX_CLI_HANDOFF.md), que registra el entorno, los comandos y los pendientes.

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

La integración de llama.cpp, Supertonic/iOS y la validación en dispositivos
físicos siguen siendo los siguientes incrementos.

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

## Estado actual

La base inicial contiene:

- una interfaz Flutter ligera con Inicio, Conversación, Temas, Progreso y Ajustes;
- un flujo de conversación textual local para probar estados y persistencia sin descargar modelos;
- captura PCM16 temporal y reproducción de audio local para validar el ciclo de un turno;
- configuración de personalidad, correcciones, velocidad de voz y recuerdos con confirmación/edición/borrado;
- contratos sustituibles para STT, LLM, TTS, memoria y gestión de modelos;
- un núcleo C++ con ABI v2 y adaptador opcional de `whisper.cpp`, además de los
  puntos preparados para `llama.cpp` y ONNX Runtime;
- integración nativa inicial para las sesiones de audio en Android e iOS.

Los modelos y sus pesos no se incluyen en el repositorio. La aplicación muestra
el modo de demostración hasta que se instale un paquete verificado por
`ModelManager`; la transcripción real requiere compilar con Whisper y pasar la
ruta del modelo verificado. Diálogo y síntesis siguen en modo demo hasta
integrar sus runtimes.

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
