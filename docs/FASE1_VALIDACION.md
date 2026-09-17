# LearnIt — acta de validación de Fase 1 (`v0.3.0`)

**Fecha:** 2026-09-17<br>
**Resultado:** cierre reproducible del paquete de ingeniería; aceptación móvil pendiente de dispositivos físicos.

Esta acta fija los artefactos que se compararán y conserva la evidencia que sí
puede producirse en el entorno actual. No convierte una medición de Linux en
una promesa de rendimiento para Android o iOS.

## Qué entrega `v0.3.0`

- `ModelPackage` exige una revisión inmutable para descargar por HTTPS y sigue
  verificando tamaño + SHA-256 antes de reemplazar un archivo instalado.
- `ModelBundle` instala y promueve de forma atómica los siete archivos de
  Supertonic 3 que deben viajar juntos.
- El catálogo fija Whisper base `q5_1` y Qwen3.5 0.8B `Q4_0`; los candidatos
  tiny, 2B y 4B quedan disponibles para comparación con procedencia explícita.
- `tool/validate_phase1_artifacts.sh` comprueba el manifiesto y los artefactos
  materializados fuera de Git.
- El ABI nativo publica versión + capacidades y tiene un smoke test CTest
  independiente de Flutter.
- `tool/phase1_host_smoke.sh` repite los smoke tests de STT, LLM y TTS con
  los pesos fijados.

El manifiesto completo, con URL, revisión, licencia, tamaño y SHA-256 por
archivo, está en [`phase1-artifacts.v0.3.json`](phase1-artifacts.v0.3.json).
Los pesos y los ejecutables de prueba viven únicamente bajo `build/phase1/`,
que está excluido del control de versiones.

## Addendum `v0.5.0`

La cadena nativa se amplía a ABI v3. `learnit_core` puede enlazar de forma
opt-in los tres adaptadores CPU: Whisper, llama.cpp y Supertonic 3/ONNX Runtime.
La sesión FFI ahora comparte las rutas verificadas de STT, LLM y TTS, y expone
jobs independientes para transcribir, generar diálogo y sintetizar WAV.

La integración de llama.cpp se probó con el checkout
`b49650adb31f2e49a0d76113aeb1792134fd8413` y el modelo Qwen3.5 0.8B `Q4_0`.
La integración de Supertonic se probó con el checkout
`1e9799e964ea4c0dad7cde993b65c3c813a7b373`, el bundle de siete artefactos de
revisión `aafc6e32416a594460b32413efc49d7fe4ce6d46` y ONNX Runtime C++ 1.23.1.
El smoke combinado devolvió un sobre de diálogo válido y audio WAV de voz M1.

El catálogo Flutter mantiene Supertonic como `ModelBundle`; la ruta que llega
al núcleo se obtiene únicamente con `verifiedBundleDirectory()`. Los pesos y
la distribución ONNX Runtime siguen fuera de Git. La aplicación conserva el
modo demo cuando un backend o sus bytes verificados no están disponibles.

## Matriz de artefactos

| Camino | Candidato fijado | Tamaño | Estado |
|---|---|---:|---|
| STT | Whisper base multilingüe `ggml-base-q5_1.bin` | 59.7 MB | seleccionado para básico |
| STT | Whisper tiny multilingüe `ggml-tiny.bin` | 77.7 MB | comparación |
| LLM básico | Qwen3.5 0.8B `Q4_0` | 563.0 MB | seleccionado para básico |
| LLM comparación | Qwen3.5 2B `Q4_K_M` | 1.27 GB | cuantización de tercero; no distribución |
| LLM avanzado | Qwen3.5 4B `Q4_K_M` | 2.39 GB | cuantización de tercero; no distribución |
| TTS | Supertonic 3: cuatro ONNX + dos índices/config + voz `M1` | 398.7 MB | bundle fijado; licencia pendiente de revisión final |

Los pesos de Whisper proceden del repositorio [`ggerganov/whisper.cpp`](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1). El GGUF básico procede del repositorio oficial de GGML [`Qwen3.5-0.8B-GGUF`](https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/tree/8fea620810c4afa23dd6443f999a48574c1611a3). El bundle TTS procede del archivo oficial [`supertonic-3`](https://huggingface.co/supertone-oss-archive/supertonic-3/tree/aafc6e32416a594460b32413efc49d7fe4ce6d46), que debe conservarse con su aviso OpenRAIL-M; el repositorio está archivado y no recibe soporte nuevo.

El perfil básico suma `1,021,396,639` bytes con el bundle completo, antes de
cachés y espacio temporal. La combinación avanzada con el candidato 4B suma
`2,844,020,767` bytes; queda como comparación hasta revisar la cuantización de
tercero y medirla en el dispositivo objetivo.

## Evidencia reproducible

Desde la raíz del proyecto:

```bash
flutter pub get
flutter analyze
flutter test
cmake -S native/core -B build/native -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build/native --parallel 2
ctest --test-dir build/native --output-on-failure
./tool/validate_phase1_artifacts.sh
./tool/phase1_host_smoke.sh
```

Resultado de esta sesión:

- análisis Flutter: sin incidencias;
- tests Flutter: `22` pasados;
- CTest: `learnit_core_smoke` pasado;
- manifiesto: `9/9` artefactos seleccionados verificados por tamaño y SHA-256;
- Whisper base q5_1 en CPU Linux: transcripción correcta del audio de muestra,
  `3.09 s` y `200,740 KiB` de RSS;
- Qwen3.5 0.8B Q4_0 en CPU Linux, contexto 4096 y un turno: respuesta
  generada, `3.35 s` y `1,037,680 KiB` de RSS;
- Supertonic 3 en ONNX Runtime CPU, voz `M1` para EN y ES: dos WAV generados,
  `4.26 s` de pared y `508,700 KiB` de RSS del proceso.

Los tiempos son una ejecución representativa del host y pueden variar con la
carga; no son umbrales de aceptación móvil.

Los smoke tests de esta sesión usaron `whisper.cpp` en el commit
`da54572229bcf64ba367d96c7ef15770376c4280`, `llama.cpp` en
`b49650adb31f2e49a0d76113aeb1792134fd8413` y el ejemplo Python de Supertonic
en `1e9799e964ea4c0dad7cde993b65c3c813a7b373`.

## Addendum `v0.4.0`

El núcleo ya expone ABI v2 con sesiones opacas, jobs de transcripción
cancelables, polling no bloqueante y transferencia copy-owning de PCM16. El
adaptador CPU de Whisper se enlaza de forma explícita con CMake contra el
checkout fijado anterior y el ejecutable `learnit_whisper_smoke` carga el
modelo base `q5_1` mediante la ABI, detecta inglés y devuelve un sobre JSON con
texto y confianza por tokens.

La ruta Dart correspondiente es `NativeCoreSession` →
`NativeSpeechRecognizer`; `ModelManager.verifiedFileFor()` evita pasar al
núcleo una ruta que no haya superado tamaño y SHA-256. El build sin el checkout
de Whisper continúa disponible para tests y demo.

Esta entrega cubre únicamente STT. No se considera cerrada la cadena
STT → LLM → TTS ni la aceptación móvil: llama.cpp, Supertonic, el enlace iOS,
Android ARM64 en dispositivo físico y las métricas de campo siguen pendientes.

Las cifras anteriores son smoke tests por componente en host. El ABI de LearnIt
sigue marcando `models_verified:false` porque la verificación de hashes es
responsabilidad de Dart/`ModelManager`; el script y el smoke de ABI demuestran
la integración de STT en host, no una integración móvil terminada.

## Puertas de aceptación pendientes

| Puerta | Estado | Motivo / evidencia requerida |
|---|---|---|
| Artefactos, procedencia e integridad | **Pasada** | Manifiesto fijado y `validate_phase1_artifacts.sh` sin errores |
| ABI C++ y contrato Flutter | **Pasada** | CTest y tests Dart pasan; bridge de diálogo valida JSON |
| ABI v3 y STT Whisper en host | **Pasada** | `learnit_whisper_smoke` carga q5_1 y devuelve texto por la ABI |
| STT, LLM y TTS en host | **Pasada** | Smoke reproducible por componente con pesos exactos |
| Cadena nativa integrada STT → LLM → TTS | **Pasada en host** | ABI v3 y smoke combinado ejercitan los jobs de los tres runtimes; falta repetir audio end-to-end en móvil |
| Android ARM64, bloqueo y 30 min | **Pendiente** | No hay dispositivo ADB conectado en este entorno |
| iOS ARM64, bloqueo y 30 min | **Pendiente** | Requiere macOS + Xcode + iPhone físico |
| Latencia, RAM, temperatura y batería móviles | **Pendiente** | Medir frío/caliente, modo avión, ahorro y presión de memoria |
| Corpus bilingüe de 90 turnos | **Pendiente** | Ejecutar EN, ES y mezcla con el paquete exacto |
| 100 casos educativos y falsos positivos | **Pendiente** | Revisión por persona competente en enseñanza de inglés |
| Licencias de bundle y cuantizaciones de tercero | **Pendiente** | Adjuntar avisos y decisión legal antes de distribuir |

Por tanto, `v0.5.0` cierra la integración de host de la Fase 1, pero no la
aceptación pública. La entrada a Fase 2 queda deliberadamente bloqueada hasta
completar las puertas físicas, de rendimiento y de calidad educativa; no se
debe presentar el modo demo como inferencia local de producción.
