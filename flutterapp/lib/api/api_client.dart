import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/app_request_signer.dart';
import 'api_config.dart';
import 'session_store.dart';

/// Errore restituito dall'API, con il codice HTTP per permettere alla UI di
/// reagire in modo mirato (per esempio 401 = sessione scaduta).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  /// Messaggio mostrato all'utente. I dettagli tecnici del server non devono
  /// trapelare: l'API in produzione non li invia, ma il client non deve
  /// comunque presumere di poterli mostrare.
  String get userMessage => message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Client HTTP unico dell'applicazione.
///
/// Perche' esiste
/// --------------
/// Ogni chiamata duplicava a mano tre cose: costruire l'URI con
/// `?user_id=<numero di telefono>`, firmare la richiesta e aggiungere gli
/// header. Concentrarle qui ha tre effetti:
///
///  1. l'identita' viaggia nell'header `Authorization`, non nella query string.
///     Nella query string finiva nei log di accesso del server e del proxy, e
///     il numero di telefono e' un dato personale: finiva a finire letto da
///     chi avesse accesso a quei log;
///  2. nessun endpoint puo' dimenticarsi di firmare o di allegare il token;
///  3. il trattamento degli errori e' identico ovunque.
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    SessionStore? store,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _store = store ?? sessionStore;

  static const Duration defaultTimeout = Duration(seconds: 10);

  final http.Client _client;
  final String _baseUrl;
  final SessionStore _store;

  String get baseUrl => _baseUrl;

  /// Client HTTP sottostante. Esposto perche' i servizi che devono condividere
  /// lo stesso canale (per esempio la sincronizzazione offline) ricevono il
  /// client gia' configurato, invece di crearne uno proprio: cosi' gli header
  /// e il token vengono applicati allo stesso modo anche da quel percorso.
  http.Client get client => _client;

  /// Costruisce l'URI di una rotta.
  ///
  /// La query string contiene solo parametri funzionali (id delle chat, filtri).
  /// Nessun identificativo dell'utente.
  Uri routeUri(String route, [Map<String, String>? query]) {
    final base = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    return Uri.parse('$base/$route').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  /// Compone gli header di una richiesta: firma HMAC più token Bearer.
  Future<Map<String, String>> _headers(Uri uri, String method, String body) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'QuiceApp/1.0.0 (${ApiConfig.deviceLabel})',
    };
    headers.addAll(await _store.authHeaders());
    headers.addAll(AppRequestSigner.buildSignedHeaders(
      method: method,
      uri: uri,
      body: body,
      headers: const <String, String>{},
    ));
    return headers;
  }

  Future<Map<String, dynamic>> get(
    String route, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final uri = routeUri(route, query);
    final response = await _client
        .get(uri, headers: await _headers(uri, 'GET', ''))
        .timeout(timeout ?? defaultTimeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String route, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final uri = routeUri(route, query);
    final encoded = jsonEncode(body ?? const <String, dynamic>{});
    final response = await _client
        .post(uri, headers: await _headers(uri, 'POST', encoded), body: encoded)
        .timeout(timeout ?? defaultTimeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> patch(
    String route, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final uri = routeUri(route, query);
    final encoded = jsonEncode(body ?? const <String, dynamic>{});
    final response = await _client
        .patch(uri, headers: await _headers(uri, 'PATCH', encoded), body: encoded)
        .timeout(timeout ?? defaultTimeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> delete(
    String route, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final uri = routeUri(route, query);
    final encoded = jsonEncode(body ?? const <String, dynamic>{});
    final response = await _client
        .delete(uri, headers: await _headers(uri, 'DELETE', encoded), body: encoded)
        .timeout(timeout ?? defaultTimeout);
    return _decode(response);
  }

  /// Caricamento di un file. La firma copre il corpo vuoto: in una richiesta
  /// multipart il corpo non e' leggibile da `php://input`, quindi firmarlo
  /// come se fosse il testo del file produrrebbe una firma sempre diversa.
  Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    Map<String, String> fields = const <String, String>{},
    Duration? timeout,
  }) async {
    final uri = routeUri('files');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _headers(uri, 'POST', ''));
    request.fields.addAll(fields);
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await request.send().timeout(timeout ?? const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  /// URL di un endpoint che consegna byte (immagini, audio, documenti).
  ///
  /// La richiesta avviene senza header personalizzati: il file si scarica
  /// passando il token come parametro esplicito, che il server registra come
  /// accesso. Non e' la forma preferita, ma `package:http` non permette di
  /// allegare header a un semplice download su tutte le piattaforme.
  Uri fileUri(String storageKey) {
    final base = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    return Uri.parse('$base/serve_file.php').replace(
      queryParameters: <String, String>{'file': storageKey},
    );
  }

  /// Decodifica la risposta e solleva `ApiException` in caso di errore.
  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw ApiException('Risposta non valida dal server.', statusCode: response.statusCode);
      }
      payload = decoded;
    } on FormatException {
      throw ApiException(
        'Il server ha risposto in un formato inatteso. '
        'Verifica che l\'indirizzo punti al backend Quice.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        payload['error']?.toString() ?? 'Errore del server (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (payload['success'] == false) {
      throw ApiException(
        payload['error']?.toString() ?? payload['message']?.toString() ?? 'Operazione non riuscita.',
        statusCode: response.statusCode,
      );
    }
    return payload;
  }
}
