# Registro delle attività di trattamento (art. 30 GDPR)

**Progetto:** Quice — messaggistica per reti locali
**Titolare del trattamento:** _da completare — vedi `PRIVACY_POLICY.md` §1_
**Versione del registro:** 1.0.0 — 1 ottobre 2026
**Aggiornato:** 1 ottobre 2026

---

## 1. Scopo del registro

Il registro elenca i trattamenti effettuati dal backend PHP e dall'app
Flutter, con la base giuridica, i dati coinvolti, i destinatari e i termini di
conservazione. È richiesto dall'art. 30 del Regolamento e va tenuto a
disposizione dell'autorità di controllo.

## 2. Trattamenti

### T-01 — Identificativi e autenticazione

| Campo | Valore |
|---|---|
| **Finalità** | Creazione dell'account, autenticazione, erogazione del servizio |
| **Dati** | Numero di telefono (10 cifre, identificativo univoco), nome, nickname, email (facoltativa), hash bcrypt della password |
| **Base giuridica** | Art. 6(1)(b) — esecuzione del contratto |
| **Categorie di interessati** | Utenti registrati |
| **Destinatari** | Nessuno. Nessun trasferimento a terzi |
| **Trasferimenti extra SEE** | Nessuno. Il servizio è pensato per ambienti isolati |
| **Conservazione** | Fino alla cancellazione dell'account |
| **Sistemi** | `utenti` (MySQL), `utenti_sessioni` |
| **Riferimenti** | `webService/resources/auth.php`, `webService/lib/auth.php` |

**Osservazione.** Il numero di telefono è l'identificativo primario: non esiste
un'identità email alternativa. La scelta è documentata per trasparenza, e la
sua necessità (trovare un interlocutore) è proporzionata allo scopo.

---

### T-02 — Contenuto delle conversazioni

| Campo | Valore |
|---|---|
| **Finalità** | Erogazione del servizio di messaggistica |
| **Dati** | Testi dei messaggi, identificativo chat, orario, stato di consegna/lettura, identificativo dei file allegati, stato di scrittura |
| **Base giuridica** | Art. 6(1)(b) — esecuzione del contratto |
| **Categorie di interessati** | Utenti registrati |
| **Destinatari** | I partecipanti della singola conversazione (art. 6(1)(b), in quanto terzi ai fini del singolo messaggio) |
| **Conservazione** | 365 giorni dalla creazione; cancellazione anticipata su richiesta dell'utente |
| **Sistemi** | `messaggi`, `chat`, `chat_members`, `chat_typing_status` |
| **Riferimenti** | `webService/resources/chat.php`, `webService/resources/chats.php` |

**Osservazione sulla base giuridica.** La base è il contratto, non il consenso:
il consenso non può rendere lecito ciò che il servizio è per sua natura. Il
consenso sarebbe la base errata, perché un rifiuto non potrebbe comunque
essere rispettato senza annullare il servizio stesso.

---

### T-03 — File allegati

| Campo | Valore |
|---|---|
| **Finalità** | Scambio di file all'interno delle conversazioni |
| **Dati** | Contenuto binario, nome originale, MIME reale, dimensione, chiave di archiviazione |
| **Base giuridica** | Art. 6(1)(b) — esecuzione del contratto |
| **Destinatari** | I partecipanti della conversazione in cui il file è stato condiviso |
| **Conservazione** | 180 giorni; cancellati in blocco con la chat o con l'account |
| **Sistemi** | `shared_files`, `webService/uploads/` (filesystem) |
| **Riferimenti** | `webService/resources/files.php`, `webService/lib/upload.php`, `webService/serve_file.php` |

**Osservazione sui diritti di terzi.** Un file può contenere dati di persone
diverse dall'utente che lo carica (foto, documenti). Chi carica un file con
dati di terzi ne risponde. L'interfaccia lo segnala nei termini di servizio.

---

### T-04 — Traduzione on-device

| Campo | Valore |
|---|---|
| **Finalità** | Traduzione dei messaggi nella lingua preferita |
| **Dati** | Testo dei messaggi, elaborato localmente dal modello ML Kit |
| **Base giuridica** | Art. 6(1)(a) — consenso, revocabile in qualsiasi momento |
| **Destinatari** | Nessuno. Il testo non lascia il dispositivo |
| **Conservazione** | Il testo tradotto non viene conservato sul server |
| **Sistemi** | Solo dispositivo |
| **Riferimenti** | `flutterapp/lib/services/message_translation_service.dart` |

**Osservazione.** Il trattamento è on-device: nessun dato viene trasferito a
Google o ad altri, nonostante l'uso di ML Kit. È comunque soggetto a consenso
perché altera la rappresentazione del dato.

---

### T-05 — Condivisione diretta sulla rete locale (peer-to-peer)

| Campo | Valore |
|---|---|
| **Finalità** | Consegna dei messaggi tramite i dispositivi vicini sulla stessa LAN |
| **Dati** | Contenuto dei messaggi, identificativi delle chat |
| **Base giuridica** | Art. 6(1)(a) — consenso esplicito per ciascun utente |
| **Destinatari** | Dispositivi dell'utente e dei destinatari presenti sulla stessa rete |
| **Conservazione** | Coda locale sul dispositivo del destinatario, sincronizzata al server |
| **Sistemi** | `flutterapp/lib/services/p2p_sync_service.dart`, `offline_message_store.dart` |
| **Riferimenti** | `Consent::assertPeerTransferAllowed()` in `webService/lib/consent.php` |

**Osservazione di sicurezza (rilevante per l'art. 32).** Il consenso è
**locale**, non solo lato server. Senza di esso il servizio non apre porte di
rete, non si registra in mDNS e non cerca peer: il dispositivo non espone nulla
sulla LAN. Un utente che revoca il consenso vede chiudersi la porta, non solo
un flag in un database.

---

### T-06 — Bio vocale

| Campo | Valore |
|---|---|
| **Finalità** | Presentazione del profilo |
| **Dati** | Registrazione audio, durata massima 5 secondi |
| **Base giuridica** | Art. 6(1)(a) — consenso specifico e separato |
| **Destinatari** | Gli utenti che aprono il profilo |
| **Conservazione** | Come T-03 |
| **Sistemi** | `shared_files`, `utenti.profile_audio_url` |
| **Riferimenti** | Controllo in `webService/resources/settings.php` |

**Osservazione.** I dati vocali possono essere considerati dati biometrici
(art. 4(14) e art. 9) in quanto consentono l'identificazione del parlante.
Per questo il consenso è richiesto in modo separato rispetto agli altri
trattamenti facoltativi, e il server **rifiuta** l'impostazione della bio
vocale se il consenso non è stato registrato.

---

### T-07 — Registro delle attività e sicurezza

| Campo | Valore |
|---|---|
| **Finalità** | Accountability: dimostrare l'osservanza del regolamento e accertare responsabilità |
| **Dati** | Orario, azione, esito, correlation id, pseudonimo HMAC dell'attore, hash troncato dell'IP |
| **Base giuridica** | Art. 6(1)(c) — adempimento di un obbligo legale di dimostrabilità; art. 32 — sicurezza del trattamento |
| **Destinatari** | Nessuno |
| **Conservazione** | 730 giorni |
| **Sistemi** | `audit_log` |
| **Riferimenti** | `webService/lib/logging.php` |

**Osservazione sulla pseudonimizzazione (art. 4(5)).** Il registro non contiene
dati identificativi diretti. L'attore è un HMAC-SHA256 dell'identificativo con
un pepper separato dal segreto applicativo; l'IP è un hash troncato a 32
caratteri. Alla cancellazione dell'account l'identificativo diretto viene
azzerato e resta solo lo pseudonimo: la responsabilità resta dimostrabile
senza conservare il dato identificativo.

---

### T-08 — Prove di consenso

| Campo | Valore |
|---|---|
| **Finalità** | Dimostrare la liceità del trattamento (art. 7(1)) |
| **Dati** | Tipo di consenso, decisione, versione dell'informativa, origine, data, pseudonimo |
| **Base giuridica** | Art. 7(1) — dimostrazione del consenso; art. 6(1)(c) |
| **Conservazione** | 1825 giorni dalla registrazione |
| **Sistemi** | `consensi` |
| **Riferimenti** | `webService/lib/consent.php` |

**Osservazione.** Questi dati sopravvivono alla cancellazione dell'account, in
forma pseudonima. Non è una scelta progettuale arbitraria: l'art. 17(3)(b)
consente di non cancellare i dati necessari a dimostrare la liceità del
trattamento. Senza di essi, in caso di controllo, non sarebbe possibile
dimostrare che l'utente aveva autorizzato il trattamento.

---

## 3. Trattamenti valutati e scartati

| Trattamento | Valutazione | Motivo |
|---|---|---|
| Cifratura end-to-end | Non implementata | Il server conserva le chiavi pubbliche ma non implementa il cifrario. Dichiarare la cifratura E2EE sarebbe una dichiarazione falsa: l'app riporta esplicitamente che il canale è protetto da TLS, non da E2EE |
| Pubblicità e profilazione | Non effettuato | Nessun servizio di terzi, nessun pixel di tracking |
| Analisi d'uso | Slot predisposto, disattivato | Se attivato in futuro, richiederà consenso specifico (voce `diagnostics` nel catalogo) |
| Biometria per autenticazione | Non implementata | L'autenticazione è basata su password e token, non su tratti biometrici |

## 4. Persone autorizzate

_Todo: indicare chi, oltre al titolare, ha accesso ai dati (amministratore di
sistema, docente, ecc.) e su quale base._

Ad oggi l'accesso al backend è possibile solo con credenziali del database e
token di sessione validi. Non sono previsti ruoli amministrativi separati.

## 5. Misure di sicurezza (art. 32)

Dettagliate in `webService/docs/SICUREZZA.md`. Sintesi:

- Autenticazione a token Bearer opaco, memorizzato solo come hash SHA-256.
- Verifica dei certificati TLS attiva.
- Password bcrypt, mai memorizzate sul dispositivo.
- Validazione del contenuto reale dei file caricati, estensione assegnata dal
  server.
- Consegna dei file subordinata a sessione valida e appartenenza alla chat.
- Registrazione di controllo pseudonima.
- Nessun dato personale nelle righe di log applicative.
