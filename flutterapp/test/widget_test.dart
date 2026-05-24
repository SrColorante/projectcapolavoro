// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutterapp/screens/splash_screen.dart';

void main() {
  testWidgets('Shows splash title on startup', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(
          nextScreen: SizedBox(),
        ),
      ),
    );

    expect(find.text('Quice'), findsOneWidget);
    expect(find.byIcon(Icons.forum_rounded), findsOneWidget);

    // Let the delayed transition timer of the splash screen run and resolve
    await tester.pump(const Duration(seconds: 5));
  });
}
