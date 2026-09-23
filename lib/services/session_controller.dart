import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/domain.dart';
import 'audio_playback.dart';
import 'engines.dart';
import 'memory_store.dart';
import 'platform_audio_session.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required MemoryStore store,
    SpeechRecognizer? recognizer,
    DialogueEngine? dialogue,
    SpeechSynthesizer? synthesizer,
    PlatformAudioSession? platformAudio,
    AudioPlayback? playback,
  })  : _store = store,
        _recognizer = recognizer ?? const DemoSpeechRecognizer(),
        _dialogue = dialogue ?? const DemoDialogueEngine(),
        _synthesizer = synthesizer ?? const DemoSpeechSynthesizer(),
        _platformAudio = platformAudio ?? PlatformAudioSession(),
        _playback = playback ?? NoopAudioPlayback();

  final MemoryStore _store;
  final SpeechRecognizer _recognizer;
  final DialogueEngine _dialogue;
  final SpeechSynthesizer _synthesizer;
  final PlatformAudioSession _platformAudio;
  final AudioPlayback _playback;

  SessionSnapshot _snapshot = const SessionSnapshot();
  CompanionProfile _companion = const CompanionProfile();
  ProgressSnapshot _progress = const ProgressSnapshot();
  SessionSummary? _lastSummary;
  DateTime? _startedAt;
  String? _sessionId;
  String? _currentTopic;
  bool _busy = false;
  bool _audioEnabled = false;
  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<MemoryProposal> _pendingProposals = <MemoryProposal>[];

  SessionSnapshot get snapshot => _snapshot;
  CompanionProfile get companion => _companion;
  ProgressSnapshot get progress => _progress;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<MemoryProposal> get pendingProposals =>
      List.unmodifiable(_pendingProposals);
  bool get isBusy => _busy;

  Future<void> load() async {
    _companion = await _store.loadCompanion();
    _progress = await _store.loadProgress();
    _lastSummary = await _store.latestSummary();
    notifyListeners();
  }

  Future<void> saveCompanion(CompanionProfile companion) async {
    _companion = companion;
    await _store.saveCompanion(companion);
    notifyListeners();
  }

  Future<List<MemoryRecord>> memories() => _store.listMemories();

  Future<bool> start({bool audio = true, String? topic}) async {
    if (_snapshot.state == SessionState.listening || _busy) {
      return _snapshot.state == SessionState.listening;
    }
    if (audio) {
      final platformStarted = await _platformAudio.start();
      if (!platformStarted && _platformAudio.lastError != null) {
        _setError(_platformAudio.lastError!);
        return false;
      }
    }
    _startedAt = DateTime.now();
    _sessionId = 'session-${_startedAt!.microsecondsSinceEpoch}';
    _currentTopic = topic;
    _audioEnabled = audio;
    _messages.clear();
    _pendingProposals.clear();
    _setSnapshot(
      const SessionSnapshot(state: SessionState.listening, turnCount: 0),
    );
    return true;
  }

  void pause() {
    if (_snapshot.state == SessionState.listening) {
      if (_audioEnabled) {
        unawaited(_platformAudio.pause());
      }
      _setSnapshot(_snapshot.copyWith(state: SessionState.paused));
    }
  }

  void resume() {
    if (_snapshot.state == SessionState.paused) {
      if (_audioEnabled) {
        unawaited(_platformAudio.resume());
      }
      _setSnapshot(_snapshot.copyWith(state: SessionState.listening));
    }
  }

  Future<void> finish() async {
    if (_startedAt == null || _snapshot.state == SessionState.idle || _busy) {
      return;
    }
    await _persistSummary();
    await _playback.stop();
    if (_audioEnabled) {
      await _platformAudio.finish();
    }
    _setSnapshot(_snapshot.copyWith(state: SessionState.finished));
    _startedAt = null;
    _sessionId = null;
    _currentTopic = null;
  }

  /// Text input provides a deterministic vertical slice before microphone
  /// capture and native STT are installed. Audio input uses the same pipeline.
  Future<void> submitText(String text,
      {LanguageCode hint = LanguageCode.auto}) async {
    if (text.trim().isEmpty || _busy) {
      return;
    }
    if (_snapshot.state == SessionState.idle ||
        _snapshot.state == SessionState.finished) {
      final started = await start(audio: false);
      if (!started) {
        return;
      }
    }
    if (_snapshot.state == SessionState.paused) {
      return;
    }
    await _processTranscript(
      Transcript(
        text: text.trim(),
        language: hint == LanguageCode.auto ? _guessLanguage(text) : hint,
        confidence: 1.0,
      ),
    );
  }

  Future<void> submitAudio(
    Uint8List audio, {
    LanguageCode hint = LanguageCode.auto,
  }) async {
    if (_busy) {
      return;
    }
    if (_snapshot.state == SessionState.idle ||
        _snapshot.state == SessionState.finished) {
      final started = await start(audio: true);
      if (!started) {
        return;
      }
    }
    if (_snapshot.state == SessionState.paused) {
      return;
    }
    _setSnapshot(_snapshot.copyWith(state: SessionState.transcribing));
    try {
      final transcript = await _recognizer.transcribe(audio, hint: hint);
      await _processTranscript(transcript);
    } on Object catch (error) {
      _setError('No se pudo transcribir el audio: $error');
    }
  }

  Future<void> confirmMemory(MemoryProposal proposal) async {
    final sessionId = _sessionId ?? 'manual';
    await _store.saveMemory(
      MemoryRecord(
        id: null,
        key: proposal.key,
        value: proposal.value,
        sourceSessionId: sessionId,
        confirmedAt: DateTime.now(),
      ),
    );
    _pendingProposals.remove(proposal);
    notifyListeners();
  }

  void dismissMemoryProposal(MemoryProposal proposal) {
    if (_pendingProposals.remove(proposal)) {
      notifyListeners();
    }
  }

  Future<void> deleteMemory(int id) async {
    await _store.deleteMemory(id);
    notifyListeners();
  }

  Future<void> updateMemory(MemoryRecord memory) async {
    await _store.saveMemory(memory);
    notifyListeners();
  }

  Future<void> _processTranscript(Transcript transcript) async {
    _busy = true;
    _setSnapshot(
      _snapshot.copyWith(
        state: SessionState.thinking,
        transcript: transcript,
        clearError: true,
      ),
    );
    try {
      final memories = await _store.listMemories();
      final reply = await _dialogue.reply(
        text: transcript.text,
        companion: _companion,
        level: _progress.estimatedLevel,
        memories: memories,
        lastSummary: _lastSummary,
      );
      _validateReply(reply);
      _messages.add(ChatMessage(text: transcript.text, fromUser: true));
      _setSnapshot(
          _snapshot.copyWith(reply: reply, state: SessionState.synthesizing));
      _pendingProposals
        ..clear()
        ..addAll(reply.memoryProposals);

      final waveforms = <double>[];
      for (final segment in reply.segments) {
        final audio = await _synthesizer.synthesize(
          segment: segment,
          voiceStyleId: _companion.voiceStyleId,
          speakingRate: _companion.speakingRate,
        );
        waveforms.addAll(audio.waveform);
        _setSnapshot(
          _snapshot.copyWith(
            state: SessionState.playing,
            waveform: List<double>.unmodifiable(waveforms),
          ),
        );
        await _playback.play(audio);
      }
      _messages.add(ChatMessage(text: reply.fullText, fromUser: false));
      _setSnapshot(
        _snapshot.copyWith(
          state: SessionState.listening,
          waveform: List<double>.unmodifiable(waveforms),
          turnCount: _snapshot.turnCount + 1,
        ),
      );
      await _saveTurn(reply, transcript);
    } on Object catch (error) {
      _setError('La sesión encontró un problema: $error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _saveTurn(DialogueReply reply, Transcript transcript) async {
    final words = transcript.text
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .length;
    _progress = _progress.copyWith(
      turnsCompleted: _progress.turnsCompleted + 1,
      wordsPracticed: _progress.wordsPracticed + words,
      practiceSeconds: _progress.practiceSeconds + 30,
    );
    await _store.saveProgress(_progress);

    final now = DateTime.now();
    _lastSummary = SessionSummary(
      id: _sessionId ?? 'session-${now.microsecondsSinceEpoch}',
      startedAt: _startedAt ?? now,
      endedAt: now,
      topics: <String>{
        ...reply.topics,
        if (_currentTopic != null) _currentTopic!
      }.toList(),
      summary:
          'Turno completado en ${transcript.language.label} con $words palabras; '
          'temas: ${reply.topics.join(', ')}.',
      lastTurnState: 'completed',
    );
    await _store.saveSummary(_lastSummary!);
  }

  void _validateReply(DialogueReply reply) {
    if (reply.segments.isEmpty ||
        reply.segments.any((segment) => segment.text.trim().isEmpty)) {
      throw const FormatException('La respuesta local no contiene segmentos.');
    }
    if (reply.segments.any(
      (segment) => segment.language == LanguageCode.auto,
    )) {
      throw const FormatException(
        'Cada segmento de respuesta debe declarar su idioma.',
      );
    }
  }

  Future<void> _persistSummary() async {
    if (_lastSummary != null && _lastSummary!.id == _sessionId) {
      await _store.saveSummary(_lastSummary!);
    }
  }

  LanguageCode _guessLanguage(String text) {
    final lower = text.toLowerCase();
    const markers = <String>[
      ' hola ',
      ' quiero ',
      ' ayer ',
      ' gracias ',
      ' qué '
    ];
    return markers.any((' $lower ').contains)
        ? LanguageCode.es
        : LanguageCode.en;
  }

  void _setSnapshot(SessionSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  void _setError(String message) {
    _snapshot = _snapshot.copyWith(
      state: SessionState.error,
      errorMessage: message,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_playback.stop());
    unawaited(_platformAudio.finish());
    super.dispose();
  }
}
