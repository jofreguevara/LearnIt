# Núcleo nativo

`core/` expone un ABI C pequeño para que Flutter pueda cargar una biblioteca compartida con `dart:ffi`. La implementación actual (`learnit_core/0.1-demo`) solo verifica el puente y devuelve una respuesta de demostración; no pretende sustituir un modelo.

## Fase 1

Para comprobar solo el ABI durante el spike:

```bash
cmake -S native/core -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native
```

El artefacto resultante debe copiarse como `liblearnit_core.so` en cada ABI de
Android o empaquetarse como framework de iOS; el host generado por Flutter se
encarga del resto del enlace.

1. Fijar revisiones y hashes de `whisper.cpp`, `llama.cpp`, ONNX Runtime y los artefactos de voz.
2. Implementar adaptadores que respeten las interfaces Dart de `SpeechRecognizer`, `DialogueEngine` y `SpeechSynthesizer`.
3. Compilar ARM64 para Android y el framework/XCFramework de iOS; mantener CPU como ruta de pantalla bloqueada.
4. Exponer buffers cancelables y liberar toda memoria que cruce el ABI.
5. Ejecutar la matriz de rendimiento de `docs/PLAN_TECNICO.md` con los pesos exactos que se distribuirán.

La aplicación no descarga modelos desde el núcleo. `ModelManager` aprovisiona, verifica SHA-256 y activa un único paquete por perfil; el núcleo recibe únicamente una ruta local validada.
