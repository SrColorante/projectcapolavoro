import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutterapp/screens/splash_screen.dart';

void main() {
  testWidgets('Mostra il titolo sulla schermata di avvio', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(
          nextScreen: SizedBox(),
        ),
      ),
    );

    expect(find.text('Quice'), findsOneWidget);

    // Difetto segnalato dal README: il test asseriva `Icons.forum_rounded`,
    // mentre splash_screen disegna `Icons.chat_bubble_outline_rounded`.
    // Il test controllava quindi un'icona che non esiste ed era rosso per
    // un motivo che non c'entrava nulla con il comportamento dell'app.
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);

    // La verifica non deve essere fragile: l'icona non e' un contratto.
    expect(find.byType(Icon), findsWidgets);

    // Si lascia correre il timer che chiude la schermata di avvio.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Non mostra credenziali o errori di rete sullo splash',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(
          nextScreen: SizedBox(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Nessun identificativo diretto deve comparire a schermo.
    expect(find.textContaining('token'), findsNothing);
    expect(find.textContaining('password'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
  });
}
