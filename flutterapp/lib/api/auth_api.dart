import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/user_profile.dart';
import '../services/app_request_signer.dart';

class AuthApi {
  static const String _defaultUserName = 'Nuovo utente';
  static const String _defaultBaseUrl =
      'https://3e39-93-71-129-17.ngrok-free.app/webService/index.php';
  static http.Client _client = http.Client();
  static String baseUrl = _defaultBaseUrl;

  static void configure({http.Client? client, String? baseUrl}) {
    if (client != null) {
      _client = client;
    }
    if (baseUrl != null) {
      AuthApi.baseUrl = baseUrl;
    }
  }

  static void reset() {
    _client = http.Client();
    baseUrl = _defaultBaseUrl;
  }

  static Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth');
    final body = jsonEncode({
      'action': 'login',
      'email': email,
      'password': password,
    });
    final response = await _client.post(
      uri,
      headers: AppRequestSigner.buildSignedHeaders(
        method: 'POST',
        uri: uri,
        body: body,
        headers: const {'Content-Type': 'application/json'},
      ),
      body: body,
    );

    return _parseProfile(response, fallbackName: 'Utente');
  }

  static Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedName = name.trim().isEmpty ? _defaultUserName : name.trim();
    final uri = Uri.parse('$baseUrl/auth');
    final body = jsonEncode({
      'action': 'register',
      'name': normalizedName,
      'email': email,
      'password': password,
    });
    final response = await _client.post(
      uri,
      headers: AppRequestSigner.buildSignedHeaders(
        method: 'POST',
        uri: uri,
        body: body,
        headers: const {'Content-Type': 'application/json'},
      ),
      body: body,
    );

    return _parseProfile(response, fallbackName: normalizedName);
  }

  static UserProfile _parseProfile(
    http.Response response, {
    required String fallbackName,
  }) {
    if (response.statusCode >= 400) {
      throw Exception('Errore server (${response.statusCode}).');
    }

    dynamic payload;
    try {
      payload = jsonDecode(response.body);
    } catch (e) {
      print('====== ERRORE DAL SERVER PHP ======');
      print(response.body);
      print('===================================');
      throw Exception('Il server PHP ha restituito un errore HTML. Controlla la console per i dettagli.');
    }

    if (payload is! Map<String, dynamic>) {
      throw Exception('Risposta non valida dal server.');
    }

    if (payload['success'] != true) {
      throw Exception(payload['error'] ?? 'Errore autenticazione.');
    }

    final data = payload['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final id = data['id']?.toString() ?? UserProfile.generateTenDigitId();
    final name = data['name']?.toString().trim();
    final nickname = data['nickname']?.toString().trim();
    final email = data['email']?.toString() ?? '';

    return UserProfile(
      id: id,
      name: (name == null || name.isEmpty) ? fallbackName : name,
      nickname: (nickname == null || nickname.isEmpty)
          ? fallbackName
          : nickname,
      email: email,
    );
  }
}
