import 'package:flutter_test/flutter_test.dart';

import 'package:learnit/app.dart';
import 'package:learnit/services/memory_store.dart';
import 'package:learnit/services/session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the local practice shell', (tester) async {
    final session = SessionController(store: InMemoryStore());
    await session.load();
    await tester.pumpWidget(LearnItApp(session: session));

    expect(find.text('Hola, Alex'), findsOneWidget);
    expect(find.text('Empezar práctica'), findsOneWidget);
    expect(find.text('Conversación'), findsOneWidget);

    session.dispose();
  });
}
