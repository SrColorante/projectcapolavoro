import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutterapp/api/auth_api.dart';
import 'package:flutterapp/models/chat_thread.dart';
import 'package:flutterapp/models/user_profile.dart';

void main() {
  group('10-digit IDs', () {
    setUp(() {
      AuthApi.configure(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final action = payload['action'];
          final name = payload['name']?.toString() ?? 'Utente';
          final email = payload['email']?.toString() ?? 'utente@test.com';
          final body = jsonEncode({
            'success': true,
            'data': {
              'id': '1234567890',
              'name': name,
              'nickname': name,
              'email': email,
            },
          });
          if (action != 'login' && action != 'register' && action != 'guest_login') {
            return http.Response('{"success":false}', 400);
          }
          return http.Response(body, 200);
        }),
      );
    });

    tearDown(() {
      AuthApi.reset();
    });

    test('validates user IDs correctly', () {
      expect(UserProfile.isValidTenDigitId('1234567890'), isTrue);
      expect(UserProfile.isValidTenDigitId('12345'), isFalse);
      expect(UserProfile.isValidTenDigitId('ABCDEFGHIJ'), isFalse);
    });

    test('throws when creating user profile with invalid ID', () {
      expect(
        () => UserProfile(id: '123', name: 'Mario', email: 'mario@test.com'),
        throwsArgumentError,
      );
    });

    test('generated IDs are always 10 digits', () {
      final generatedUserId = UserProfile.generateTenDigitId();
      final generatedChatId = ChatThread.generateTenDigitId();

      expect(UserProfile.isValidTenDigitId(generatedUserId), isTrue);
      expect(ChatThread.isValidTenDigitId(generatedChatId), isTrue);
    });

    test('validates profile audio duration max 5 seconds', () {
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

    test('auth API returns and preserves 10-digit IDs by email', () async {
      final registered = await AuthApi.register(
        name: 'Utente',
        email: 'utente@test.com',
        password: 'password',
      );
      final logged = await AuthApi.login(
        email: 'utente@test.com',
        password: 'password',
      );

      expect(UserProfile.isValidTenDigitId(registered.id), isTrue);
      expect(logged.id, registered.id);
    });
  });
}
