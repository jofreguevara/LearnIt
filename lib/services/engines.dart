import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/domain.dart';
import 'native_core_bridge.dart';

abstract interface class SpeechRecognizer {
  Future<Transcript> transcribe(
    Uint8List audio, {
    LanguageCode hint = LanguageCode.auto,
  });
}

abstract interface class DialogueEngine {
  Future<DialogueReply> reply({
    required String text,
    required CompanionProfile companion,
    required String level,
    required List<MemoryRecord> memories,
    required SessionSummary? lastSummary,
  });
}

abstract interface class SpeechSynthesizer {
  Future<SynthesizedAudio> synthesize({
    required ReplySegment segment,
    required String voiceStyleId,
    required double speakingRate,
  });
}

/// Parses the compatibility/demo JSON envelope exposed by the native dialogue
/// seam. The real llama.cpp path is implemented by
/// [NativeLlamaDialogueEngine]; keeping both parsers preserves the original
/// demo ABI contract.
class NativeDialogueEngine implements DialogueEngine {
  const NativeDialogueEngine(this._client);

  final NativeDialogueClient _client;

  @override
  Future<DialogueReply> reply({
    required String text,
    required CompanionProfile companion,
    required String level,
    required List<MemoryRecord> memories,
    required SessionSummary? lastSummary,
  }) async {
    final raw = _client.generateReply(
      input: text,
      language: companion.preferredLanguage.value,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('La respuesta nativa no es un objeto JSON.');
    }
    final payload = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'La respuesta nativa contiene una clave inválida.',
        );
      }
      payload[entry.key as String] = entry.value;
    }
    final message = payload['message'];
    final languageValue = payload['language'];
    if (message is! String || message.trim().isEmpty) {
      throw const FormatException(
        'La respuesta nativa no contiene un mensaje válido.',
      );
    }
    if (languageValue is! String) {
      throw const FormatException(
        'La respuesta nativa no declara el idioma del mensaje.',
      );
    }
    final language = languageCodeFromValue(languageValue);
    if (language == LanguageCode.auto) {
      throw const FormatException(
        'La respuesta nativa declara un idioma desconocido.',
      );
    }

    return DialogueReply(
      segments: <ReplySegment>[
        ReplySegment(text: message.trim(), language: language),
      ],
      corrections: _readStringList(payload, 'corrections'),
      topics: _readStringList(payload, 'topics'),
      memoryProposals: _readMemoryProposals(payload),
    );
  }

  List<String> _readStringList(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value == null) {
      return const <String>[];
    }
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('El campo nativo "$key" no es una lista válida.');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  List<MemoryProposal> _readMemoryProposals(Map<String, dynamic> payload) {
    final value = payload['memory_proposals'];
    if (value == null) {
      return const <MemoryProposal>[];
    }
    if (value is! List) {
      throw const FormatException(
        'El campo nativo "memory_proposals" no es una lista.',
      );
    }
    return value.map((entry) {
      if (entry is! Map) {
        throw const FormatException('Una propuesta de memoria no es válida.');
      }
      final proposal = <String, dynamic>{};
      for (final item in entry.entries) {
        if (item.key is! String) {
          throw const FormatException(
            'Una propuesta de memoria contiene una clave inválida.',
          );
        }
        proposal[item.key as String] = item.value;
      }
      final key = proposal['key'];
      final proposalValue = proposal['value'];
      final reason = proposal['reason'];
      if (key is! String ||
          key.trim().isEmpty ||
          proposalValue is! String ||
          proposalValue.trim().isEmpty ||
          reason is! String ||
          reason.trim().isEmpty) {
        throw const FormatException('Una propuesta de memoria no es válida.');
      }
      return MemoryProposal(
        key: key.trim(),
        value: proposalValue.trim(),
        reason: reason.trim(),
      );
    }).toList(growable: false);
  }
}

/// Sends the complete, already-verified conversation context to the native
/// llama.cpp job and converts the model's JSON response to the Flutter
/// dialogue contract.
class NativeLlamaDialogueEngine implements DialogueEngine {
  const NativeLlamaDialogueEngine(this._runtime);

  final NativeDialogueRuntime _runtime;

  @override
  Future<DialogueReply> reply({
    required String text,
    required CompanionProfile companion,
    required String level,
    required List<MemoryRecord> memories,
    required SessionSummary? lastSummary,
  }) async {
    final raw = await _runtime.generateDialogue(
      request: jsonEncode(<String, Object?>{
        'text': text,
        'language': companion.preferredLanguage.value,
        'level': level,
        'companion': companion.toMap(),
        'memories': memories.map((memory) => memory.toMap()).toList(),
        'last_summary': lastSummary?.toMap(),
      }),
    );
    final envelope = _decodeObject(raw, 'diálogo nativo');
    if (envelope['ok'] != true) {
      _throwNativeError(envelope, 'diálogo');
    }
    if (envelope['type'] != 'dialogue') {
      throw const FormatException(
        'La respuesta nativa de diálogo no declara un diálogo.',
      );
    }
    final envelopeLanguage = _languageFromPayload(envelope['language']);
    final generated = envelope['text'];
    if (generated is! String || generated.trim().isEmpty) {
      throw const FormatException(
        'La respuesta nativa de diálogo no contiene texto válido.',
      );
    }

    return _parseGeneratedReply(
      generated.trim(),
      fallbackLanguage: envelopeLanguage == LanguageCode.auto
          ? (companion.preferredLanguage == LanguageCode.auto
              ? LanguageCode.en
              : companion.preferredLanguage)
          : envelopeLanguage,
    );
  }

  DialogueReply _parseGeneratedReply(
    String generated, {
    required LanguageCode fallbackLanguage,
  }) {
    final cleaned = _cleanModelOutput(generated);
    final decoded = _tryDecodeObject(cleaned);
    if (decoded == null) {
      return DialogueReply(
        segments: <ReplySegment>[
          ReplySegment(text: cleaned, language: fallbackLanguage),
        ],
      );
    }

    final segmentsValue = decoded['segments'];
    if (segmentsValue != null) {
      if (segmentsValue is! List || segmentsValue.isEmpty) {
        throw const FormatException(
          'El modelo nativo no produjo segmentos de diálogo válidos.',
        );
      }
      final segments = segmentsValue.map((entry) {
        if (entry is! Map) {
          throw const FormatException('Un segmento nativo no es válido.');
        }
        final segmentText = entry['text'];
        if (segmentText is! String || segmentText.trim().isEmpty) {
          throw const FormatException(
            'Un segmento nativo no contiene texto válido.',
          );
        }
        final language = _languageFromPayload(entry['language']);
        if (language == LanguageCode.auto) {
          throw const FormatException(
            'Cada segmento nativo debe declarar en o es.',
          );
        }
        return ReplySegment(
          text: segmentText.trim(),
          language: language,
        );
      }).toList(growable: false);
      return DialogueReply(
        segments: segments,
        corrections: _readStringList(decoded, 'corrections'),
        topics: _readStringList(decoded, 'topics'),
        memoryProposals: _readMemoryProposals(decoded),
      );
    }

    final message = decoded['message'] ?? decoded['text'];
    if (message is! String || message.trim().isEmpty) {
      throw const FormatException(
        'El JSON generado por el modelo no contiene segmentos ni mensaje.',
      );
    }
    return DialogueReply(
      segments: <ReplySegment>[
        ReplySegment(text: message.trim(), language: fallbackLanguage),
      ],
      corrections: _readStringList(decoded, 'corrections'),
      topics: _readStringList(decoded, 'topics'),
      memoryProposals: _readMemoryProposals(decoded),
    );
  }

  String _cleanModelOutput(String value) {
    var cleaned = value
        .replaceAll(
          RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false),
          '',
        )
        .trim();
    cleaned = cleaned
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace > 0 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1).trim();
    }
    return cleaned;
  }

  Map<String, dynamic> _decodeObject(String raw, String label) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw FormatException('La respuesta nativa de $label no es JSON.');
    }
    return _stringKeyed(decoded, label);
  }

  Map<String, dynamic>? _tryDecodeObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? _stringKeyed(decoded, 'modelo') : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> _stringKeyed(Map value, String label) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException(
            'La respuesta de $label contiene una clave inválida.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  LanguageCode _languageFromPayload(Object? value) {
    return languageCodeFromValue(value is String ? value : null);
  }

  List<String> _readStringList(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value == null) {
      return const <String>[];
    }
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('El campo nativo "$key" no es una lista válida.');
    }
    return List<String>.unmodifiable(
      value
          .cast<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    );
  }

  List<MemoryProposal> _readMemoryProposals(Map<String, dynamic> payload) {
    final value = payload['memory_proposals'];
    if (value == null) {
      return const <MemoryProposal>[];
    }
    if (value is! List) {
      throw const FormatException(
        'El campo nativo "memory_proposals" no es una lista.',
      );
    }
    return value.map((entry) {
      if (entry is! Map) {
        throw const FormatException('Una propuesta de memoria no es válida.');
      }
      final key = entry['key'];
      final proposalValue = entry['value'];
      final reason = entry['reason'];
      if (key is! String ||
          key.trim().isEmpty ||
          proposalValue is! String ||
          proposalValue.trim().isEmpty ||
          reason is! String ||
          reason.trim().isEmpty) {
        throw const FormatException('Una propuesta de memoria no es válida.');
      }
      return MemoryProposal(
        key: key.trim(),
        value: proposalValue.trim(),
        reason: reason.trim(),
      );
    }).toList(growable: false);
  }

  Never _throwNativeError(Map<String, dynamic> payload, String label) {
    final error = payload['error'];
    if (error is Map && error['code'] is String && error['message'] is String) {
      throw StateError('${error['code']}: ${error['message']}');
    }
    throw FormatException(
        'La respuesta nativa de $label contiene un error inválido.');
  }
}

/// Converts a Supertonic PCM16 WAV envelope into the waveform/audio object
/// consumed by [SessionController] and the existing playback layer.
class NativeSupertonicSynthesizer implements SpeechSynthesizer {
  const NativeSupertonicSynthesizer(this._client);

  final NativeTtsClient _client;

  @override
  Future<SynthesizedAudio> synthesize({
    required ReplySegment segment,
    required String voiceStyleId,
    required double speakingRate,
  }) async {
    final raw = await _client.synthesize(
      text: segment.text,
      language: segment.language.value,
      voiceStyleId: voiceStyleId,
      speakingRate: speakingRate,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('La respuesta nativa de TTS no es JSON.');
    }
    final payload = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'La respuesta nativa de TTS contiene una clave inválida.',
        );
      }
      payload[entry.key as String] = entry.value;
    }
    if (payload['ok'] != true) {
      final error = payload['error'];
      if (error is Map &&
          error['code'] is String &&
          error['message'] is String) {
        throw StateError('${error['code']}: ${error['message']}');
      }
      throw const FormatException(
        'La respuesta nativa de TTS contiene un error inválido.',
      );
    }
    if (payload['type'] != 'audio') {
      throw const FormatException(
        'La respuesta nativa de TTS no declara audio.',
      );
    }
    final encoded = payload['audio_base64'];
    if (encoded is! String || encoded.isEmpty) {
      throw const FormatException(
          'La respuesta nativa de TTS no contiene audio.');
    }
    final bytes = base64Decode(encoded);
    final wav = _parseWav(bytes);
    final durationValue = payload['duration_ms'];
    final durationMs =
        durationValue is num && durationValue.isFinite && durationValue > 0
            ? durationValue.round()
            : ((wav.sampleCount * 1000) / wav.sampleRate).round();
    final mimeType = payload['mime_type'] is String
        ? payload['mime_type'] as String
        : 'audio/wav';
    return SynthesizedAudio(
      bytes: bytes,
      waveform: wav.waveform,
      duration: Duration(milliseconds: durationMs),
      mimeType: mimeType,
    );
  }

  _ParsedWav _parseWav(Uint8List bytes) {
    if (bytes.length < 44 ||
        !_asciiEquals(bytes, 0, 'RIFF') ||
        !_asciiEquals(bytes, 8, 'WAVE')) {
      throw const FormatException('El audio nativo no es un WAV RIFF válido.');
    }
    final data = ByteData.sublistView(bytes);
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkLength = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + chunkLength;
      if (chunkEnd > bytes.length) {
        throw const FormatException(
            'El WAV nativo contiene un chunk truncado.');
      }
      if (_asciiEquals(bytes, offset, 'fmt ') && chunkLength >= 16) {
        final format = data.getUint16(chunkStart, Endian.little);
        channels = data.getUint16(chunkStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
        if (format != 1) {
          throw const FormatException('El audio nativo no es PCM lineal.');
        }
      } else if (_asciiEquals(bytes, offset, 'data')) {
        dataOffset = chunkStart;
        dataLength = chunkLength;
        break;
      }
      offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
    }
    if (sampleRate == null ||
        channels != 1 ||
        bitsPerSample != 16 ||
        dataOffset == null ||
        dataLength == null ||
        sampleRate <= 0 ||
        dataLength <= 0 ||
        dataLength.isOdd) {
      throw const FormatException(
        'El audio nativo debe ser WAV PCM16 mono con una frecuencia válida.',
      );
    }
    final sampleCount = dataLength ~/ 2;
    final waveformLength = math.min(256, sampleCount);
    final waveform = <double>[];
    for (var bin = 0; bin < waveformLength; bin++) {
      final start = (bin * sampleCount) ~/ waveformLength;
      final end = ((bin + 1) * sampleCount) ~/ waveformLength;
      var total = 0.0;
      final count = math.max(1, end - start);
      for (var sample = start; sample < end; sample++) {
        total += data.getInt16(dataOffset + sample * 2, Endian.little).abs() /
            32768.0;
      }
      waveform.add((total / count).clamp(0.0, 1.0).toDouble());
    }
    return _ParsedWav(
      sampleRate: sampleRate,
      sampleCount: sampleCount,
      waveform: List<double>.unmodifiable(waveform),
    );
  }

  bool _asciiEquals(Uint8List bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) {
      return false;
    }
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }
}

class _ParsedWav {
  const _ParsedWav({
    required this.sampleRate,
    required this.sampleCount,
    required this.waveform,
  });

  final int sampleRate;
  final int sampleCount;
  final List<double> waveform;
}

/// Converts the native Whisper JSON envelope into the stable Flutter
/// [Transcript] contract. Native jobs are asynchronous, so this parser is
/// also the boundary where backend errors become recoverable Dart errors.
class NativeSpeechRecognizer implements SpeechRecognizer {
  const NativeSpeechRecognizer(this._client);

  final NativeWhisperClient _client;

  @override
  Future<Transcript> transcribe(
    Uint8List audio, {
    LanguageCode hint = LanguageCode.auto,
  }) async {
    final raw = await _client.transcribe(
      audio: audio,
      language: hint.value,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('La respuesta nativa de STT no es JSON.');
    }
    final payload = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'La respuesta nativa de STT contiene una clave inválida.',
        );
      }
      payload[entry.key as String] = entry.value;
    }

    if (payload['ok'] != true) {
      final error = payload['error'];
      if (error is Map &&
          error['code'] is String &&
          error['message'] is String) {
        throw StateError('${error['code']}: ${error['message']}');
      }
      throw const FormatException(
        'La respuesta nativa de STT contiene un error inválido.',
      );
    }
    if (payload['type'] != 'transcript') {
      throw const FormatException(
        'La respuesta nativa de STT no declara una transcripción.',
      );
    }
    final text = payload['text'];
    final languageValue = payload['language'];
    final confidenceValue = payload['confidence'];
    if (text is! String || text.trim().isEmpty) {
      throw const FormatException(
        'La respuesta nativa de STT no contiene texto válido.',
      );
    }
    if (languageValue is! String) {
      throw const FormatException(
        'La respuesta nativa de STT no declara el idioma.',
      );
    }
    final language = languageCodeFromValue(languageValue);
    if (language == LanguageCode.auto) {
      throw const FormatException(
        'La respuesta nativa de STT declara un idioma desconocido.',
      );
    }
    if (confidenceValue is! num || !confidenceValue.isFinite) {
      throw const FormatException(
        'La respuesta nativa de STT no declara una confianza válida.',
      );
    }

    return Transcript(
      text: text.trim(),
      language: language,
      confidence: confidenceValue.toDouble().clamp(0.0, 1.0).toDouble(),
    );
  }
}

/// Fallback used by the UI before model packages are installed.
/// It keeps the full orchestration testable without a network or model files.
class DemoSpeechRecognizer implements SpeechRecognizer {
  const DemoSpeechRecognizer();

  @override
  Future<Transcript> transcribe(
    Uint8List audio, {
    LanguageCode hint = LanguageCode.auto,
  }) async {
    if (audio.isEmpty) {
      throw StateError('No se recibió audio.');
    }
    return Transcript(
      text: 'Hello, I want to practice English today.',
      language: hint == LanguageCode.auto ? LanguageCode.en : hint,
      confidence: 0.92,
    );
  }
}

/// Deterministic conversation engine for the first vertical slice.
/// The native Qwen/llama.cpp adapter replaces this class after the spike.
class DemoDialogueEngine implements DialogueEngine {
  const DemoDialogueEngine();

  @override
  Future<DialogueReply> reply({
    required String text,
    required CompanionProfile companion,
    required String level,
    required List<MemoryRecord> memories,
    required SessionSummary? lastSummary,
  }) async {
    final normalized = text.trim().toLowerCase();
    final isSpanish = _looksSpanish(normalized);
    final corrections = <String>[];
    final memoryProposals = <MemoryProposal>[];
    if (companion.correctionMode != CorrectionMode.off &&
        normalized.contains('i want practice')) {
      corrections.add(
        'Una forma más natural es: “I want to practice English.”',
      );
    }

    final topics = <String>[
      if (normalized.contains('coffee') || normalized.contains('café'))
        'café'
      else
        'rutinas diarias',
    ];
    final rememberedName = memories
        .where((memory) => memory.key == 'name')
        .map((memory) => memory.value)
        .firstOrNull;
    final nameMatch = RegExp(
      r"\b(?:my name is|me llamo)\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'-]{1,29})",
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (nameMatch != null && rememberedName != nameMatch.group(1)?.trim()) {
      memoryProposals.add(
        MemoryProposal(
          key: 'name',
          value: nameMatch.group(1)!.trim(),
          reason: 'Lo compartiste durante esta conversación.',
        ),
      );
    }
    final greeting = rememberedName == null ? '' : ' $rememberedName';

    final answer = isSpanish
        ? '¡Hola$greeting! Podemos practicar poco a poco. '
            'Cuéntame en inglés qué hiciste ayer.'
        : 'Great choice$greeting! Tell me one thing you did yesterday, '
            'and I will ask a follow-up question.';

    final segments = <ReplySegment>[
      ReplySegment(
        text: answer,
        language: isSpanish ? LanguageCode.es : LanguageCode.en,
      ),
    ];
    if (corrections.isNotEmpty) {
      segments.add(
        const ReplySegment(
          text: 'Try it again when you are ready.',
          language: LanguageCode.en,
        ),
      );
    }

    return DialogueReply(
      segments: segments,
      corrections: corrections,
      topics: topics,
      memoryProposals: memoryProposals,
    );
  }

  bool _looksSpanish(String text) {
    const markers = <String>[
      ' hola ',
      ' quiero ',
      ' ayer ',
      ' qué ',
      ' gracias ',
      ' practicar ',
      ' café',
    ];
    final padded = ' $text ';
    return markers.any(padded.contains);
  }
}

/// Generates a small PCM-like buffer and waveform for the UI demonstration.
/// Real Supertonic/ONNX output will implement the same interface.
class DemoSpeechSynthesizer implements SpeechSynthesizer {
  const DemoSpeechSynthesizer();

  @override
  Future<SynthesizedAudio> synthesize({
    required ReplySegment segment,
    required String voiceStyleId,
    required double speakingRate,
  }) async {
    final safeSpeakingRate = speakingRate <= 0 ? 1.0 : speakingRate;
    final sampleCount = math.max(80, segment.text.length * 5).toInt();
    final waveform = List<double>.generate(sampleCount, (index) {
      final envelope = 0.25 + 0.75 * math.sin(math.pi * index / sampleCount);
      return (math.sin(index / 2.7) * envelope).abs();
    });
    final pcm = List<int>.generate(
      sampleCount,
      (index) =>
          (math.sin(index / 2.7) * envelopeFor(index, sampleCount) * 32767)
              .round(),
    );
    final bytes = _wavBytes(pcm, sampleRate: 16000);
    final milliseconds = (segment.text.length * 42 / safeSpeakingRate).round();
    return SynthesizedAudio(
      bytes: bytes,
      waveform: waveform,
      duration: Duration(milliseconds: milliseconds),
    );
  }

  double envelopeFor(int index, int count) =>
      0.25 + 0.75 * math.sin(math.pi * index / count);

  Uint8List _wavBytes(List<int> samples, {required int sampleRate}) {
    final dataLength = samples.length * 2;
    final result = ByteData(44 + dataLength);
    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        result.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    result.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    result.setUint32(16, 16, Endian.little);
    result.setUint16(20, 1, Endian.little);
    result.setUint16(22, 1, Endian.little);
    result.setUint32(24, sampleRate, Endian.little);
    result.setUint32(28, sampleRate * 2, Endian.little);
    result.setUint16(32, 2, Endian.little);
    result.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    result.setUint32(40, dataLength, Endian.little);
    for (var index = 0; index < samples.length; index++) {
      result.setInt16(44 + index * 2, samples[index], Endian.little);
    }
    return result.buffer.asUint8List();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
