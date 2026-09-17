import 'package:flutter/services.dart';

class PlatformAudioSession {
  const PlatformAudioSession();

  static const MethodChannel _channel = MethodChannel('learnit/audio_session');

  Future<bool> start() => _invoke('start');

  Future<bool> pause() => _invoke('pause');

  Future<bool> resume() => _invoke('resume');

  Future<bool> finish() => _invoke('finish');

  Future<bool> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
      return true;
    } on MissingPluginException {
      // The demo remains usable on desktop, tests, and before native plugins
      // are registered. Production mobile builds must register the channel.
      return false;
    } on PlatformException {
      return false;
    }
  }
}
