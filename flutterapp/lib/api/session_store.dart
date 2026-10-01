import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Archivio sicuro di chiavi e valori.
///
/// Un'interfaccia cosi' stretta serve a due scopi: disaccoppiare la sessione
/// dal plugin (che nei test non puo' girare, perche' richiederebbe il
/// Keychain di sistema) e rendere esplicito quali operazioni servono
/// davvero — solo tre.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Implementazione su Keychain / EncryptedSharedPreferences.
class PlatformSecureStore implements SecureStore {
  const PlatformSecureStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Archivio del token di sessione.
///
/// Perche' un archivio sicuro e non `SharedPreferences`
/// -------------------------------------------------
/// La versione precedente salvava in `SharedPreferences` la password in
/// chiaro e il numero di telefono, e li reinviava a ogni avvio. Su Android
/// `SharedPreferences` e' un XML leggibile da qualunque app con accesso
/// all'archivio dell'utente; su Windows e' testo semplice. La password era
/// quindi recuperabile da un dispositivo bloccato o da un backup non cifrato,
/// e non serviva a nulla: da quando esiste la sessione con token, l'accesso non
/// richiede piu' la password.
///
/// Qui si conserva solo il token di sessione, in un archivio che usa il
/// Keychain di iOS/macOS e EncryptedSharedPreferences su Android. Il token non
/// viene mai scritto in chiaro su disco in modo recuperabile e non finisce nei
/// log.
class SessionStore {
  SessionStore({SecureStore? storage}) : _storage = storage ?? const PlatformSecureStore();

  static const String _tokenKey = 'quice.session.token';
  static const String _userIdKey = 'quice.session.user_id';
  static const String _expiresAtKey = 'quice.session.expires_at';

  final SecureStore _storage;
  String? _cachedToken;

  /// Token corrente, se presente. Resta in memoria per la sessione del
  /// processo e non viene mai serializzato altrove.
  String? get token => _cachedToken;

  Future<String?> readToken() async {
    if (_cachedToken != null) return _cachedToken;
    _cachedToken = await _storage.read(_tokenKey);
    return _cachedToken;
  }

  /// Header `Authorization` da allegare a ogni richiesta autenticata.
  ///
  /// Se il token non c'e', si ottiene una mappa vuota: e' poi il chiamante a
  /// decidere se la richiesta richiedeva una sessione.
  ///
  /// Un errore dell'archivio non viene propagato. Un archivio sicuro
  /// temporaneamente illeggibile (Keychain bloccato, credenziali di sistema non
  /// sbloccate) non deve trasformarsi in un crash dell'applicazione: la
  /// richiesta partira' senza token e il server rispondere' 401, che e' una
  /// risposta comprensibile e recuperabile.
  Future<Map<String, String>> authHeaders() async {
    try {
      final value = await readToken();
      if (value == null || value.isEmpty) return const <String, String>{};
      return <String, String>{'Authorization': 'Bearer $value'};
    } on Object catch (error) {
      debugPrint('[quice] archivio sessione non disponibile: $error');
      return const <String, String>{};
    }
  }

  Future<void> save({
    required String token,
    required String userId,
    String? expiresAt,
  }) async {
    _cachedToken = token;
    await _storage.write(_tokenKey, token);
    await _storage.write(_userIdKey, userId);
    if (expiresAt != null) {
      await _storage.write(_expiresAtKey, expiresAt);
    }
  }

  Future<String?> readUserId() => _storage.read(_userIdKey);

  Future<String?> readExpiresAt() => _storage.read(_expiresAtKey);

  /// Indica, in base all'orario dichiarato dal server, se la sessione e' scaduta.
  ///
  /// Serve solo per proporre all'utente un reaccesso volontario: la verita'
  /// resta al server, che rifiuta comunque ogni richiesta con token scaduto.
  /// Un orologio del dispositivo sbagliato non deve bloccare l'uso, quindi una
  /// scadenza "impossibilmente" lontana nel passato viene ignorata.
  Future<bool> isExpired() async {
    final value = await readExpiresAt();
    if (value == null) return false;
    final expiresAt = DateTime.tryParse(value);
    if (expiresAt == null) return false;

    final remaining = expiresAt.difference(DateTime.now());
    if (!remaining.isNegative) return false;

    // Scaduto da oltre una settimana: quasi certamente un orologio
    // disassestato, non un token dimenticato.
    return remaining.inDays.abs() < 7;
  }

  Future<void> clear() async {
    _cachedToken = null;
    await _storage.delete(_tokenKey);
    await _storage.delete(_userIdKey);
    await _storage.delete(_expiresAtKey);
  }

  /// Svuota l'archivio. Nei test serve a non far sopravvivere il token da un
  /// caso all'altro, altrimenti l'ordine di esecuzione cambierebbe l'esito.
  @visibleForTesting
  Future<void> resetForTests() async {
    _cachedToken = null;
    await _storage.deleteAll();
  }
}

/// Istanza condivisa usata dall'applicazione.
final SessionStore sessionStore = SessionStore();
