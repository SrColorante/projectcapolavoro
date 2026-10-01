/// Configurazione del client, impostata in compilazione.
///
/// Prima l'indirizzo del server era una costante scritta a mano nel codice,
/// con un tunnel ngrok di esempio rimasto dentro. Ogni installazione richiedeva
/// una modifica al sorgente e una ricompilazione. Ora si passa dalla riga di
/// comando:
///
///     flutter run --dart-define=QUICE_BASE_URL=https://chat.example.org
///     flutter build windows --dart-define=QUICE_BASE_URL=https://chat.example.org
///
/// Se la variabile manca si cade su un indirizzo di sviluppo locale, che non
/// e' un segreto e non espone nessun servizio reale.
library;

class ApiConfig {
  const ApiConfig._();

  /// Indirizzo base dell'API. Deve terminare con `/` perche' le rotte vi
  /// vengano concatenate.
  static const String baseUrl = String.fromEnvironment(
    'QUICE_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/index.php',
  );

  /// Segreto per la firma HMAC delle richieste.
  ///
  /// NON e' un segreto di autenticazione e non va trattato come tale: vive
  /// dentro il binario dell'app e puo' essere estratto. Serve solo a rendere
  /// difficile il replay e la manomissione di una richiesta intercettata.
  /// L'autenticazione avviene tramite token di sessione, emesso dal server e
  /// conservato in un archivio sicuro del dispositivo.
  static const String signingSecret = String.fromEnvironment(
    'QUICE_APP_SECRET',
    defaultValue: 'quice-dev-signing-secret',
  );

  /// Identificatore della chiave di firma.
  static const String signingKeyId = 'crimson-chat-v1';

  /// Durata oltre la quale una richiesta firmata viene considerata scaduta.
  static const Duration signatureTolerance = Duration(minutes: 5);

  /// Etichetta del dispositivo, mostrata all'utente nell'elenco delle sessioni
  /// attive. Serve a riconoscere i propri accessi.
  static const String deviceLabel = String.fromEnvironment(
    'QUICE_DEVICE_LABEL',
    defaultValue: 'Quice',
  );
}
