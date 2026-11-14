import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopez_code_ai/models/message.dart';
import 'package:lopez_code_ai/widgets/message_bubble.dart';

void main() {
  testWidgets('MessageBubble separa timeline en tarjeta compacta y oculta código largo',
      (tester) async {
    final msg = Message(
      role: 'assistant',
      content: '''
• Thought briefly
• Explored lib/commons/pages/authentication/authentication\\_widget.dart
• Edited lib/commons/pages/authentication/authentication\\_widget.dart +27 -41
• Analyze clean

Ya localicé el problema en `authentication_widget.dart` y ajusté el texto para que no se desborde en pantallas pequeñas.

```dart
Padding(
  padding: EdgeInsetsDirectional.fromSTEB(0, 16, 0, 0),
  child: Row(
    children: [],
  ),
)
```
''',
      timestamp: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(message: msg),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Timeline colapsada en tarjeta con badge del archivo tocado (sin \_).
    expect(find.text('4 acciones realizadas'), findsOneWidget);
    expect(find.text('authentication_widget.dart'), findsOneWidget);
    expect(find.text('+27 -41'), findsOneWidget);

    // El código largo aparece colapsado en tarjeta compacta ("Ver código").
    expect(find.text('dart · 6 líneas'), findsOneWidget);
    expect(find.text('Ver código'), findsOneWidget);
    expect(find.textContaining('fromSTEB'), findsNothing);

    // Al pulsar "Ver código" sí se despliega el bloque.
    await tester.tap(find.text('Ver código'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fromSTEB'), findsOneWidget);
  });
}
