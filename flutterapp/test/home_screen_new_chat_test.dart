import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutterapp/api/chat_api.dart';
import 'package:flutterapp/models/chat_thread.dart';
import 'package:flutterapp/models/user_profile.dart';
import 'package:flutterapp/screens/home_screen.dart';

import 'support/fake_secure_store.dart';

/// Sostituto di ChatApi che risponde in locale.
///
/// Riceve un archivio di sessione finto perche' il costruttore di base
/// altrimenti creerebbe un client HTTP reale e toccherebbe il Keychain del
/// sistema, che in un test non esiste.
class FakeChatApi extends ChatApi {
  FakeChatApi() : super(sessionStore: fakeSessionStore());

  final List<ChatThread> _chats = <ChatThread>[];

  @override
  Future<List<ChatThread>> fetchChats({required String userId}) async {
    return _chats;
  }

  @override
  Future<MessagesFetchResult> fetchMessages({
    required String userId,
    required String chatId,
  }) async {
    return MessagesFetchResult(
      messages: _chats.firstWhere((chat) => chat.id == chatId).messages,
      typingUsers: const [],
    );
  }

  @override
  Future<String> createChat({
    required String userId,
    required String targetUserId,
  }) async {
    final chat = ChatThread(
      id: '2345678901',
      title: 'Alice',
      participantId: targetUserId,
      messages: <ChatMessage>[],
    );
    _chats.insert(0, chat);
    return chat.id;
  }
}

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
          chatApi: FakeChatApi(),
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

    // La chat appena creata deve comparire nella lista con il nome inserito.
    expect(find.text('Alice'), findsWidgets);

    // Il pannello si chiude: la creazione non lascia l'utente dentro il form.
    expect(find.text('Crea chat'), findsNothing);
  });

  testWidgets('l\'etichetta del campo annuncia 10 cifre, non 8-15', (
    WidgetTester tester,
  ) async {
    // Difetto originale: l'etichetta prometteva "8-15 cifre" mentre il server ne
    // richiede esattamente 10. L'utente poteva registrare un numero che poi
    // non avrebbe mai potuto usare per accedere.
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          profile: UserProfile(
            id: '1234567890',
            name: 'Tester',
            email: 'tester@example.com',
          ),
          chatApi: FakeChatApi(),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Nuova chat'));
    await tester.pumpAndSettle();

    expect(find.text('Numero di telefono (10 cifre)'), findsOneWidget);
    expect(find.textContaining('8-15'), findsNothing);
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
          chatApi: FakeChatApi(),
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
