import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../models/domain.dart';

abstract interface class AudioPlayback {
  Future<void> play(SynthesizedAudio audio);

  Future<void> stop();
}

class NoopAudioPlayback implements AudioPlayback {
  @override
  Future<void> play(SynthesizedAudio audio) async {}

  @override
  Future<void> stop() async {}
}

/// Plays local bytes only. It never accepts URLs and therefore cannot create a
/// hidden network dependency in the conversation pipeline.
class DeviceAudioPlayback implements AudioPlayback {
  DeviceAudioPlayback({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(SynthesizedAudio audio) async {
    try {
      await _player.stop();
      final completion = _player.onPlayerComplete.first;
      await _player.play(BytesSource(audio.bytes, mimeType: audio.mimeType));
      await completion.timeout(
        audio.duration + const Duration(seconds: 2),
        // `onPlayerComplete` is a Stream<void> in audioplayers 6.x. A timeout
        // only releases the orchestration pipeline; it does not fabricate a
        // player event or change the session state by itself.
        onTimeout: () {},
      );
    } on Object {
      // Unsupported codecs/platforms must not break the text conversation.
    }
  }

  @override
  Future<void> stop() => _player.stop();
}
