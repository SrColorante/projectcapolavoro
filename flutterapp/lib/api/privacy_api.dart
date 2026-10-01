import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Stato di una singola voce di consenso.
class ConsentEntry {
  const ConsentEntry({
    required this.type,
    required this.granted,
    required this.required,
    required this.title,
    required this.basis,
    this.policyVersion,
    this.decidedAt,
  });

  final String type;
  final bool granted;
  final bool required;
  final String title;
  final String basis;
  final String? policyVersion;
  final String? decidedAt;

  factory ConsentEntry.fromJson(String type, Map<String, dynamic> json) {
    return ConsentEntry(
      type: type,
      granted: json['granted'] == true,
      required: json['required'] == true,
      title: json['title']?.toString() ?? type,
      basis: json['basis']?.toString() ?? '',
      policyVersion: json['policy_version']?.toString(),
      decidedAt: json['decided_at']?.toString(),
    );
  }
}

/// Riepilogo dello stato della privacy dell'utente.
class PrivacyStatus {
  const PrivacyStatus({
    required this.consents,
    required this.processingRestricted,
    required this.policyVersion,
    required this.retention,
    required this.deletion,
    required this.activeSessions,
  });

  final Map<String, ConsentEntry> consents;
  final bool processingRestricted;
  final String policyVersion;
  final Map<String, int> retention;
  final Map<String, dynamic> deletion;
  final List<dynamic> activeSessions;

  /// Termine di conservazione, in giorni, per una risorsa.
  int retentionDays(String resource) => retention[resource] ?? 0;
}

/// API per l'esercizio dei diritti dell'interessato.
///
/// Tutte le operazioni richiedono una sessione valida: il backend non
/// restituisce dati personali a richieste anonime.
class PrivacyApi {
  PrivacyApi({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  @visibleForTesting
  ApiClient get api => _api;

  Future<PrivacyStatus> fetchStatus() async {
    final payload = await _api.get('privacy');
    final data = (payload['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

    final consents = <String, ConsentEntry>{};
    final raw = (data['consents'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    raw.forEach((type, value) {
      consents[type] = ConsentEntry.fromJson(
        type,
        Map<String, dynamic>.from(value as Map),
      );
    });

    final retention = <String, int>{};
    (data['retention'] as Map<String, dynamic>? ?? const <String, dynamic>{})
        .forEach((key, value) {
      final parsed = int.tryParse(value.toString());
      if (parsed != null) retention[key] = parsed;
    });

    return PrivacyStatus(
      consents: consents,
      processingRestricted: data['processing_restricted'] == true,
      policyVersion: data['policy_version']?.toString() ?? '',
      retention: retention,
      deletion: Map<String, dynamic>.from(
        (data['deletion'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      activeSessions: (data['active_sessions'] as List<dynamic>?) ?? const <dynamic>[],
    );
  }

  /// Esporta tutti i dati dell'utente in JSON (Art. 15 e 20).
  Future<String> exportDataAsJson() async {
    final payload = await _api.get('privacy', query: const {'view': 'export'});
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload['data'] ?? const <String, dynamic>{});
  }

  /// Concede un consenso opzionale.
  Future<void> grantConsent(String type) =>
      _postConsent('grant_consent', type, true);

  /// Ritira un consenso opzionale (Art. 7(3)).
  Future<void> withdrawConsent(String type) =>
      _postConsent('withdraw_consent', type, false);

  Future<void> _postConsent(String action, String type, bool granted) async {
    await _api.post('privacy', body: {
      'action': action,
      'type': type,
      'granted': granted,
    });
  }

  /// Attiva o revoca la limitazione del trattamento (Art. 18).
  Future<void> setProcessingRestriction(bool restricted) async {
    await _api.post('privacy', body: {
      'action': 'restrict',
      'value': restricted,
    });
  }

  /// Richiede l'eliminazione definitiva dell'account (Art. 17).
  ///
  /// Non e' immediata: il server concede una finestra di attesa, annullabile,
  /// prima della cancellazione. Questo evita che una richiesta fatta per
  /// errore — o sotto pressione — produca una perdita irreversibile.
  Future<Map<String, dynamic>> requestErasure() async {
    final payload = await _api.post('privacy', body: const {
      'action': 'request_erasure',
      'confirmation': 'ELIMINA',
    });
    return Map<String, dynamic>.from(
      (payload['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }

  Future<void> cancelErasure() async {
    await _api.post('privacy', body: const {'action': 'cancel_erasure'});
  }

  Future<void> revokeSession(String sessionId) async {
    await _api.post('privacy', body: {
      'action': 'revoke_session',
      'session_id': sessionId,
    });
  }
}
