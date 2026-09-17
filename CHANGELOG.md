# Historial de cambios

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
