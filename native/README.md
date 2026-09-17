# Núcleo nativo

`core/` expone un ABI C v3 para que Flutter pueda cargar una biblioteca
compartida con `dart:ffi`. El ABI conserva el diálogo demo, añade sesiones
opacas y jobs asíncronos para STT, diálogo y TTS. `whisper.cpp`, `llama.cpp` y
Supertonic 3/ONNX Runtime se habilitan explícitamente; ninguno se descarga por
defecto.

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

## Build con llama.cpp y Supertonic 3

Los checkouts usados por la validación son `llama.cpp`
`b49650adb31f2e49a0d76113aeb1792134fd8413`, Supertonic
`1e9799e964ea4c0dad7cde993b65c3c813a7b373` y el bundle de modelos fijado en
`aafc6e32416a594460b32413efc49d7fe4ce6d46`. Supertonic requiere la distribución
de desarrollo C++ de ONNX Runtime 1.23.1; el runtime Python no aporta los
headers necesarios.

```bash
cmake -S native/core -B build/native-v0.5-all \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
  -DLEARNIT_WITH_LLAMA=ON \
  -DLEARNIT_LLAMA_ROOT="$PWD/build/phase1/upstream/llama.cpp" \
  -DLEARNIT_WITH_WHISPER=ON \
  -DLEARNIT_WHISPER_ROOT="$PWD/build/phase1/upstream/whisper.cpp" \
  -DLEARNIT_WITH_SUPERTONIC=ON \
  -DLEARNIT_SUPERTONIC_ROOT="$PWD/build/phase1/upstream/supertonic" \
  -DLEARNIT_ONNXRUNTIME_ROOT="$PWD/build/phase1/onnxruntime-1.23.1"
cmake --build build/native-v0.5-all --parallel 2
ctest --test-dir build/native-v0.5-all --output-on-failure
LD_LIBRARY_PATH="$PWD/build/phase1/onnxruntime-1.23.1/lib" \
  build/native-v0.5-all/learnit_native_smoke \
  --llama build/phase1/models/Qwen3.5-0.8B-Q4_0.gguf \
  --tts-dir build/phase1/models/supertonic-3/onnx \
  --voice build/phase1/models/supertonic-3/voice_styles/M1.json
```

La reproducción completa también está disponible en
[`tool/v05_native_smoke.sh`](../tool/v05_native_smoke.sh); las variables
`V05_*` permiten apuntar a otras rutas fijadas sin modificar el repositorio.

El smoke imprime el sobre de diálogo y confirma que TTS devolvió audio WAV.
Para Android, `LEARNIT_WITH_LLAMA`, `LEARNIT_WITH_SUPERTONIC` y las rutas se
leen de variables de entorno durante el configure Gradle. ONNX Runtime debe
ser compilado o descargado para cada ABI Android; la distribución Linux del
ejemplo anterior solo sirve para host.

## Estado de la integración

- `NativeLlamaDialogueEngine` construye un request JSON con contexto de nivel,
  compañero, memoria y resumen; admite JSON de segmentos o texto de reserva y
  elimina bloques de razonamiento antes de hablar.
- `NativeSupertonicSynthesizer` valida WAV PCM16 mono, calcula la onda y
  entrega `SynthesizedAudio` al playback existente.
- `learnit_native_smoke` ejecuta los dos jobs por la ABI v3 con los artefactos
  locales exactos.

## Siguiente integración

1. Compilar ARM64 para Android y el framework/XCFramework de iOS; mantener
   CPU como ruta de pantalla bloqueada.
2. Ejecutar la matriz de latencia, RAM, temperatura y batería con los pesos
   exactos que se distribuirán.

El `NativeDialogueEngine` conserva el adaptador demo/compatibilidad; el camino
real usa `NativeLlamaDialogueEngine`. `NativeSupertonicSynthesizer` valida el
audio devuelto por el backend y `NativeSpeechRecognizer` valida el sobre JSON
de STT. `learnit_core_capabilities` deja explícito qué backends fueron
compilados.
