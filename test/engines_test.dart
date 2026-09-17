import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:learnit/models/domain.dart';
import 'package:learnit/services/engines.dart';

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
}
