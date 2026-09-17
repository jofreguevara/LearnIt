import 'dart:math' as math;
import 'dart:typed_data';

import '../models/domain.dart';

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
