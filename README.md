# LearnIt

LearnIt es una aplicación Flutter para practicar inglés con inferencia local. El alcance y la secuencia de implementación están en [`docs/PLAN_TECNICO.md`](docs/PLAN_TECNICO.md).

Para retomar el trabajo desde Codex CLI, consulta el [documento de relevo](docs/CODEX_CLI_HANDOFF.md), que registra el entorno, los comandos y los pendientes.

## Estado actual

La base inicial contiene:

- una interfaz Flutter ligera con Inicio, Conversación, Temas, Progreso y Ajustes;
- un flujo de conversación textual local para probar estados y persistencia sin descargar modelos;
- captura PCM16 temporal y reproducción de audio local para validar el ciclo de un turno;
- configuración de personalidad, correcciones, velocidad de voz y recuerdos con confirmación/edición/borrado;
- contratos sustituibles para STT, LLM, TTS, memoria y gestión de modelos;
- un núcleo C++ mínimo preparado para enlazar `whisper.cpp`, `llama.cpp` y ONNX Runtime en la Fase 1;
- integración nativa inicial para las sesiones de audio en Android e iOS.

Los modelos y sus pesos no se incluyen en el repositorio. La aplicación muestra el modo de demostración hasta que se instale un paquete verificado por `ModelManager`; el catálogo contiene hashes pendientes de la prueba de viabilidad y no se puede publicar como paquete final todavía.

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
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
```

Si se elimina un host de plataforma, se puede regenerar con
`flutter create --platforms=android,ios .`. La compilación iOS requiere macOS y
Xcode; el proyecto y la integración nativa están versionados para ejecutarla
allí.

Para ejecutar la validación de audio bloqueado se necesitan dispositivos físicos. Consulta la guía de contribución en [`AGENTS.md`](AGENTS.md) antes de modificar el núcleo nativo.
