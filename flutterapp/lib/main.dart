import 'package:flutter/material.dart';

import 'app.dart';
import 'services/app_preferences.dart';

/// Avvio dell'applicazione.
///
/// NOTA SULLA VERIFICA DEI CERTIFICATI
/// ------------------------------------
/// La versione precedente installava un `HttpOverrides` globale con
/// `badCertificateCallback = ... => true`, per tutte le destinazioni e per tutta
/// la durata del processo. In pratica HTTPS non offriva alcuna protezione: un
/// intermediario di rete (o un semplice proxy di laboratorio) poteva leggere e
/// modificare tutto il traffico, compresi messaggi e token di sessione.
///
/// Non e' stato sostituito con un'alternativa "piu' permissiva ma per
/// dominio": disattivare la verifica dei certificati e' sempre una cattiva idea,
/// e accettarla solo per un host preciso richiederebbe a ogni utente di fidarsi
/// di una lista codificata in un binario. Se in laboratorio si usa un
/// certificato autofirmato, la soluzione corretta e' installare la CA
/// radice nel sistema operativo, non disattivare i controlli.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  runApp(const CrimsonChatApp());
}
