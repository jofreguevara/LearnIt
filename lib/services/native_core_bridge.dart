import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class NativeCoreBridge {
  NativeCoreBridge._(DynamicLibrary library)
      : _version = library.lookupFunction<_VersionNative, _VersionDart>(
          'learnit_core_version',
        ),
        _demoReply = library.lookupFunction<_DemoReplyNative, _DemoReplyDart>(
          'learnit_demo_reply',
        ),
        _freeString =
            library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'learnit_free_string',
        );

  final _VersionDart _version;
  final _DemoReplyDart _demoReply;
  final _FreeStringDart _freeString;

  static NativeCoreBridge? tryLoad() {
    try {
      final library = Platform.isAndroid
          ? DynamicLibrary.open('liblearnit_core.so')
          : DynamicLibrary.process();
      return NativeCoreBridge._(library);
    } on Object {
      return null;
    }
  }

  String get version => _version().toDartString();

  String demoReply({required String input, required String language}) {
    final inputPointer = input.toNativeUtf8();
    final languagePointer = language.toNativeUtf8();
    try {
      final result = _demoReply(inputPointer, languagePointer);
      if (result == nullptr) {
        throw StateError('El núcleo nativo no pudo producir una respuesta.');
      }
      try {
        return result.toDartString();
      } finally {
        _freeString(result);
      }
    } finally {
      calloc.free(inputPointer);
      calloc.free(languagePointer);
    }
  }
}

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
typedef _DemoReplyNative = Pointer<Utf8> Function(
  Pointer<Utf8> input,
  Pointer<Utf8> language,
);
typedef _DemoReplyDart = Pointer<Utf8> Function(
  Pointer<Utf8> input,
  Pointer<Utf8> language,
);
typedef _FreeStringNative = Void Function(Pointer<Utf8> value);
typedef _FreeStringDart = void Function(Pointer<Utf8> value);
