# Historial de cambios

## 0.7.0 — 2026-09-18

- Añadida la sección de modelos locales en Ajustes, compartiendo el mismo
  `ModelManager` que el arranque nativo.
- Añadida descarga de Whisper base, Qwen3.5 0.8B y el bundle Supertonic 3 con
  progreso, verificación, activación y eliminación desde Flutter.
- Añadida cancelación cooperativa de descargas; los archivos `.part` se
  conservan para reanudar transferencias y los bundles se promueven atómicamente.
- Añadido permiso de Internet para el manifiesto release de Android y aviso de
  reinicio después de activar nuevos pesos.
- El puente nativo se intenta cargar por defecto, manteniendo los motores demo
  si todavía no hay pesos verificados o un backend compatible.
- Actualizada la versión Flutter a `0.7.0+7`; análisis y 27 tests Flutter pasan.
- Siguen pendientes las pruebas físicas, las descargas en segundo plano, iOS y
  las métricas de campo de la cadena completa.

## 0.6.0 — 2026-09-17

- Compilado ONNX Runtime 1.23.1 para Android arm64-v8a y x86_64 con
  c++_shared, biblioteca compartida y reducción a los operadores usados por
  el bundle verificado de Supertonic 3.
- Añadidos tool/build_onnxruntime_android.sh y
  tool/validate_onnxruntime_android.sh, con checkout, NDK, API, hashes,
  manifiesto y validación ELF fijados.
- CMake selecciona el subpaquete según ANDROID_ABI, valida abi.txt y la
  versión, e importa libonnxruntime.so sin posibilidad de enlazar por
  accidente la distribución Linux de host.
- Publicada la versión del runtime y ABI móvil en learnit_core_capabilities;
  actualizado Flutter a 0.6.0+6.
- El enlace iOS y las pruebas en dispositivos físicos siguen pendientes:
  Linux solo puede verificar la compilación cruzada y el empaquetado.

## 0.5.0 — 2026-09-17

- Actualizada la ABI C a v3 con jobs asíncronos para diálogo y síntesis TTS.
- Integrado `llama.cpp` CPU con Qwen3.5 GGUF y contexto JSON de la sesión.
- Integrado Supertonic 3 mediante su helper C++ y ONNX Runtime, con WAV
  PCM16 mono y voz verificada `M1`.
- Conectados `NativeLlamaDialogueEngine` y
  `NativeSupertonicSynthesizer` al flujo Flutter cuando hay modelos/bundles
  verificados.
- Añadida prueba nativa combinada y actualizado Flutter a `0.5.0+5`.
- Manteniendo runtimes opt-in y pendientes las pruebas Android/iOS físicas,
  bloqueo de pantalla y métricas de campo.

## 0.4.0 — 2026-09-17

- Añadida ABI C v2 con sesiones nativas opacas, jobs de transcripción
  asíncronos, cancelación y sobres JSON de éxito/error.
- Añadido adaptador CPU de `whisper.cpp` con PCM16 mono a 16 kHz, detección de
  idioma EN/ES y confianza agregada por tokens.
- Añadido enlace CMake opcional a un checkout fijado de `whisper.cpp`, sin
  cambiar el build demo por defecto.
- Añadido `NativeSpeechRecognizer` y entrega de rutas verificadas desde
  `ModelManager`.
- Añadido smoke executable para validar STT real con el modelo de Fase 1.
- Actualizada la versión Flutter a `0.4.0+4`.

## 0.3.0 — 2026-09-17

- Cerrado el manifiesto reproducible de la Fase 1 con revisiones, URLs,
  licencias, tamaños y SHA-256 de los artefactos candidatos.
- Fijados Whisper base `q5_1` y Qwen3.5 0.8B `Q4_0`; documentados tiny, 2B y
  4B como comparaciones, dejando clara la procedencia de cuantizaciones de
  terceros.
- Añadido `ModelBundle` con importación, descarga, verificación y activación
  atómica para el bundle multiarchivo de Supertonic 3.
- Añadido seguimiento seguro de redirecciones HTTPS y reanudación de descargas.
- Añadidas capacidades/versionado del ABI nativo y el smoke test CTest.
- Añadidos `tool/validate_phase1_artifacts.sh`,
  `tool/phase1_host_smoke.sh` y el acta de validación de Fase 1.
- Dejadas explícitas como pendientes la integración nativa real, las pruebas
  de dispositivos físicos, la calidad educativa y la revisión legal final.

## 0.2.0 — 2026-09-17

- Añadida validación de metadatos para impedir activar paquetes sin versión,
  tamaño o SHA-256 fijados.
- Instalación de modelos mediante archivos temporales verificados antes de
  sustituir el paquete activo.
- Añadida lectura y escritura atómica del manifiesto local de modelos.
- Añadido `NativeDialogueEngine`, que valida el sobre JSON del puente nativo y
  convierte errores de contrato en fallos recuperables de sesión.
- Actualizado el ABI nativo al identificador `learnit-core/0.2-native-spike`.
- Añadida cobertura de tests para manifiestos, sustituciones atómicas,
  metadatos pendientes y respuestas nativas incompletas.

Esta versión sigue usando el modo demo por defecto. Los pesos y adaptadores
finales de Whisper, Qwen y Supertonic requieren cerrar la prueba de viabilidad
en dispositivos físicos.
