import 'package:flutter_test/flutter_test.dart';

import 'package:learnit/models/domain.dart';

void main() {
  test('companion profile round trips through a map', () {
    const original = CompanionProfile(
      name: 'Sam',
      personality: 'patient',
      voiceStyleId: 'M1',
      correctionMode: CorrectionMode.detailed,
      speakingRate: 0.9,
      preferredLanguage: LanguageCode.es,
    );

    final copy = CompanionProfile.fromMap(original.toMap());

    expect(copy.name, original.name);
    expect(copy.personality, original.personality);
    expect(copy.correctionMode, CorrectionMode.detailed);
    expect(copy.speakingRate, 0.9);
    expect(copy.preferredLanguage, LanguageCode.es);
  });

  test('session state labels remain user-facing and stable', () {
    expect(SessionState.listening.label, 'Escuchando');
    expect(SessionState.playing.label, 'Reproduciendo');
  });

  test('progress copyWith changes only requested fields', () {
    const progress = ProgressSnapshot(
      practiceSeconds: 30,
      turnsCompleted: 1,
      wordsPracticed: 6,
      estimatedLevel: 'A1',
    );

    final updated = progress.copyWith(turnsCompleted: 2);

    expect(updated.turnsCompleted, 2);
    expect(updated.practiceSeconds, 30);
    expect(updated.wordsPracticed, 6);
    expect(updated.estimatedLevel, 'A1');
  });
}
