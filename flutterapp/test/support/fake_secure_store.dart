import 'package:flutterapp/api/session_store.dart';

/// Archivio sicuro in memoria, da usare nei test.
///
/// Il `flutter_secure_storage` reale parla con il Keychain di sistema e con
/// `MethodChannel`: in un test unitario non esiste alcun canale, quindi ogni
/// lettura lancerebbe. Sostituendolo si puo' verificare il comportamento della
/// sessione — inclusi i casi di errore — senza toccare il dispositivo.
class FakeSecureStore implements SecureStore {
  FakeSecureStore({Map<String, String>? initial})
      : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  /// Fa fallire ogni operazione: serve a verificare che un archivio non
  /// disponibile non porti a un crash dell'applicazione.
  bool failOnAccess = false;

  @override
  Future<String?> read(String key) async {
    if (failOnAccess) throw StateError('archivio non disponibile');
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failOnAccess) throw StateError('archivio non disponibile');
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failOnAccess) throw StateError('archivio non disponibile');
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    if (failOnAccess) throw StateError('archivio non disponibile');
    _values.clear();
  }

  /// Copia dei valori, per verificare che nessun segreto finisca dove non deve.
  Map<String, String> get values => Map<String, String>.unmodifiable(_values);

  void set(String key, String value) => _values[key] = value;
}

/// Sessione di prova con un token gia' presente.
SessionStore fakeSessionStore({String token = 'token-di-test', String userId = '1234567890'}) {
  final store = SessionStore(storage: FakeSecureStore(initial: <String, String>{
    'quice.session.token': token,
    'quice.session.user_id': userId,
  }));
  return store;
}
