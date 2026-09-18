import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'model_download_page.dart';
import 'models/domain.dart';
import 'services/microphone_capture.dart';
import 'services/model_manager.dart';
import 'services/session_controller.dart';

class LearnItApp extends StatelessWidget {
  const LearnItApp({
    required this.session,
    this.modelManager,
    super.key,
  });

  final SessionController session;
  final ModelManager? modelManager;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LearnIt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4057A7),
        scaffoldBackgroundColor: const Color(0xFFF8F9FE),
      ),
      home: AppShell(
        session: session,
        modelManager: modelManager ?? ModelManager(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.session,
    required this.modelManager,
    super.key,
  });

  final SessionController session;
  final ModelManager modelManager;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        session: widget.session,
        onStart: () => setState(() => _selectedIndex = 1),
      ),
      ConversationPage(session: widget.session),
      TopicsPage(
        session: widget.session,
        onStart: () => setState(() => _selectedIndex = 1),
      ),
      ProgressPage(session: widget.session),
      SettingsPage(
        session: widget.session,
        modelManager: widget.modelManager,
      ),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: 'Conversación'),
          NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Temas'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Progreso'),
          NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: 'Ajustes'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({required this.session, required this.onStart, super.key});

  final SessionController session;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, child) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: <Widget>[
          Text('Hola, ${session.companion.name}',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Una práctica corta hoy suma a tu progreso.',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          _OfflineCard(session: session),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    CircleAvatar(
                        radius: 27,
                        child: Text(session.companion.name.isEmpty
                            ? '?'
                            : session.companion.name
                                .substring(0, 1)
                                .toUpperCase())),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Text(session.companion.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    const Icon(Icons.auto_awesome, color: Color(0xFF4057A7)),
                  ]),
                  const SizedBox(height: 16),
                  Text('“${session.companion.personality}”',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      await session.start();
                      onStart();
                    },
                    icon: const Icon(Icons.mic_none),
                    label: const Text('Empezar práctica'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ProgressCard(progress: session.progress),
          const SizedBox(height: 16),
          Text('Sugerencia para hoy',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Card(
              child: ListTile(
                  leading: Icon(Icons.local_cafe_outlined),
                  title: Text('Coffee talk'),
                  subtitle: Text('Habla de tus rutinas y bebidas favoritas.'))),
        ],
      ),
    );
  }
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({required this.session, super.key});

  final SessionController session;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final TextEditingController _textController = TextEditingController();
  MicrophoneCapture? _capture;
  bool _recording = false;

  @override
  void dispose() {
    _textController.dispose();
    final capture = _capture;
    if (capture != null) {
      unawaited(capture.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AnimatedBuilder(
      animation: session,
      builder: (context, child) {
        final snapshot = session.snapshot;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                      child: Text('Conversación',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700))),
                  _StatusPill(state: snapshot.state),
                ],
              ),
            ),
            if (snapshot.state == SessionState.error &&
                snapshot.errorMessage != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(snapshot.errorMessage!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            Expanded(
              child: session.messages.isEmpty
                  ? _EmptyConversation(
                      onStart: () => unawaited(session.start()))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                      itemCount: session.messages.length,
                      itemBuilder: (context, index) {
                        final message = session.messages[index];
                        return _MessageBubble(message: message);
                      },
                    ),
            ),
            if (snapshot.reply?.corrections.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: const Text('Sugerencia'),
                    subtitle: Text(snapshot.reply!.corrections.join('\n')),
                  ),
                ),
              ),
            if (snapshot.waveform.isNotEmpty)
              _Waveform(data: snapshot.waveform),
            if (session.pendingProposals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  children: session.pendingProposals
                      .map(
                        (proposal) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.bookmark_add_outlined),
                            title: Text('¿Recordar ${proposal.key}?'),
                            subtitle: Text(proposal.value),
                            trailing: Wrap(
                              spacing: 2,
                              children: <Widget>[
                                IconButton(
                                  tooltip: 'Confirmar',
                                  onPressed: () => unawaited(
                                      session.confirmMemory(proposal)),
                                  icon: const Icon(Icons.check),
                                ),
                                IconButton(
                                  tooltip: 'Descartar',
                                  onPressed: () =>
                                      session.dismissMemoryProposal(proposal),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                          hintText: 'Escribe una frase para practicar…',
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _recording
                        ? 'Terminar grabación'
                        : 'Grabar intervención',
                    onPressed: session.isBusy ? null : _toggleRecording,
                    icon: Icon(_recording ? Icons.stop : Icons.mic),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Enviar',
                    onPressed: session.isBusy ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                      onPressed: session.isBusy
                          ? null
                          : () => unawaited(session.submitText(
                              'Hello, I want to practice English today.')),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Ejemplo EN')),
                  OutlinedButton.icon(
                      onPressed: session.isBusy
                          ? null
                          : () => unawaited(session.submitText(
                              'Hola, quiero practicar inglés hoy.')),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Ejemplo ES')),
                  if (snapshot.state == SessionState.listening)
                    OutlinedButton.icon(
                        onPressed: () => unawaited(_pause()),
                        icon: const Icon(Icons.pause),
                        label: const Text('Pausar')),
                  if (snapshot.state == SessionState.paused)
                    OutlinedButton.icon(
                        onPressed: session.resume,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Continuar')),
                  if (snapshot.state != SessionState.idle &&
                      snapshot.state != SessionState.finished)
                    OutlinedButton.icon(
                        onPressed: () => unawaited(_finish()),
                        icon: const Icon(Icons.stop),
                        label: const Text('Finalizar')),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _send() {
    final text = _textController.text;
    _textController.clear();
    unawaited(widget.session.submitText(text));
  }

  Future<void> _finish() async {
    if (_recording) {
      await _capture?.cancel();
      if (mounted) setState(() => _recording = false);
    }
    await widget.session.finish();
  }

  Future<void> _pause() async {
    if (_recording) {
      await _capture?.cancel();
      if (mounted) setState(() => _recording = false);
    }
    widget.session.pause();
  }

  Future<void> _toggleRecording() async {
    final capture = _capture ??= MicrophoneCapture();
    if (_recording) {
      Uint8List audio;
      try {
        audio = await capture.stop();
      } on Object {
        if (!mounted) {
          return;
        }
        setState(() => _recording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo leer la grabación.')),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() => _recording = false);
      if (audio.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se capturó audio.')));
        return;
      }
      await widget.session.submitAudio(audio);
      return;
    }
    bool started;
    try {
      started = await capture.start();
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo iniciar el micrófono.')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de micrófono no concedido.')));
      return;
    }
    setState(() => _recording = true);
  }
}

class TopicsPage extends StatelessWidget {
  const TopicsPage({required this.session, required this.onStart, super.key});

  final SessionController session;
  final VoidCallback onStart;

  static const topics = <Map<String, String>>[
    {
      'title': 'Coffee talk',
      'subtitle': 'Rutinas y bebidas',
      'asset': 'assets/topics/coffee.svg'
    },
    {
      'title': 'Travel plans',
      'subtitle': 'Viajes y lugares',
      'asset': 'assets/topics/travel.svg'
    },
    {
      'title': 'Work day',
      'subtitle': 'Trabajo y hábitos',
      'asset': 'assets/topics/work.svg'
    },
    {
      'title': 'Weekend ideas',
      'subtitle': 'Planes y aficiones',
      'asset': 'assets/topics/ideas.svg'
    },
    {
      'title': 'My neighborhood',
      'subtitle': 'Lugares cercanos',
      'asset': 'assets/topics/nature.svg'
    },
    {
      'title': 'Food memories',
      'subtitle': 'Comida y recuerdos',
      'asset': 'assets/topics/coffee.svg'
    },
    {
      'title': 'Music I like',
      'subtitle': 'Canciones y artistas',
      'asset': 'assets/topics/music.svg'
    },
    {
      'title': 'Books and stories',
      'subtitle': 'Lecturas favoritas',
      'asset': 'assets/topics/ideas.svg'
    },
    {
      'title': 'Healthy habits',
      'subtitle': 'Salud y rutinas',
      'asset': 'assets/topics/nature.svg'
    },
    {
      'title': 'Learning goals',
      'subtitle': 'Metas de estudio',
      'asset': 'assets/topics/ideas.svg'
    },
    {
      'title': 'A perfect day',
      'subtitle': 'Imaginación y planes',
      'asset': 'assets/topics/ideas.svg'
    },
    {
      'title': 'Technology',
      'subtitle': 'Herramientas digitales',
      'asset': 'assets/topics/work.svg'
    },
    {
      'title': 'The weather',
      'subtitle': 'Clima y estaciones',
      'asset': 'assets/topics/nature.svg'
    },
    {
      'title': 'Family and friends',
      'subtitle': 'Personas importantes',
      'asset': 'assets/topics/coffee.svg'
    },
    {
      'title': 'Small celebrations',
      'subtitle': 'Fiestas y costumbres',
      'asset': 'assets/topics/ideas.svg'
    },
    {
      'title': 'City or countryside',
      'subtitle': 'Formas de vivir',
      'asset': 'assets/topics/nature.svg'
    },
    {
      'title': 'A difficult choice',
      'subtitle': 'Opiniones y decisiones',
      'asset': 'assets/topics/ideas.svg'
    },
    {
      'title': 'A memorable trip',
      'subtitle': 'Historias de viaje',
      'asset': 'assets/topics/travel.svg'
    },
    {
      'title': 'Future ideas',
      'subtitle': 'Sueños y proyectos',
      'asset': 'assets/topics/ideas.svg'
    },
    {
      'title': 'Everyday opinions',
      'subtitle': 'Conversación abierta',
      'asset': 'assets/topics/work.svg'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          sliver: SliverToBoxAdapter(
              child: Text('Temas',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700))),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: topics.length,
            itemBuilder: (context, index) {
              final topic = topics[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: SvgPicture.asset(topic['asset']!,
                      width: 76, height: 60, fit: BoxFit.cover),
                  title: Text(topic['title']!,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(topic['subtitle']!),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    await session.start(topic: topic['title']);
                    onStart();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ProgressPage extends StatelessWidget {
  const ProgressPage({required this.session, super.key});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, child) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: <Widget>[
          Text('Tu progreso',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
              'Una estimación orientativa basada en la práctica guardada localmente.'),
          const SizedBox(height: 18),
          _ProgressCard(progress: session.progress, expanded: true),
          const SizedBox(height: 16),
          const Card(
              child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Nivel estimado'),
                  subtitle:
                      Text('LearnIt no sustituye una certificación oficial.'))),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.session,
    required this.modelManager,
    super.key,
  });

  final SessionController session;
  final ModelManager modelManager;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _nameController;
  late TextEditingController _personalityController;
  late Future<List<MemoryRecord>> _memoriesFuture;
  double? _pendingSpeakingRate;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.session.companion.name);
    _personalityController =
        TextEditingController(text: widget.session.companion.personality);
    _memoriesFuture = widget.session.memories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personalityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AnimatedBuilder(
      animation: session,
      builder: (context, child) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: <Widget>[
          Text('Ajustes y memoria',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
                labelText: 'Nombre del compañero',
                border: OutlineInputBorder()),
            onSubmitted: (value) => unawaited(session.saveCompanion(session
                .companion
                .copyWith(name: value.trim().isEmpty ? 'Alex' : value.trim()))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _personalityController,
            decoration: const InputDecoration(
                labelText: 'Personalidad', border: OutlineInputBorder()),
            onSubmitted: (value) => unawaited(session.saveCompanion(
                session.companion.copyWith(
                    personality: value.trim().isEmpty
                        ? 'amable y curioso'
                        : value.trim()))),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CorrectionMode>(
            initialValue: session.companion.correctionMode,
            decoration: const InputDecoration(
                labelText: 'Correcciones', border: OutlineInputBorder()),
            items: CorrectionMode.values
                .map((mode) =>
                    DropdownMenuItem(value: mode, child: Text(mode.label)))
                .toList(),
            onChanged: (mode) {
              if (mode != null) {
                unawaited(
                  session.saveCompanion(
                    session.companion.copyWith(correctionMode: mode),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: session.companion.voiceStyleId,
            decoration: const InputDecoration(
              labelText: 'Identidad de voz',
              border: OutlineInputBorder(),
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'M1', child: Text('Alex · voz base')),
              DropdownMenuItem(value: 'M2', child: Text('Alex · voz cálida')),
            ],
            onChanged: (voiceStyleId) {
              if (voiceStyleId != null) {
                unawaited(
                  session.saveCompanion(
                    session.companion.copyWith(voiceStyleId: voiceStyleId),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 4),
          Text(
            'El paquete TTS seleccionado debe incluir el estilo elegido.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Velocidad de voz: '
            '${(_pendingSpeakingRate ?? session.companion.speakingRate).toStringAsFixed(1)}×',
          ),
          Slider(
            value: _pendingSpeakingRate ?? session.companion.speakingRate,
            min: 0.7,
            max: 1.3,
            divisions: 6,
            label:
                '${(_pendingSpeakingRate ?? session.companion.speakingRate).toStringAsFixed(1)}×',
            onChanged: (value) => setState(() {
              // Keep this local while dragging; persistence happens on release.
              _pendingSpeakingRate = value;
            }),
            onChangeEnd: (value) {
              _pendingSpeakingRate = null;
              unawaited(
                session.saveCompanion(
                  session.companion.copyWith(speakingRate: value),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          ModelDownloadSection(manager: widget.modelManager),
          const SizedBox(height: 24),
          Text('Recuerdos confirmados',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FutureBuilder<List<MemoryRecord>>(
            future: _memoriesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final memories = snapshot.data ?? const <MemoryRecord>[];
              if (memories.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Aún no hay recuerdos'),
                    subtitle: Text(
                      'Las propuestas deberán confirmarse antes de guardarse.',
                    ),
                  ),
                );
              }
              return Column(
                children: memories
                    .map(
                      (memory) => Card(
                        child: ListTile(
                          title: Text(memory.key),
                          subtitle: Text(memory.value),
                          trailing: Wrap(
                            spacing: 2,
                            children: <Widget>[
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: memory.id == null
                                    ? null
                                    : () => _editMemory(memory),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Borrar',
                                onPressed: memory.id == null
                                    ? null
                                    : () => unawaited(_deleteMemory(memory)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 16),
          const Card(
              child: ListTile(
                  leading: Icon(Icons.cloud_off),
                  title: Text('Funcionamiento local'),
                  subtitle: Text(
                      'La práctica no necesita una cuenta ni una conexión después de preparar los modelos.'))),
        ],
      ),
    );
  }

  Future<void> _deleteMemory(MemoryRecord memory) async {
    final id = memory.id;
    if (id == null) {
      return;
    }
    await widget.session.deleteMemory(id);
    if (mounted) {
      setState(() => _memoriesFuture = widget.session.memories());
    }
  }

  Future<void> _editMemory(MemoryRecord memory) async {
    final valueController = TextEditingController(text: memory.value);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${memory.key}'),
        content: TextField(
          controller: valueController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: const InputDecoration(labelText: 'Valor'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(valueController.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    valueController.dispose();
    if (!mounted || value == null || value.isEmpty) {
      return;
    }
    await widget.session.updateMemory(
      MemoryRecord(
        id: memory.id,
        key: memory.key,
        value: value,
        sourceSessionId: memory.sourceSessionId,
        confirmedAt: memory.confirmedAt,
      ),
    );
    if (mounted) {
      setState(() => _memoriesFuture = widget.session.memories());
    }
  }
}

class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFE8F2EC),
        child: ListTile(
          leading: const Icon(Icons.cloud_off, color: Color(0xFF23633D)),
          title: Text(
              session.snapshot.isOfflineReady
                  ? 'Modo local listo'
                  : 'Demo local lista',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(session.snapshot.isOfflineReady
              ? 'Los datos permanecen en el dispositivo.'
              : 'Falta preparar un paquete de modelos verificados para activar la inferencia real.'),
        ),
      );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress, this.expanded = false});

  final ProgressSnapshot progress;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final minutes = progress.practiceSeconds ~/ 60;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Nivel estimado ${progress.estimatedLevel}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _Metric(value: '$minutes min', label: 'práctica'),
                  _Metric(value: '${progress.turnsCompleted}', label: 'turnos'),
                  _Metric(
                      value: '${progress.wordsPracticed}', label: 'palabras'),
                ]),
            if (expanded) ...<Widget>[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                  value: (progress.turnsCompleted / 20)
                      .clamp(0.0, 1.0)
                      .toDouble()),
              const SizedBox(height: 8),
              const Text('Objetivo inicial: completar 20 turnos de práctica.'),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final active =
        state == SessionState.listening || state == SessionState.playing;
    return Chip(
        avatar: Icon(active ? Icons.graphic_eq : Icons.circle,
            size: 16, color: active ? Colors.green : Colors.grey),
        label: Text(state.label));
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.forum_outlined,
                    size: 56, color: Color(0xFF4057A7)),
                const SizedBox(height: 16),
                Text('Tu conversación empieza aquí',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                    'Escribe una frase o usa uno de los ejemplos. Esta demo mantiene todo local.'),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: onStart, child: const Text('Iniciar sesión')),
              ]),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final color = message.fromUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Colors.white;
    return Align(
      alignment:
          message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(18)),
        child: Text(message.text),
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.data});

  final List<double> data;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 52,
      child: CustomPaint(
          painter:
              _WaveformPainter(data, Theme.of(context).colorScheme.primary)));
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.data, this.color);

  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
      return;
    }
    final paint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 2;
    final step = size.width / data.length;
    for (var index = 0; index < data.length; index++) {
      final x = index * step;
      final amplitude = data[index] * size.height / 2;
      canvas.drawLine(Offset(x, size.height / 2 - amplitude),
          Offset(x, size.height / 2 + amplitude), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}
