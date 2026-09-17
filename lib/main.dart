import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/audio_playback.dart';
import 'services/engines.dart';
import 'services/memory_store.dart';
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
  final session = SessionController(
    store: store,
    dialogue: nativeBridge == null ? null : NativeDialogueEngine(nativeBridge),
    playback: DeviceAudioPlayback(),
  );
  await session.load();
  runApp(LearnItApp(session: session));
}
