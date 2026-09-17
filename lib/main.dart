import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

import 'app.dart';
import 'services/audio_playback.dart';
import 'services/engines.dart';
import 'services/memory_store.dart';
import 'services/model_manager.dart';
import 'services/native_core_bridge.dart';
import 'services/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MemoryStore store;
  try {
    store = await SqfliteMemoryStore.open();
  } on Object catch (_) {
    // The in-memory store keeps the UI usable on unsupported platforms and in
    // the native spike before the SQLite plugin is packaged.
    store = InMemoryStore();
  }

  const nativeSpikeEnabled = bool.fromEnvironment(
    'LEARNIT_NATIVE_SPIKE',
    defaultValue: false,
  );
  final nativeBridge = nativeSpikeEnabled ? NativeCoreBridge.tryLoad() : null;

  SpeechRecognizer? recognizer;
  DialogueEngine? dialogue;
  SpeechSynthesizer? synthesizer;
  NativeCoreSession? nativeSession;
  if (nativeBridge != null) {
    try {
      final modelManager = ModelManager();
      final catalog = defaultModelCatalog();
      String? whisperModelPath;
      String? dialogueModelPath;
      String? supertonicModelDir;
      String? supertonicVoiceStylePath;

      if (_hasBackend(nativeBridge, 'whisper_backend')) {
        final sttCatalog = catalog.where(
          (package) =>
              package.profile == CapabilityProfile.basic &&
              package.component == ModelComponent.speechRecognizer,
        );
        final activePackages = await modelManager.activePackages(
          CapabilityProfile.basic,
          sttCatalog,
        );
        if (activePackages.length == 1) {
          whisperModelPath =
              (await modelManager.verifiedFileFor(activePackages.single)).path;
        }
      }

      if (_hasBackend(nativeBridge, 'dialogue_backend')) {
        final dialogueCatalog = catalog.where(
          (package) =>
              package.profile == CapabilityProfile.basic &&
              package.component == ModelComponent.dialogue,
        );
        final activePackages = await modelManager.activePackages(
          CapabilityProfile.basic,
          dialogueCatalog,
        );
        if (activePackages.length == 1) {
          dialogueModelPath =
              (await modelManager.verifiedFileFor(activePackages.single)).path;
        }
      }

      if (_hasBackend(nativeBridge, 'tts_backend')) {
        final bundle = supertonic3Bundle(CapabilityProfile.basic);
        final activeBundles = await modelManager.activeBundles(
          CapabilityProfile.basic,
          <ModelBundle>[bundle],
        );
        if (activeBundles.length == 1) {
          final directory =
              await modelManager.verifiedBundleDirectory(activeBundles.single);
          supertonicModelDir = path.join(directory.path, 'onnx');
          supertonicVoiceStylePath =
              path.join(directory.path, 'voice_styles', 'M1.json');
        }
      }

      if (whisperModelPath != null ||
          dialogueModelPath != null ||
          supertonicModelDir != null) {
        nativeSession = nativeBridge.createSession(
          whisperModelPath: whisperModelPath,
          dialogueModelPath: dialogueModelPath,
          supertonicModelDir: supertonicModelDir,
          supertonicVoiceStylePath: supertonicVoiceStylePath,
          whisperThreads: 2,
        );
        if (whisperModelPath != null) {
          recognizer = NativeSpeechRecognizer(nativeSession);
        }
        if (dialogueModelPath != null) {
          dialogue = NativeLlamaDialogueEngine(nativeSession);
        }
        if (supertonicModelDir != null && supertonicVoiceStylePath != null) {
          synthesizer = NativeSupertonicSynthesizer(nativeSession);
        }
      }
    } on Object catch (_) {
      nativeSession?.close();
      recognizer = null;
      dialogue = null;
      synthesizer = null;
      // Keep the demo engines when no verified model is active or the native
      // backend cannot be initialized on this platform.
    }
  }

  final session = SessionController(
    store: store,
    recognizer: recognizer,
    dialogue: dialogue,
    synthesizer: synthesizer,
    playback: DeviceAudioPlayback(),
  );
  await session.load();
  runApp(LearnItApp(session: session));
}

bool _hasBackend(NativeCoreBridge bridge, String name) {
  try {
    final capabilities = jsonDecode(bridge.capabilities);
    return capabilities is Map && capabilities[name] == true;
  } on Object {
    return false;
  }
}
