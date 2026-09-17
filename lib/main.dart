import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/audio_playback.dart';
import 'services/memory_store.dart';
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

  final session = SessionController(
    store: store,
    playback: DeviceAudioPlayback(),
  );
  await session.load();
  runApp(LearnItApp(session: session));
}
