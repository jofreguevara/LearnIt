import 'package:flutter/services.dart';

class PlatformSettings {
  const PlatformSettings._();

  static const MethodChannel _channel =
      MethodChannel('learnit/system_settings');

  static Future<bool> openBackgroundSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openBackgroundSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
