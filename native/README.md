# Núcleo nativo

`core/` expone un ABI C pequeño para que Flutter pueda cargar una biblioteca compartida con `dart:ffi`. La implementación actual (`learnit-core/0.3-phase1-spike`) publica versión/capacidades, verifica el contrato y devuelve una respuesta de demostración; todavía no pretende sustituir los adaptadores de modelo de producción.

## Fase 1

Para comprobar solo el ABI durante el spike:

```bash
cmake -S native/core -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --parallel 2
ctest --test-dir build/native --output-on-failure
```

El artefacto resultante debe copiarse como `liblearnit_core.so` en cada ABI de
Android o empaquetarse como framework de iOS; el host generado por Flutter se
encarga del resto del enlace.

1. Fijar revisiones y hashes de `whisper.cpp`, `llama.cpp`, ONNX Runtime y los artefactos de voz.
2. Implementar adaptadores que respeten las interfaces Dart de `SpeechRecognizer`, `DialogueEngine` y `SpeechSynthesizer`.
3. Compilar ARM64 para Android y el framework/XCFramework de iOS; mantener CPU como ruta de pantalla bloqueada.
4. Exponer buffers cancelables y liberar toda memoria que cruce el ABI.
5. Ejecutar la matriz de rendimiento de `docs/PLAN_TECNICO.md` con los pesos exactos que se distribuirán.

El `NativeDialogueEngine` de v0.2.0 ya valida el sobre JSON de esta frontera;
la respuesta actual sigue siendo de smoke test mientras los adaptadores reales
se incorporan al núcleo. El endpoint `learnit_core_capabilities` deja explícito
qué componentes están implementados en el ABI actual.

La aplicación lo activa de forma optativa con
`--dart-define=LEARNIT_NATIVE_SPIKE=true`; sin esa bandera conserva el diálogo
demo para no cambiar el flujo por defecto.

La aplicación no descarga modelos desde el núcleo. `ModelManager` aprovisiona,
verifica SHA-256 y activa paquetes o bundles por perfil; el núcleo recibe
únicamente rutas locales validadas.
