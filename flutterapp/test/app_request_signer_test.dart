import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutterapp/services/app_request_signer.dart';

void main() {
  test('builds deterministic canonical requests and signed headers', () {
    final uri = Uri.parse(
      'https://example.test/webService/index.php/chat?user_id=1234567890',
    );
    const body = '{"textmessage":"Hello","reciverID":"1234567891"}';

    final canonicalRequest = AppRequestSigner.buildCanonicalRequest(
      method: 'POST',
      uri: uri,
      timestamp: '1716134400',
      body: body,
    );

    expect(
      canonicalRequest,
      'POST\n'
      '/webService/index.php/chat\n'
      'user_id=1234567890\n'
      '1716134400\n'
      '{"textmessage":"Hello","reciverID":"1234567891"}',
    );

    final headers = AppRequestSigner.buildSignedHeaders(
      method: 'POST',
      uri: uri,
      body: body,
      now: DateTime.fromMillisecondsSinceEpoch(1716134400 * 1000),
    );

    expect(headers[AppRequestSigner.keyHeader], AppRequestSigner.appKeyId);
    expect(headers[AppRequestSigner.timestampHeader], '1716134400');
    expect(
      base64Decode(headers[AppRequestSigner.signatureHeader]!),
      hasLength(32),
    );
  });
}
