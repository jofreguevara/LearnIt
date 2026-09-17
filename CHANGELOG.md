# Historial de cambios

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
