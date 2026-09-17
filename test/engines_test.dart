import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:learnit/models/domain.dart';
import 'package:learnit/services/engines.dart';
import 'package:learnit/services/native_core_bridge.dart';

class _FakeNativeDialogueClient implements NativeDialogueClient {
  _FakeNativeDialogueClient(this.payload);

  final String payload;

  @override
  String get version => 'test-native';

  @override
  String generateReply({required String input, required String language}) =>
      payload;
}

class _FakeNativeWhisperClient implements NativeWhisperClient {
  _FakeNativeWhisperClient(this.payload);

  final String payload;
  bool cancelled = false;

  @override
  Future<String> transcribe({
    required Uint8List audio,
    required String language,
  }) async =>
      payload;

  @override
  void cancel() => cancelled = true;
}

class _FakeNativeDialogueRuntime implements NativeDialogueRuntime {
  _FakeNativeDialogueRuntime(this.payload);

  final String payload;
  String? request;

  @override
  Future<String> generateDialogue({required String request}) async {
    this.request = request;
    return payload;
  }

  @override
  void cancel() {}
}

class _FakeNativeTtsClient implements NativeTtsClient {
  _FakeNativeTtsClient(this.payload);

  final String payload;
  String? text;

  @override
  Future<String> synthesize({
    required String text,
    required String language,
    required String voiceStyleId,
    required double speakingRate,
  }) async {
    this.text = text;
    return payload;
  }

  @override
  void cancel() {}
}

Uint8List _wavFixture() {
  final data = ByteData(48);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 40, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, 4, Endian.little);
  data.setInt16(44, 12000, Endian.little);
  data.setInt16(46, -12000, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  test('demo dialogue emits a correction for a common learner error', () async {
    const engine = DemoDialogueEngine();
    final reply = await engine.reply(
      text: 'I want practice English',
      companion: const CompanionProfile(),
      level: 'A1',
      memories: const <MemoryRecord>[],
      lastSummary: null,
    );

    expect(reply.corrections, isNotEmpty);
    expect(reply.segments.first.language, LanguageCode.en);
  });

  test('demo synthesizer returns a playable WAV and waveform', () async {
    const synthesizer = DemoSpeechSynthesizer();
    final audio = await synthesizer.synthesize(
      segment: const ReplySegment(text: 'Hello', language: LanguageCode.en),
      voiceStyleId: 'M1',
      speakingRate: 1.0,
    );

    expect(audio.bytes, isA<Uint8List>());
    expect(audio.bytes.sublist(0, 4), <int>[82, 73, 70, 70]);
    expect(audio.waveform, isNotEmpty);
    expect(audio.mimeType, 'audio/wav');
  });

  test('demo dialogue asks before persisting a personal memory', () async {
    const engine = DemoDialogueEngine();
    final reply = await engine.reply(
      text: 'My name is Lucía',
      companion: const CompanionProfile(),
      level: 'A1',
      memories: const <MemoryRecord>[],
      lastSummary: null,
    );

    expect(reply.memoryProposals.single.key, 'name');
    expect(reply.memoryProposals.single.value, 'Lucía');
  });

  test('native dialogue parses the structured response envelope', () async {
    final engine = NativeDialogueEngine(
      _FakeNativeDialogueClient(
        jsonEncode(<String, Object?>{
          'mode': 'native',
          'language': 'en',
          'message': 'Tell me about your day.',
          'corrections': <String>['Use the past tense.'],
          'topics': <String>['daily routines'],
          'memory_proposals': <Map<String, String>>[
            <String, String>{
              'key': 'name',
              'value': 'Lucía',
              'reason': 'Shared during the conversation.',
            },
          ],
        }),
      ),
    );

    final reply = await engine.reply(
      text: 'Hello',
      companion: const CompanionProfile(),
      level: 'A1',
      memories: const <MemoryRecord>[],
      lastSummary: null,
    );

    expect(reply.fullText, 'Tell me about your day.');
    expect(reply.corrections, <String>['Use the past tense.']);
    expect(reply.topics, <String>['daily routines']);
    expect(reply.memoryProposals.single.value, 'Lucía');
  });

  test('native dialogue rejects an incomplete response envelope', () async {
    final engine = NativeDialogueEngine(
      _FakeNativeDialogueClient('{"language":"en","message":""}'),
    );

    await expectLater(
      engine.reply(
        text: 'Hello',
        companion: const CompanionProfile(),
        level: 'A1',
        memories: const <MemoryRecord>[],
        lastSummary: null,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('llama dialogue sends context and parses model JSON', () async {
    final runtime = _FakeNativeDialogueRuntime(
      jsonEncode(<String, Object?>{
        'ok': true,
        'type': 'dialogue',
        'language': 'en',
        'text': jsonEncode(<String, Object?>{
          'segments': <Map<String, Object?>>[
            <String, Object?>{
              'text': 'Tell me about your weekend.',
              'language': 'en',
            },
          ],
          'corrections': <String>['Use the past tense.'],
          'topics': <String>['weekend'],
          'memory_proposals': <Map<String, String>>[
            <String, String>{
              'key': 'name',
              'value': 'Lucía',
              'reason': 'Shared in the turn.',
            },
          ],
        }),
      }),
    );
    const companion = CompanionProfile();
    final engine = NativeLlamaDialogueEngine(runtime);

    final reply = await engine.reply(
      text: 'My name is Lucía',
      companion: companion,
      level: 'A1',
      memories: const <MemoryRecord>[],
      lastSummary: null,
    );

    final request = jsonDecode(runtime.request!) as Map;
    expect(request['text'], 'My name is Lucía');
    expect(request['companion'], companion.toMap());
    expect(reply.fullText, 'Tell me about your weekend.');
    expect(reply.corrections, <String>['Use the past tense.']);
    expect(reply.memoryProposals.single.value, 'Lucía');
  });

  test('Supertonic synthesizer validates PCM16 WAV output', () async {
    final client = _FakeNativeTtsClient(
      jsonEncode(<String, Object?>{
        'ok': true,
        'type': 'audio',
        'mime_type': 'audio/wav',
        'sample_rate': 16000,
        'duration_ms': 12,
        'audio_base64': base64Encode(_wavFixture()),
      }),
    );
    final synthesizer = NativeSupertonicSynthesizer(client);

    final audio = await synthesizer.synthesize(
      segment: const ReplySegment(text: 'Hello', language: LanguageCode.en),
      voiceStyleId: 'M1',
      speakingRate: 1.0,
    );

    expect(client.text, 'Hello');
    expect(audio.bytes, hasLength(48));
    expect(audio.waveform, hasLength(2));
    expect(audio.waveform.first, closeTo(12000 / 32768, 0.001));
    expect(audio.duration, const Duration(milliseconds: 12));
  });

  test('native speech recognizer parses a Whisper transcript envelope',
      () async {
    final recognizer = NativeSpeechRecognizer(
      _FakeNativeWhisperClient(
        jsonEncode(<String, Object?>{
          'ok': true,
          'type': 'transcript',
          'text': 'Hello, I practice English.',
          'language': 'en',
          'confidence': 0.87,
        }),
      ),
    );

    final transcript = await recognizer.transcribe(
      Uint8List.fromList(<int>[0, 0]),
      hint: LanguageCode.en,
    );

    expect(transcript.text, 'Hello, I practice English.');
    expect(transcript.language, LanguageCode.en);
    expect(transcript.confidence, closeTo(0.87, 0.001));
  });

  test('native speech recognizer exposes backend errors', () async {
    final recognizer = NativeSpeechRecognizer(
      _FakeNativeWhisperClient(
        '{"ok":false,"error":{"code":"cancelled","message":"stop"}}',
      ),
    );

    await expectLater(
      recognizer.transcribe(Uint8List.fromList(<int>[0, 0])),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('cancelled: stop'),
        ),
      ),
    );
  });
}
