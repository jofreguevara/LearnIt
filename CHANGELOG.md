# Historial de cambios

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
