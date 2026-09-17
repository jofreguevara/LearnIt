import 'dart:convert';

import 'package:flutter/widgets.dart';

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
  if (nativeBridge != null && _hasWhisperBackend(nativeBridge)) {
    try {
      final modelManager = ModelManager();
      final sttCatalog = defaultModelCatalog().where(
        (package) =>
            package.profile == CapabilityProfile.basic &&
            package.component == ModelComponent.speechRecognizer,
      );
      final activePackages = await modelManager.activePackages(
        CapabilityProfile.basic,
        sttCatalog,
      );
      if (activePackages.length == 1) {
        final model = await modelManager.verifiedFileFor(activePackages.single);
        final nativeSession = nativeBridge.createSession(
          whisperModelPath: model.path,
          whisperThreads: 2,
        );
        recognizer = NativeSpeechRecognizer(nativeSession);
      }
    } on Object catch (_) {
      // Keep the demo recognizer when no verified model is active or the
      // native backend cannot be initialized on this platform.
    }
  }

  final session = SessionController(
    store: store,
    recognizer: recognizer,
    dialogue: nativeBridge == null ? null : NativeDialogueEngine(nativeBridge),
    playback: DeviceAudioPlayback(),
  );
  await session.load();
  runApp(LearnItApp(session: session));
}

bool _hasWhisperBackend(NativeCoreBridge bridge) {
  try {
    final capabilities = jsonDecode(bridge.capabilities);
    return capabilities is Map && capabilities['whisper_backend'] == true;
  } on Object {
    return false;
  }
}
