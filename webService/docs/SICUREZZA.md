# Sicurezza — misure tecniche (art. 32 GDPR)

**Progetto:** Quice
**Versione:** 1.0.0 — 1 ottobre 2026

Questo documento descrive le misure applicate, il problema che ciascuna risolve
e come verificarla. Le misure non sono elencate per soddisfare l'art. 32: sono
il motivo per cui il trattamento è praticabile.

---

## 1. Il difetto di partenza

La versione precedente del backend **non aveva autenticazione**. L'identità
dell'utente arrivava dalla query string:

```php
// index.php (prima)
$current_user_id = isset($_GET['user_id']) ? str_replace(' ', '', $_GET['user_id']) : null;
```

L'unica protezione era una firma HMAC con un segreto **unico per
l'installazione**, presente nel codice del client e quindi nel repository
pubblico. Conseguenze:

- chiunque conoscesse un numero di telefono poteva **leggere e scrivere** i
  messaggi, i file e il profilo di quella persona;
- il segreto era in un repository pubblico, quindi non era un segreto;
- `serve_file.php` non richiedeva alcuna autenticazione e serviva ogni file con
  `Access-Control-Allow-Origin: *`;
- l'endpoint di caricamento non validava il tipo di file e accettava il MIME
  dichiarato dal client.

Nessuna di queste condizioni è compatibile con l'art. 32: non è sufficiente
"avere HTTPS" se poi l'identità è dichiarata dall'utente.

---

## 2. Autenticazione

### Token di sessione

| Aspetto | Implementazione |
|---|---|
| Token | 32 byte casuali (`random_bytes`), 64 caratteri esadecimali |
| Storage lato server | Solo `SHA-256(token)`, mai il token |
| Storage lato client | `flutter_secure_storage` (Keychain / EncryptedSharedPreferences) |
| Trasporto | Header `Authorization: Bearer` |
| Durata | 30 giorni, con rinnovo scorrevole a metà TTL |
| Revoca | Singola sessione, tutte le sessioni, o tutte al cambio password |

**Perché un token e non la password a ogni richiesta.** La password non viene
più inviata dopo l'accesso. Prima era salvata in chiaro in `SharedPreferences`
— che su Android è un XML leggibile da qualunque altra app con accesso
all'archivio dell'utente — e reinviata a ogni avvio. Con il token, un
dispositivo perso espone una credenziale limitata nel tempo e revocabile.

**Perché l'hash.** Conservare l'hash significa che una copia del database
(non trafugata per l'autenticazione, ma per un backup) non permette di
ricostruire i token: un attaccante dovrebbe indovinere 256 bit di casualità,
non decifrare.

### Difese aggiuntive

- **Rate limit di accesso** per utente e per indirizzo IP, con finestra
  scorrevole. Un attacco a spruzzo su più account viene limitato dal controllo
  sull'IP.
- **Risposta uniforme** fra utente inesistente e password errata, e confronto
  eseguito comunque con password fittizia: il tempo di risposta non rivela se
  un numero è registrato.
- **Rehash automatico** se il costo di `bcrypt` cambia.
- **Firma HMAC delle richieste** mantenuta come protezione da manomissione e
  replay. **Non è un segreto di autenticazione**: vive nel binario del client.
  Il segreto di produzione è obbligatorio (`APP_ENV=production`).
- **Rifiuto del segreto di sviluppo in produzione**: se `QUICE_APP_SECRET`
  manca, il server risponde 503 e si rifiuta di avviarsi.

---

## 3. File caricati

| Controllo | Implementazione |
|---|---|
| MIME reale | `finfo` sul file temporaneo, non `$_FILES['type']` |
| Estensioni bloccate | 34 estensioni eseguibili (php, phtml, phar, sh, exe, jar, …) |
| Coerenza contenuto/estensione | Un `.jpg` il cui contenuto non è un'immagine viene rifiutato |
| Estensione finale | Assegnata dal server dal MIME reale; `.bin` per i tipi ignoti |
| Nome su disco | 24 byte casuali, mai il nome originale |
| Permessi | `0640` |
| MIME vietati | HTML, XHTML, PHP, eseguibili, JavaScript |
| Limite dimensione | 50 MiB, configurabile |

Il MIME dichiarato dal client è trattato come non attendibile: è un campo di
formulario, non una misura.

**`serve_file.php` richiede:**

1. una sessione valida;
2. di essere il proprietario del file **oppure** un partecipante della chat in
   cui è stato condiviso.

Prima non richiedeva nulla. Il nome del file contiene inoltre 24 byte di
casualità, il che rende l'enumerazione impraticabile anche per chi conoscesse
il formato.

**Il bypass tramite "password admin" per file oltre 50 MiB è stato rimosso.**
Era una backdoor con password in chiaro nel codice, presente su ogni
installazione, e non era una misura di sicurezza: era una chiave di
superamento del limite, non qualcosa che proteggesse i dati.

---

## 4. Trasporto

- **Verifica dei certificati TLS attiva.** La versione precedente installava un
  `HttpOverrides` globale con `badCertificateCallback => true`: HTTPS non
  offriva alcuna protezione, per qualunque destinazione e per tutto il tempo
  di vita del processo.
- **HSTS** in produzione.
- **CORS a lista bianca** (`QUICE_ALLOWED_ORIGINS`). Il carattere jolly è
  accettato solo in sviluppo; in produzione è rifiutato.
- **`Referrer-Policy: no-referrer`**, per non propagare l'URL del server — che
  può contenere identificativi di risorsa — ad altre origini.
- **`X-Content-Type-Options: nosniff`** su ogni risposta, per impedire che il
  browser interpreti un file caricato come script.

> Per un certificato autofirmato in laboratorio: installare la CA radice nel
> sistema operativo. Disattivare la verifica non è un'alternativa accettabile.

---

## 5. Dati nei log

| Dove | Prima | Ora |
|---|---|---|
| Log applicativi | URI completo, con `user_id` = numero di telefono | Metodo, risorsa, correlation id |
| Registro di controllo | — | Pseudonimo HMAC dell'attore, hash troncato dell'IP |
| Errori | Messaggio dell'eccezione al client | Dettaglio solo nel log; risposta generica in produzione |
| Token | — | Nessun endpoint li registra; `authHeaders` non stampa nulla |

Il numero di telefono finiva nelle righe di log di accesso di Apache perché
passava nella query string. Ora non transita più da lì.

Il correlation id permette di ricostruire un incidente senza conservare dati
personali.

---

## 6. Configurazione

- Nessun segreto nel codice. Tutto da `.env`, che è in `.gitignore`.
- In produzione il server si rifiuta di avviarsi se mancano
  `QUICE_APP_SECRET`, `QUICE_PRIVACY_PEPPER` o `QUICE_ALLOWED_ORIGINS`.
- Nessuna credenziale di database nel sorgente.
- Nessun DDL a runtime: le migrazioni stanno in `migrate.php` e girano una
  volta sola. Prima, `db.php` eseguiva sei `ALTER TABLE` a ogni richiesta.
- Percorsi di sistema bloccati via `.htaccess`: `.env`, `lib/`, `tests/`,
  `migrate.php`, `*.sql`.

---

## 7. Verifiche automatizzate

```bash
php webService/tests/run.php          # 50 verifiche
php webService/tests/smoke_http.php   # 13 verifiche
cd flutterapp && flutter test         # 31 test
```

Coprono, fra gli altri, i casi di regressione sui difetti descritti sopra:

| Test | Cosa impedisce la regressione |
|---|---|
| «un token non può impersonare un altro utente» | Il ritorno all'identità dichiarata dal client |
| «il database contiene solo l'hash del token» | La conservazione del token in chiaro |
| «il parametro ?user_id non autentica più» | La riapertura del bypass in `index.php` |
| «serve_file senza sessione non consegna il file» | L'accesso anonimo ai file |
| «un file con estensione eseguibile viene rifiutato» | La riapertura dell'upload di script |
| «un'immagine il cui contenuto è codice viene rifiutata» | Il MIME dichiarato dal cliente come fonte di verità |
| «il token viene salvato e la password no» | La reintroduzione della password su disco |
| «l'identità non viaggia nella query string» | Il ritorno dell'identificativo in URL |
| «i consensi sopravvivono pseudonimi» | La cancellazione delle prove di liceità |
| «il registro di controllo perde l'ID ma conserva la prova» | La perdita di accountability o la conservazione dell'identificativo |

I test del backend girano su SQLite in memoria e non richiedono MySQL.

---

## 8. Limiti noti, dichiarati

| Limite | Impatto | Stato |
|---|---|---|
| Nessuna cifratura end-to-end | Il server legge i messaggi | Dichiarato nell'app e nella privacy policy |
| Nessuna autorizzazione per ruoli | Chi ha accesso al database ha accesso a tutto | Documentato in ROPA §4 |
| Nessun 2FA funzionante | La 2FA è memorizzata ma gli OTP non vengono emessi | Segnalato come gap |
| Assenza di protezione anti-forza bruta oltre il rate limit | Attacchi lenti distribuiti | Accettato per il caso d'uso LAN |
| Export su disco in chiaro | L'utente deve custodire il file | Dichiarato nella schermata |
| I dati di terzi nelle chat non sono cancellabili | Chi possiede il dispositivo conserva le conversazioni | Dichiarato nella privacy policy |

Un limite dichiarato è una scelta informata. Un limite nascosto è un
danno all'utente che scopre il problema nel momento peggiore.
