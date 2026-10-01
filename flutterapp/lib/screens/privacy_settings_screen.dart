import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/privacy_api.dart';
import '../services/app_preferences.dart';

/// Schermata per l'esercizio dei diritti dell'interessato.
///
/// Rende accessibili dall'app, senza intervento dell'amministratore, i diritti
/// previsti dal GDPR:
///
///  - accesso e portabilita' (Art. 15 e 20) — export completo in JSON;
///  - limitazione del trattamento (Art. 18);
///  - opposizione e ritiro del consenso (Art. 7(3) e 21);
///  - cancellazione dell'account (Art. 17);
///  - elenco delle sessioni attive, con revoca a distanza.
///
/// La schermata mostra anche i termini di conservazione applicati: un utente
/// informato della scadenza dei propri dati puo' fare scelte diverse da chi
/// non lo sa.
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final PrivacyApi _api = PrivacyApi();

  PrivacyStatus? _status;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final status = await _api.fetchStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.userMessage : e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy e dati'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final status = _status!;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'I tuoi dati',
          children: [
            Text(
              'Versione dell\'informativa: ${status.policyVersion}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Quice tratta i dati per erogare il servizio di messaggistica. '
              'I trattamenti opzionali richiedono il tuo consenso e puoi '
              'ritirarlo in qualsiasi momento: il ritiro è efficace immediatamente '
              'e non modifica gli accessi già effettuati.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _exportData,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Scarica tutti i miei dati'),
            ),
            const SizedBox(height: 4),
            Text(
              'Un file JSON con profilo, conversazioni, messaggi, file, '
              'sessioni, consensi e registro delle attività.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        _SectionCard(
          title: 'Trattamenti facoltativi',
          children: [
            for (final entry in status.consents.values)
              if (!entry.required) _ConsentTile(entry: entry, api: _api, onChanged: _load),
            if (status.consents.values.every((e) => e.required))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nessun trattamento facoltativo attivo.'),
              ),
          ],
        ),
        _SectionCard(
          title: 'Trattamento necessario',
          children: [
            for (final entry in status.consents.values)
              if (entry.required)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: Text(entry.title),
                  subtitle: Text(entry.basis),
                  trailing: const Icon(Icons.check_circle_outline, size: 20),
                ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Questi trattamenti sono necessari al funzionamento del servizio: '
                'per ritirarli occorre eliminare l\'account.',
              ),
            ),
          ],
        ),
        _SectionCard(
          title: 'Limitazione del trattamento (Art. 18)',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: status.processingRestricted,
              onChanged: _setRestriction,
              title: const Text('Limita il trattamento'),
              subtitle: const Text(
                'Blocca l\'invio di nuovi messaggi, mantenendo accesso ai '
                'propri dati, rettifica, portabilità e cancellazione.',
              ),
            ),
          ],
        ),
        _SectionCard(
          title: 'Conservazione',
          children: [
            _RetentionRow(label: 'Messaggi', days: status.retentionDays('messaggi_days')),
            _RetentionRow(label: 'File allegati', days: status.retentionDays('files_days')),
            _RetentionRow(label: 'Sessioni', days: status.retentionDays('sessions_days')),
            _RetentionRow(label: 'Registro attività', days: status.retentionDays('audit_log_days')),
            _RetentionRow(
              label: 'Prove di consenso',
              days: status.retentionDays('consent_records_days'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Le prove di consenso sopravvivono alla cancellazione dell\'account, '
                'in forma pseudonima: servono a dimostrare che il trattamento '
                'era autorizzato.',
              ),
            ),
          ],
        ),
        _SectionCard(
          title: 'Sessioni attive',
          children: [
            if (status.activeSessions.isEmpty)
              const Text('Nessuna sessione registrata.')
            else
              for (final session in status.activeSessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_rounded),
                  title: Text('${session['device'] ?? 'Dispositivo sconosciuto'}'),
                  subtitle: Text('Ultimo uso: ${session['last_used_at'] ?? 'n/d'}'),
                  trailing: session['active'] == true
                      ? TextButton(
                          onPressed: () => _revokeSession('${session['id']}'),
                          child: const Text('Revoca'),
                        )
                      : const Text('scaduta', style: TextStyle(fontSize: 12)),
                ),
          ],
        ),
        _SectionCard(
          title: 'Eliminazione dell\'account (Art. 17)',
          children: [
            if (status.deletion['cancellable'] == true) ...[
              const Text(
                'Hai già richiesto l\'eliminazione del tuo account. Puoi '
                'annullare la richiesta finché non viene eseguita.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _cancelErasure,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Annulla la richiesta di eliminazione'),
              ),
            ] else ...[
              const Text(
                'L\'eliminazione rimuove profilo, messaggi, file e sessioni. '
                'Non è immediata: hai un periodo di attesa per annullarla, '
                'nel caso avessi premuto per errore.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _requestErasure,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Elimina il mio account'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _openPrivacyPolicy,
          child: const Text('Leggi l\'informativa privacy completa'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Azioni
  // ------------------------------------------------------------------

  Future<void> _exportData() async {
    try {
      final json = await _api.exportDataAsJson();
      if (!mounted) return;

      final fileName =
          'quice-export-${DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-')}.json';
      final directory = await _exportDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(json);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dati esportati in ${file.path}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on Object catch (e) {
      _showError(e);
    }
  }

  /// Cartella in cui depositare l'export.
  ///
  /// Su desktop e mobile `path_provider` restituisce la directory dei documenti
  /// dell'applicazione: l'utente puo' poi condividere il file da lì. Se il
  /// percorso non è ottenibile, si ripiega sulla directory temporanea del
  /// sistema, così l'export non fallisce per un problema di percorso.
  Future<Directory> _exportDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } on Object {
      return Directory.systemTemp;
    }
  }

  Future<void> _setRestriction(bool restricted) async {
    try {
      await _api.setProcessingRestriction(restricted);
      await _load();
    } on Object catch (e) {
      _showError(e);
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    try {
      await _api.revokeSession(sessionId);
      await _load();
    } on Object catch (e) {
      _showError(e);
    }
  }

  Future<void> _requestErasure() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare l\'account?'),
        content: const Text(
          'Verranno rimossi profilo, messaggi, file e sessioni. Avrai un '
          'periodo di attesa per annullare la richiesta, dopo il quale '
          'l\'eliminazione diventerà definitiva.\n\n'
          'Questa operazione non può essere annullata dall\'amministratore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Seconda conferma esplicita: evita che un tocco accidentale basta a
    // iniziare una procedura di cancellazione.
    final typed = await showDialog<String>(
      context: context,
      builder: (context) => _ConfirmationDialog(),
    );
    if (typed != 'ELIMINA' || !mounted) return;

    try {
      await _api.requestErasure();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Richiesta registrata. Puoi annullarla dalle impostazioni.'),
        ),
      );
      await _load();
    } on Object catch (e) {
      _showError(e);
    }
  }

  Future<void> _cancelErasure() async {
    try {
      await _api.cancelErasure();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Richiesta annullata. Accedi di nuovo.')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on Object catch (e) {
      _showError(e);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    try {
      final text = await rootBundle.loadString('assets/legal/privacy_policy.txt');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: Text(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      );
    } on Object {
      if (!mounted) return;
      _showError('Il testo dell\'informativa non è disponibile in questa build.');
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ApiException ? error.userMessage : error.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ConfirmationDialog extends StatefulWidget {
  @override
  State<_ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<_ConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _controller.text.trim() == 'ELIMINA';
    return AlertDialog(
      title: const Text('Conferma di eliminazione'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Digita ELIMINA per confermare.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: matches ? () => Navigator.of(context).pop('ELIMINA') : null,
          child: const Text('Elimina definitivamente'),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.entry,
    required this.api,
    required this.onChanged,
  });

  final ConsentEntry entry;
  final PrivacyApi api;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: entry.granted,
      title: Text(entry.title),
      subtitle: Text(entry.basis),
      onChanged: (granted) async {
        try {
          if (granted) {
            await api.grantConsent(entry.type);
            await AppPreferences.instance.setConsent(entry.type, true);
          } else {
            await api.withdrawConsent(entry.type);
            await AppPreferences.instance.setConsent(entry.type, false);
          }
          await onChanged();
        } on Object catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e is ApiException ? e.userMessage : e.toString())),
          );
        }
      },
    );
  }
}

class _RetentionRow extends StatelessWidget {
  const _RetentionRow({required this.label, required this.days});

  final String label;
  final int days;

  @override
  Widget build(BuildContext context) {
    if (days <= 0) return const SizedBox.shrink();
    final years = days / 365;
    final human = years >= 1
        ? '${years.toStringAsFixed(years % 1 == 0 ? 0 : 1)} anni'
        : '$days giorni';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      trailing: Text(human),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Riprova')),
          ],
        ),
      ),
    );
  }
}
