import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutterapp/models/user_profile.dart';
import 'package:flutterapp/screens/home_screen.dart';

void main() {
  testWidgets('opens new chat pane and creates a chat with valid 10-digit ID', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          profile: UserProfile(
            id: '1234567890',
            name: 'Tester',
            email: 'tester@example.com',
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Nuova chat'));
    await tester.pumpAndSettle();

    expect(find.text('Nuova chat'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), '1234567899');
    await tester.tap(find.text('Crea chat'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsWidgets);
    expect(find.text('Benvenuto! Questa è la tua nuova chat.'), findsOneWidget);
  });

  testWidgets('shows validation error for invalid new chat user ID', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          profile: UserProfile(
            id: '1234567890',
            name: 'Tester',
            email: 'tester@example.com',
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Nuova chat'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Bob');
    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tester.tap(find.text('Crea chat'));
    await tester.pumpAndSettle();

    expect(
      find.text('L\'ID utente deve essere numerico e di 10 cifre'),
      findsOneWidget,
    );
  });
}
