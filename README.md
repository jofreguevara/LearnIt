# LearnIt

LearnIt es una aplicación Flutter para practicar inglés con inferencia local. El alcance y la secuencia de implementación están en [`docs/PLAN_TECNICO.md`](docs/PLAN_TECNICO.md).

Para retomar el trabajo desde Codex CLI, consulta el [documento de relevo](docs/CODEX_CLI_HANDOFF.md), que registra el entorno, los comandos y los pendientes.

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
SHA-256. La aplicación sigue usando modo demo por defecto: la integración de
los runtimes reales dentro del núcleo nativo y la certificación en teléfonos
son puertas explícitas antes de abrir la Fase 2.

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
- un núcleo C++ mínimo preparado para enlazar `whisper.cpp`, `llama.cpp` y ONNX Runtime en la Fase 1;
- integración nativa inicial para las sesiones de audio en Android e iOS.

Los modelos y sus pesos no se incluyen en el repositorio. La aplicación muestra
el modo de demostración hasta que se instale un paquete verificado por
`ModelManager`; el catálogo de v0.3.0 fija candidatos de STT/LLM y expone el
bundle TTS, pero no habilita inferencia de producción sin los adaptadores
nativos y las pruebas físicas de [`docs/FASE1_VALIDACION.md`](docs/FASE1_VALIDACION.md).

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
