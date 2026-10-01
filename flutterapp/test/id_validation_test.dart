import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutterapp/api/api_client.dart';
import 'package:flutterapp/api/auth_api.dart';
import 'package:flutterapp/api/session_store.dart';
import 'package:flutterapp/models/chat_thread.dart';
import 'package:flutterapp/models/user_profile.dart';

/// Archivio sicuro in memoria: nel test non si tocca il Keychain reale.
class _MemorySecureStore implements SecureStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async => _values.clear();

  /// Espone i valori per verificare che il token non finisca altrove.
  Map<String, String> get values => Map<String, String>.unmodifiable(_values);
}

SessionStore _testStore() => SessionStore(storage: _MemorySecureStore());

void main() {
  group('Identificativi a 10 cifre', () {
    test('valida gli identificativi utente', () {
      expect(UserProfile.isValidTenDigitId('1234567890'), isTrue);
      expect(UserProfile.isValidTenDigitId('12345'), isFalse);
      expect(UserProfile.isValidTenDigitId('ABCDEFGHIJ'), isFalse);
    });

    test('rifiuta un profilo con identificativo non valido', () {
      expect(
        () => UserProfile(id: '123', name: 'Mario', email: 'mario@test.com'),
        throwsArgumentError,
      );
    });

    test('gli identificativi generati hanno sempre 10 cifre', () {
      expect(UserProfile.isValidTenDigitId(UserProfile.generateTenDigitId()), isTrue);
      expect(ChatThread.isValidTenDigitId(ChatThread.generateTenDigitId()), isTrue);
    });

    test('la bio vocale non supera i 5 secondi', () {
      expect(
        () => UserProfile(
          id: '1234567890',
          name: 'Mario',
          email: 'mario@test.com',
          profileAudioDurationSeconds: 5.1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Validazione del numero di telefono', () {
    // Difetto originale: l'app accettava da 8 a 15 cifre mentre il server ne
    // richiedeva esattamente 10. La registrazione riusciva e l'accesso
    // successivo falliva per sempre, lasciando l'utente bloccato fuori.
    test('accetta esattamente 10 cifre', () {
      expect(AuthApi.validatePhone('3391234567'), isNull);
      expect(AuthApi.validatePhone('339 123 4567'), isNull);
      expect(AuthApi.validatePhone('339.123.4567'), isNull);
    });

    test('rifiuta un numero di lunghezza diversa da 10', () {
      for (final invalid in ['339123456', '33912345678', '12345', '1234567890123']) {
        expect(AuthApi.validatePhone(invalid), isNotNull, reason: 'accettava $invalid');
      }
    });

    test('rifiuta un numero vuoto o non numerico', () {
      expect(AuthApi.validatePhone(''), isNotNull);
      expect(AuthApi.validatePhone('   '), isNotNull);
      expect(AuthApi.validatePhone('abcdefghij'), isNotNull);
    });
  });

  group('Requisiti della password', () {
    test('accetta una password robusta', () {
      expect(AuthApi.validatePassword('Password123'), isNull);
      expect(AuthApi.validatePassword('Quice2026Sicura'), isNull);
    });

    test('rifiuta password corte o troppo semplici', () {
      expect(AuthApi.validatePassword('password'), isNotNull);
      expect(AuthApi.validatePassword('Password1'), isNotNull);
      expect(AuthApi.validatePassword('password123456'), isNotNull);
      expect(AuthApi.validatePassword('PASSWORD123456'), isNotNull);
      expect(AuthApi.validatePassword('PasswordOnly'), isNotNull);
    });
  });

  group('Token di sessione', () {
    test('il token viene salvato e la password no', () async {
      final backing = _MemorySecureStore();
      final store = SessionStore(storage: backing);
      final api = AuthApi(store: store, client: _mockAuth());

      final session = await api.login(phone: '3391234567', password: 'Password123');

      expect(session.token, isNotEmpty);
      expect(await store.readToken(), session.token);
      expect(await store.readUserId(), '3391234567');

      // La password non deve essere finita da nessuna parte nell'archivio.
      for (final entry in backing.values.entries) {
        expect(entry.value, isNot(contains('Password123')));
      }
    });

    test('la disconnessione cancella il token locale', () async {
      final store = _testStore();
      final api = AuthApi(store: store, client: _mockAuth());

      await api.login(phone: '3391234567', password: 'Password123');
      expect(await store.readToken(), isNotEmpty);

      await api.logout();
      expect(await store.readToken(), isNull);
    });

    test('l\'intestazione Authorization porta il token Bearer', () async {
      final store = _testStore();
      await store.save(token: 'abc123', userId: '3391234567');

      final headers = await store.authHeaders();
      expect(headers['Authorization'], 'Bearer abc123');
    });

    test('senza token non viene prodotta alcuna intestazione', () async {
      final store = _testStore();
      expect(await store.authHeaders(), isEmpty);
    });

    test('una sessione scaduta viene riconosciuta', () async {
      final store = _testStore();
      await store.save(
        token: 'abc',
        userId: '3391234567',
        expiresAt: DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      );
      expect(await store.isExpired(), isTrue);
    });

    test('una sessione ancora valida non viene data per scaduta', () async {
      final store = _testStore();
      await store.save(
        token: 'abc',
        userId: '3391234567',
        expiresAt: DateTime.now().add(const Duration(days: 5)).toIso8601String(),
      );
      expect(await store.isExpired(), isFalse);
    });
  });

  group('L\'identità non viaggia nella query string', () {
    // Difetto originale: ogni richiesta appendeva `?user_id=<numero di
    // telefono>`. Il numero finiva nei log di accesso del server e del proxy.
    test('nessuna rotta contiene user_id nella query', () {
      final api = ApiClient(baseUrl: 'https://chat.example.org/index.php');

      final chats = api.routeUri('chats');
      final messages = api.routeUri('chat', <String, String>{'chat_id': '2345678901'});

      expect(chats.query, isNot(contains('user_id')));
      expect(messages.queryParameters.keys, <String>['chat_id']);
      expect(messages.toString(), isNot(contains('user_id')));
    });

    test('l\'URL di un file non contiene credenziali', () {
      final api = ApiClient(baseUrl: 'https://chat.example.org/index.php');
      final uri = api.fileUri('20260101/abc_def.jpg');

      expect(uri.path, endsWith('serve_file.php'));
      expect(uri.queryParameters['file'], '20260101/abc_def.jpg');
      expect(uri.toString(), isNot(contains('user_id')));
    });
  });

  group('Trattamento degli errori', () {
    test('un 401 produce un errore di sessione', () async {
      final api = ApiClient(
        baseUrl: 'https://chat.example.org/index.php',
        store: _testStore(),
        client: MockClient((_) async => http.Response(
              jsonEncode(<String, dynamic>{
                'success': false,
                'error': 'Sessione mancante o scaduta. Accedi di nuovo.',
              }),
              401,
            )),
      );

      await expectLater(
        api.get('privacy'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });

    test('una risposta non JSON non espone dettagli tecnici', () async {
      final api = ApiClient(
        baseUrl: 'https://chat.example.org/index.php',
        store: _testStore(),
        client: MockClient((_) async => http.Response(
              '<html><body>Errore del server</body></html>',
              500,
            )),
      );

      await expectLater(
        api.get('privacy'),
        throwsA(isA<ApiException>().having(
          (e) => e.userMessage,
          'messaggio',
          isNot(contains('<html>')),
        )),
      );
    });
  });
}

http.Client _mockAuth() {
  return MockClient((request) async {
    final body = jsonEncode(<String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'token': 'token-di-test-' 'a' * 57,
        'expires_at': '2030-01-01T00:00:00+00:00',
        'user': <String, dynamic>{
          'id': '3391234567',
          'name': 'Mario',
          'nickname': 'mario',
          'email': 'mario@test.example',
        },
      },
    });
    return http.Response(body, 200);
  });
}
