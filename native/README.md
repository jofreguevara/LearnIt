# Núcleo nativo

`core/` expone un ABI C v2 para que Flutter pueda cargar una biblioteca
compartida con `dart:ffi`. El ABI conserva el diálogo demo y añade sesiones
opacas, jobs de STT cancelables y un adaptador CPU real de `whisper.cpp` cuando
se habilita explícitamente su checkout fijado.

## Build sin runtime

Para comprobar solo la ABI:

```bash
cmake -S native/core -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --parallel 2
ctest --test-dir build/native --output-on-failure
```

Este build devuelve un error explícito si se solicita STT sin un backend
Whisper. El artefacto resultante debe copiarse como `liblearnit_core.so` en
cada ABI de Android o empaquetarse como framework de iOS.

## Build con Whisper real

El checkout debe estar fijado al commit usado por la validación de Fase 1:
`da54572229bcf64ba367d96c7ef15770376c4280`. Los pesos permanecen fuera de Git.

```bash
cmake -S native/core -B build/native-v0.4-whisper \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
  -DLEARNIT_WITH_WHISPER=ON \
  -DLEARNIT_WHISPER_ROOT="$PWD/build/phase1/upstream/whisper.cpp"
cmake --build build/native-v0.4-whisper --parallel 2
ctest --test-dir build/native-v0.4-whisper --output-on-failure
LD_LIBRARY_PATH="$PWD/build/native-v0.4-whisper/whisper.cpp/bin:$PWD/build/native-v0.4-whisper" \
  build/native-v0.4-whisper/learnit_whisper_smoke \
  build/phase1/models/ggml-base-q5_1.bin build/phase1/jfk.wav
```

El smoke executable carga el modelo, ejecuta el adaptador a través de la ABI y
devuelve el sobre JSON de transcripción. La entrada es PCM16 mono a 16 kHz.

Para Android se puede pasar la misma ruta desde `android/`. Al cambiar entre
builds con y sin runtime, limpia primero los artefactos nativos:

```bash
./gradlew :app:clean
LEARNIT_WITH_WHISPER=ON \
LEARNIT_WHISPER_ROOT="$PWD/../build/phase1/upstream/whisper.cpp" \
  ./gradlew :app:assembleDebug
```

`ModelManager` es responsable de verificar el archivo y entregar su ruta al
constructor de la sesión. El núcleo no descarga ni valida URLs.

## Siguiente integración

1. Añadir el adaptador llama.cpp y ampliar el request nativo con contexto de
   nivel, compañero, memoria y resumen.
2. Añadir el adaptador ONNX de Supertonic 3 y devolver WAV/PCM al contrato de
   `SpeechSynthesizer`.
3. Compilar ARM64 para Android y el framework/XCFramework de iOS; mantener
   CPU como ruta de pantalla bloqueada.
4. Ejecutar la matriz de latencia, RAM, temperatura y batería con los pesos
   exactos que se distribuirán.

El `NativeDialogueEngine` sigue validando el sobre JSON de diálogo.
`NativeSpeechRecognizer` valida el sobre JSON de STT y
`learnit_core_capabilities` deja explícito si la biblioteca fue compilada con
el backend Whisper.
