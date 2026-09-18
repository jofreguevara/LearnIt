import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:learnit/app.dart';
import 'package:learnit/services/memory_store.dart';
import 'package:learnit/services/model_manager.dart';
import 'package:learnit/services/session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the local practice shell', (tester) async {
    final session = SessionController(store: InMemoryStore());
    final modelDirectory = Directory(
      '${Directory.systemTemp.path}/learnit-widget-models-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      if (await modelDirectory.exists()) {
        await modelDirectory.delete(recursive: true);
      }
    });
    await session.load();
    await tester.pumpWidget(
      LearnItApp(
        session: session,
        modelManager: ModelManager(rootDirectory: modelDirectory),
      ),
    );

    expect(find.text('Hola, Alex'), findsOneWidget);
    expect(find.text('Empezar práctica'), findsOneWidget);
    expect(find.text('Conversación'), findsOneWidget);

    await tester.tap(find.text('Ajustes'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Modelos locales'), findsOneWidget);
    expect(find.text('Reconocimiento · Whisper base'), findsOneWidget);
    expect(find.text('Voz · Supertonic 3 (M1)'), findsOneWidget);

    session.dispose();
  });
}
