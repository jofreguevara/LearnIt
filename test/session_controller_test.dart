import 'package:flutter_test/flutter_test.dart';

import 'package:learnit/models/domain.dart';
import 'package:learnit/services/memory_store.dart';
import 'package:learnit/services/session_controller.dart';

void main() {
  test('processes a local text turn and returns to listening', () async {
    final store = InMemoryStore();
    final session = SessionController(store: store);
    await session.load();

    await session.submitText('Hello, I want to practice English today.');

    expect(session.snapshot.state, SessionState.listening);
    expect(session.snapshot.turnCount, 1);
    expect(session.messages.length, 2);
    expect(session.progress.turnsCompleted, 1);
    expect(session.progress.wordsPracticed, greaterThan(0));
    final summary = await store.latestSummary();
    expect(summary?.summary, isNot(contains('Hello, I want')));
  });

  test('pause prevents a new turn until the user resumes', () async {
    final session = SessionController(store: InMemoryStore());
    await session.load();
    await session.start(audio: false);
    session.pause();

    await session.submitText('Hello there.');

    expect(session.snapshot.state, SessionState.paused);
    expect(session.snapshot.turnCount, 0);
    expect(session.messages, isEmpty);
  });

  test('confirmed memories are persisted and deletable', () async {
    final store = InMemoryStore();
    final session = SessionController(store: store);
    await session.load();

    const proposal = MemoryProposal(
      key: 'name',
      value: 'Lucía',
      reason: 'The user shared their name.',
    );
    await session.confirmMemory(proposal);
    final saved = await session.memories();
    expect(saved.single.value, 'Lucía');

    await session.deleteMemory(saved.single.id!);
    expect(await session.memories(), isEmpty);
  });
}
