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
}
