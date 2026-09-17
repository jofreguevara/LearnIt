import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/domain.dart';

abstract interface class MemoryStore {
  Future<CompanionProfile> loadCompanion();

  Future<void> saveCompanion(CompanionProfile companion);

  Future<List<MemoryRecord>> listMemories();

  Future<int> saveMemory(MemoryRecord memory);

  Future<void> deleteMemory(int id);

  Future<SessionSummary?> latestSummary();

  Future<void> saveSummary(SessionSummary summary);

  Future<ProgressSnapshot> loadProgress();

  Future<void> saveProgress(ProgressSnapshot progress);
}

class InMemoryStore implements MemoryStore {
  CompanionProfile _companion = const CompanionProfile();
  final List<MemoryRecord> _memories = <MemoryRecord>[];
  final List<SessionSummary> _summaries = <SessionSummary>[];
  ProgressSnapshot _progress = const ProgressSnapshot();
  int _nextMemoryId = 1;

  @override
  Future<CompanionProfile> loadCompanion() async => _companion;

  @override
  Future<void> saveCompanion(CompanionProfile companion) async {
    _companion = companion;
  }

  @override
  Future<List<MemoryRecord>> listMemories() async =>
      List.unmodifiable(_memories);

  @override
  Future<int> saveMemory(MemoryRecord memory) async {
    final record = MemoryRecord(
      id: memory.id ?? _nextMemoryId++,
      key: memory.key,
      value: memory.value,
      sourceSessionId: memory.sourceSessionId,
      confirmedAt: memory.confirmedAt,
    );
    _memories.removeWhere((item) => item.key == record.key);
    _memories.add(record);
    return record.id!;
  }

  @override
  Future<void> deleteMemory(int id) async {
    _memories.removeWhere((memory) => memory.id == id);
  }

  @override
  Future<SessionSummary?> latestSummary() async =>
      _summaries.isEmpty ? null : _summaries.last;

  @override
  Future<void> saveSummary(SessionSummary summary) async {
    _summaries.removeWhere((item) => item.id == summary.id);
    _summaries.add(summary);
  }

  @override
  Future<ProgressSnapshot> loadProgress() async => _progress;

  @override
  Future<void> saveProgress(ProgressSnapshot progress) async {
    _progress = progress;
  }
}

class SqfliteMemoryStore implements MemoryStore {
  SqfliteMemoryStore(this._database);

  final Database _database;

  static Future<SqfliteMemoryStore> open() async {
    // Application Support keeps the database out of user-visible documents;
    // the native host should also mark this directory excluded from backup.
    final directory = await getApplicationSupportDirectory();
    final databasePath = path.join(directory.path, 'learnit.sqlite');
    final database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE companion (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            name TEXT NOT NULL,
            personality TEXT NOT NULL,
            voice_style_id TEXT NOT NULL,
            correction_mode TEXT NOT NULL,
            speaking_rate REAL NOT NULL,
            preferred_language TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT NOT NULL UNIQUE,
            value TEXT NOT NULL,
            source_session_id TEXT NOT NULL,
            confirmed_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE session_summaries (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT NOT NULL,
            topics TEXT NOT NULL,
            summary TEXT NOT NULL,
            last_turn_state TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE progress (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            practice_seconds INTEGER NOT NULL,
            turns_completed INTEGER NOT NULL,
            words_practiced INTEGER NOT NULL,
            estimated_level TEXT NOT NULL
          )
        ''');
      },
    );
    return SqfliteMemoryStore(database);
  }

  @override
  Future<CompanionProfile> loadCompanion() async {
    final rows = await _database.query('companion', where: 'id = 1');
    if (rows.isEmpty) {
      const companion = CompanionProfile();
      await saveCompanion(companion);
      return companion;
    }
    return CompanionProfile.fromMap(rows.first.cast<String, Object?>());
  }

  @override
  Future<void> saveCompanion(CompanionProfile companion) async {
    await _database.insert(
      'companion',
      <String, Object?>{'id': 1, ...companion.toMap()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<MemoryRecord>> listMemories() async {
    final rows =
        await _database.query('memories', orderBy: 'confirmed_at DESC');
    return rows
        .map((row) => MemoryRecord.fromMap(row.cast<String, Object?>()))
        .toList(growable: false);
  }

  @override
  Future<int> saveMemory(MemoryRecord memory) async {
    return _database.insert(
      'memories',
      memory.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteMemory(int id) async {
    await _database
        .delete('memories', where: 'id = ?', whereArgs: <Object>[id]);
  }

  @override
  Future<SessionSummary?> latestSummary() async {
    final rows = await _database.query(
      'session_summaries',
      orderBy: 'ended_at DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : SessionSummary.fromMap(rows.first.cast<String, Object?>());
  }

  @override
  Future<void> saveSummary(SessionSummary summary) async {
    await _database.insert(
      'session_summaries',
      summary.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<ProgressSnapshot> loadProgress() async {
    final rows = await _database.query('progress', where: 'id = 1');
    if (rows.isEmpty) {
      const progress = ProgressSnapshot();
      await saveProgress(progress);
      return progress;
    }
    final row = rows.first;
    return ProgressSnapshot(
      practiceSeconds: row['practice_seconds'] as int? ?? 0,
      turnsCompleted: row['turns_completed'] as int? ?? 0,
      wordsPracticed: row['words_practiced'] as int? ?? 0,
      estimatedLevel: row['estimated_level'] as String? ?? 'A1',
    );
  }

  @override
  Future<void> saveProgress(ProgressSnapshot progress) async {
    await _database.insert(
      'progress',
      <String, Object?>{
        'id': 1,
        'practice_seconds': progress.practiceSeconds,
        'turns_completed': progress.turnsCompleted,
        'words_practiced': progress.wordsPracticed,
        'estimated_level': progress.estimatedLevel,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
