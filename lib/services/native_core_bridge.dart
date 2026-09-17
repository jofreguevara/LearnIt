import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Small Dart-side contract for a native dialogue runtime.
///
/// The demo ABI implements this contract today. A whisper.cpp/llama.cpp/
/// ONNX-backed bridge can replace it without changing the Flutter session
/// orchestration or its tests.
abstract interface class NativeDialogueClient {
  String get version;

  String generateReply({required String input, required String language});
}

/// Dart-side contract for the asynchronous native Whisper session.
///
/// Audio ownership stays on the Dart side until [transcribe] has copied it
/// into the native job. The returned JSON is parsed by [NativeSpeechRecognizer]
/// so malformed native output remains a recoverable session error.
abstract interface class NativeWhisperClient {
  Future<String> transcribe({
    required Uint8List audio,
    required String language,
  });

  void cancel();
}

class NativeCoreBridge implements NativeDialogueClient {
  NativeCoreBridge._(DynamicLibrary library)
      : _version = library.lookupFunction<_VersionNative, _VersionDart>(
          'learnit_core_version',
        ),
        _capabilities =
            library.lookupFunction<_CapabilitiesNative, _CapabilitiesDart>(
          'learnit_core_capabilities',
        ),
        _demoReply = library.lookupFunction<_DemoReplyNative, _DemoReplyDart>(
          'learnit_demo_reply',
        ),
        _freeString =
            library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'learnit_free_string',
        ),
        _sessionCreate =
            library.lookupFunction<_SessionCreateNative, _SessionCreateDart>(
          'learnit_core_session_create',
        ),
        _sessionDestroy =
            library.lookupFunction<_SessionDestroyNative, _SessionDestroyDart>(
          'learnit_core_session_destroy',
        ),
        _sessionLoad =
            library.lookupFunction<_SessionLoadNative, _SessionLoadDart>(
          'learnit_core_session_load',
        ),
        _sessionIsReady =
            library.lookupFunction<_SessionIsReadyNative, _SessionIsReadyDart>(
          'learnit_core_session_is_ready',
        ),
        _sessionLastError = library
            .lookupFunction<_SessionLastErrorNative, _SessionLastErrorDart>(
          'learnit_core_session_last_error',
        ),
        _transcribeStart = library
            .lookupFunction<_TranscribeStartNative, _TranscribeStartDart>(
          'learnit_core_transcribe_start',
        ),
        _jobPoll = library.lookupFunction<_JobPollNative, _JobPollDart>(
          'learnit_core_job_poll',
        ),
        _jobCancel = library.lookupFunction<_JobCancelNative, _JobCancelDart>(
          'learnit_core_job_cancel',
        ),
        _sessionCancel =
            library.lookupFunction<_SessionCancelNative, _SessionCancelDart>(
          'learnit_core_session_cancel',
        );

  final _VersionDart _version;
  final _CapabilitiesDart _capabilities;
  final _DemoReplyDart _demoReply;
  final _FreeStringDart _freeString;
  final _SessionCreateDart _sessionCreate;
  final _SessionDestroyDart _sessionDestroy;
  final _SessionLoadDart _sessionLoad;
  final _SessionIsReadyDart _sessionIsReady;
  final _SessionLastErrorDart _sessionLastError;
  final _TranscribeStartDart _transcribeStart;
  final _JobPollDart _jobPoll;
  final _JobCancelDart _jobCancel;
  final _SessionCancelDart _sessionCancel;

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

  @override
  String get version => _version().toDartString();

  /// JSON capabilities advertised by the native runtime.
  ///
  /// This is intentionally separate from [NativeDialogueClient] so the
  /// Flutter session contract remains stable while the native spike grows.
  String get capabilities => _capabilities().toDartString();

  @override
  String generateReply({required String input, required String language}) =>
      demoReply(input: input, language: language);

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

  /// Creates a native session. Model loading is lazy and runs on the native
  /// worker started by [NativeCoreSession.transcribe].
  NativeCoreSession createSession({
    String? whisperModelPath,
    int whisperThreads = 2,
  }) {
    final pathPointer = (whisperModelPath ?? '').toNativeUtf8();
    try {
      final handle = _sessionCreate(
        pathPointer,
        whisperThreads.clamp(1, 8).toInt(),
      );
      if (handle == nullptr) {
        throw StateError('No se pudo crear la sesión nativa.');
      }
      return NativeCoreSession._(
        handle: handle,
        destroy: _sessionDestroy,
        load: _sessionLoad,
        isReady: _sessionIsReady,
        lastError: _sessionLastError,
        start: _transcribeStart,
        poll: _jobPoll,
        cancelJob: _jobCancel,
        cancelSession: _sessionCancel,
        freeString: _freeString,
      );
    } finally {
      calloc.free(pathPointer);
    }
  }
}

/// Owns one native Whisper context and exposes its copy-owning job queue to
/// Dart without blocking the Flutter event loop while inference runs.
class NativeCoreSession implements NativeWhisperClient {
  NativeCoreSession._({
    required Pointer<Void> handle,
    required _SessionDestroyDart destroy,
    required _SessionLoadDart load,
    required _SessionIsReadyDart isReady,
    required _SessionLastErrorDart lastError,
    required _TranscribeStartDart start,
    required _JobPollDart poll,
    required _JobCancelDart cancelJob,
    required _SessionCancelDart cancelSession,
    required _FreeStringDart freeString,
  })  : _handle = handle,
        _destroy = destroy,
        _load = load,
        _isReady = isReady,
        _lastError = lastError,
        _start = start,
        _poll = poll,
        _cancelJob = cancelJob,
        _cancelSession = cancelSession,
        _freeString = freeString;

  final Pointer<Void> _handle;
  final _SessionDestroyDart _destroy;
  final _SessionLoadDart _load;
  final _SessionIsReadyDart _isReady;
  final _SessionLastErrorDart _lastError;
  final _TranscribeStartDart _start;
  final _JobPollDart _poll;
  final _JobCancelDart _cancelJob;
  final _SessionCancelDart _cancelSession;
  final _FreeStringDart _freeString;
  bool _closed = false;
  int? _activeJobId;

  bool get isReady {
    _ensureOpen();
    return _isReady(_handle) != 0;
  }

  String get lastError {
    _ensureOpen();
    final value = _lastError(_handle);
    return value == nullptr ? '' : value.toDartString();
  }

  /// Explicit warm-up for a caller that is already off the Flutter UI path.
  bool load() {
    _ensureOpen();
    return _load(_handle) != 0;
  }

  @override
  Future<String> transcribe({
    required Uint8List audio,
    required String language,
  }) async {
    _ensureOpen();
    if (audio.isEmpty) {
      throw StateError('No se recibió audio.');
    }
    if (audio.length.isOdd) {
      throw FormatException('El audio PCM16 tiene un tamaño impar.');
    }
    if (_activeJobId != null) {
      throw StateError('La sesión nativa ya está transcribiendo un turno.');
    }

    final sampleCount = audio.length ~/ 2;
    final samples = calloc<Int16>(sampleCount);
    final bytes = samples.cast<Uint8>().asTypedList(audio.length);
    bytes.setAll(0, audio);
    final languagePointer = language.toNativeUtf8();
    try {
      final jobId = _start(
        _handle,
        samples,
        sampleCount,
        16000,
        languagePointer,
      );
      if (jobId == 0) {
        throw StateError(lastError);
      }
      _activeJobId = jobId;
      try {
        while (true) {
          final result = _poll(_handle, jobId);
          if (result != nullptr) {
            try {
              return result.toDartString();
            } finally {
              _freeString(result);
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      } finally {
        if (_activeJobId == jobId) {
          _activeJobId = null;
        }
      }
    } finally {
      calloc.free(languagePointer);
      calloc.free(samples);
    }
  }

  @override
  void cancel() {
    if (!_closed) {
      final jobId = _activeJobId;
      if (jobId != null) {
        _cancelJob(_handle, jobId);
      }
      _cancelSession(_handle);
    }
  }

  /// Cancels pending jobs, joins native workers, and releases the model.
  /// Do not call it while another isolate is polling this session.
  void close() {
    if (_closed) {
      return;
    }
    _cancelSession(_handle);
    _destroy(_handle);
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('La sesión nativa ya fue cerrada.');
    }
  }
}

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();
typedef _CapabilitiesNative = Pointer<Utf8> Function();
typedef _CapabilitiesDart = Pointer<Utf8> Function();
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
typedef _SessionCreateNative = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  Int32 whisperThreads,
);
typedef _SessionCreateDart = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  int whisperThreads,
);
typedef _SessionDestroyNative = Void Function(Pointer<Void> session);
typedef _SessionDestroyDart = void Function(Pointer<Void> session);
typedef _SessionLoadNative = Int32 Function(Pointer<Void> session);
typedef _SessionLoadDart = int Function(Pointer<Void> session);
typedef _SessionIsReadyNative = Int32 Function(Pointer<Void> session);
typedef _SessionIsReadyDart = int Function(Pointer<Void> session);
typedef _SessionLastErrorNative = Pointer<Utf8> Function(
  Pointer<Void> session,
);
typedef _SessionLastErrorDart = Pointer<Utf8> Function(Pointer<Void> session);
typedef _TranscribeStartNative = Uint64 Function(
  Pointer<Void> session,
  Pointer<Int16> samples,
  Int32 sampleCount,
  Int32 sampleRate,
  Pointer<Utf8> languageHint,
);
typedef _TranscribeStartDart = int Function(
  Pointer<Void> session,
  Pointer<Int16> samples,
  int sampleCount,
  int sampleRate,
  Pointer<Utf8> languageHint,
);
typedef _JobPollNative = Pointer<Utf8> Function(
  Pointer<Void> session,
  Uint64 jobId,
);
typedef _JobPollDart = Pointer<Utf8> Function(
  Pointer<Void> session,
  int jobId,
);
typedef _JobCancelNative = Int32 Function(
  Pointer<Void> session,
  Uint64 jobId,
);
typedef _JobCancelDart = int Function(Pointer<Void> session, int jobId);
typedef _SessionCancelNative = Void Function(Pointer<Void> session);
typedef _SessionCancelDart = void Function(Pointer<Void> session);
