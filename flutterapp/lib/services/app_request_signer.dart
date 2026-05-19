import 'dart:convert';

import 'package:crypto/crypto.dart';

class AppRequestSigner {
  AppRequestSigner._();

  static const String appKeyId = 'crimson-chat-v1';
  static const String _sharedSecret =
      'SEGRETO_DA_RUOTARE';
  static const String signatureHeader = 'X-App-Signature';
  static const String timestampHeader = 'X-App-Timestamp';
  static const String keyHeader = 'X-App-Key';

  static Map<String, String> buildSignedHeaders({
    required String method,
    required Uri uri,
    required String body,
    Map<String, String> headers = const <String, String>{},
    DateTime? now,
  }) {
    final timestamp =
        ((now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000).toString();
    final canonicalRequest = buildCanonicalRequest(
      method: method,
      uri: uri,
      timestamp: timestamp,
      body: body,
    );
    final signature = _sign(canonicalRequest);
    return <String, String>{
      ...headers,
      keyHeader: appKeyId,
      timestampHeader: timestamp,
      signatureHeader: signature,
    };
  }

  static String buildCanonicalRequest({
    required String method,
    required Uri uri,
    required String timestamp,
    required String body,
  }) {
    return <String>[
      method.toUpperCase(),
      uri.path,
      _normalizedQuery(uri),
      timestamp,
      body,
    ].join('\n');
  }

  static String _normalizedQuery(Uri uri) {
    final entries = <MapEntry<String, String>>[];
    for (final entry in uri.queryParametersAll.entries) {
      final values = List<String>.from(entry.value)..sort();
      for (final value in values) {
        entries.add(MapEntry(entry.key, value));
      }
    }
    entries.sort((left, right) {
      final keyComparison = left.key.compareTo(right.key);
      if (keyComparison != 0) {
        return keyComparison;
      }
      return left.value.compareTo(right.value);
    });

    return entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  static String _sign(String canonicalRequest) {
    final digest = Hmac(sha256, utf8.encode(_sharedSecret)).convert(
      utf8.encode(canonicalRequest),
    );
    return base64Encode(digest.bytes);
  }
}
