import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// Requests microphone access before a foreground audio service is started.
/// Desktop and tests keep the demo path available without a platform prompt.
Future<bool> requestMicrophonePermission() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return true;
  }
  final recorder = AudioRecorder();
  try {
    return await recorder.hasPermission();
  } on MissingPluginException {
    // Keep the local demo usable on desktop and in widget tests where the
    // mobile recorder plugin is intentionally not registered.
    return true;
  } on PlatformException {
    return false;
  } finally {
    await recorder.dispose();
  }
}

/// Captures a single turn as PCM16 in memory. The completed buffer is handed
/// directly to SpeechRecognizer and is never written to a file.
class MicrophoneCapture {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  bool get isRecording => _subscription != null;

  Future<bool> start() async {
    if (isRecording) {
      return true;
    }
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      return false;
    }
    try {
      _buffer.clear();
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _recorder = recorder;
      _subscription = stream.listen(_buffer.add);
      return true;
    } on Object catch (_) {
      await recorder.cancel();
      await recorder.dispose();
      rethrow;
    }
  }

  Future<Uint8List> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;
    return _buffer.takeBytes();
  }

  Future<void> cancel() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await _recorder?.cancel();
    await _recorder?.dispose();
    _recorder = null;
    _buffer.clear();
  }
}
