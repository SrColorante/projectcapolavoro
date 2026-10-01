# Quice

> Messaggistica per reti locali, self-hosted. Flutter + PHP/MySQL.

WhatsApp e Discord richiedono internet e server di terze parti, cosa
inaccettabile in ambienti isolati o ad alta sicurezza. Quice è pensato per
**laboratori informatici, scuole e reti ad aria isolata**, dove i messaggi non
devono uscire dalla rete locale.

---

## Stato del progetto

| Area | Stato |
|---|---|
| Autenticazione | Token di sessione Bearer, hash SHA-256, revocabile |
| Autorizzazione | Verificata per proprietario e partecipanti alla chat |
| Diritto all'oblio (Art. 17) | Implementato, con finestra di annullamento |
| Esportazione (Art. 15/20) | Implementata, JSON strutturato |
| Consensi (Art. 7) | Registro append-only con prova e revoca |
| Limitazione (Art. 18) | Implementata |
| Conservazione (Art. 5(1)(e)) | Termini configurabili + job automatico |
| Registro di controllo | Pseudonimo, niente PII in chiaro |
| Cifratura end-to-end | **Non implementata** — dichiarata come assente |
| Test | 50 PHP + 13 smoke PHP + 31 Dart, tutti verdi |
| 2FA | Schema presente, OTP non emessi |

---

## Avviso importante: GDPR e dati già esposti

Il repository ha contenuto **11 file caricati da utenti reali**
(fotografie, registrazioni vocali, un brano audio) in una cartella tracciata
da git, in un repository **pubblico**. Sono stati rimossi dall'indice e
ignorati da git, ma restano nella cronologia dei commit.

**Azioni richieste a chi gestisce l'installazione, in questa ordine:**

1. **Leggere** [`docs/LEGAL/PURGA-GIT.md`](docs/LEGAL/PURGA-GIT.md) e seguire
   la procedura di purga della cronologia.
2. **Ruotare ogni segreto** che era nel repository: chiave di firma, pepper
   per la pseudonimizzazione, password del database, e revocare qualsiasi URL
   pubblico (ngrok o simile) usato per le prove.
3. **Valutare la notifica della violazione** secondo
   [`docs/LEGAL/PROCEDURA-VIOLAZIONE.md`](docs/LEGAL/PROCEDURA-VIOLAZIONE.md)
   §V-01. La decisione spetta al titolare del trattamento e va verbalizzata.

Nessuno di questi passi può essere eseguito al posto del titolare: sono
decisioni e attività che ne comportano la responsabilità.

---

## Requisiti

| Componente | Versione |
|---|---|
| Flutter | 3.47.5 stable; Dart `>=3.11.5 <4.0.0` |
| PHP | **≥ 8.0** con `pdo_mysql`, `fileinfo`, `openssl`, `json`, `mbstring` |
| MySQL | 8 / MariaDB 10.x |
| Composer | Solo per il server WebSocket opzionale |

## Configurazione

### 1. Database

```bash
# Su un database vuoto: lo schema completo, con utenti di prova in fondo
mysql -u root -p < webService/chat.sql

# Su un'installazione esistente: le migrazioni, una volta sola
php webService/migrate.php status
php webService/migrate.php up
```

> `chat.sql` contiene `DROP DATABASE`. **Non usarlo su un'istanza reale**:
> importarlo sovrascrive il database. Per un'istanza esistente usare
> `migrate.php up`.

> Il file include tre utenti di prova con password `password`. Non esistono più
> `seed.php` e `chat_migration_v2.sql`: sono sostituiti da `migrate.php`.

### 2. Configurazione

```bash
cd webService
cp .env.example .env
# Genera i segreti, distinti fra loro:
openssl rand -hex 32   # -> QUICE_APP_SECRET
openssl rand -hex 32   # -> QUICE_PRIVACY_PEPPER
```

`APP_ENV=production` fa fallire l'avvio se mancano i segreti obbligatori: è
voluto, perché un servizio che gira con credenziali prevedibili è peggio di
uno che non parte.

### 3. Backend

```bash
chmod -R 750 webService/uploads
```

Apache con `mod_rewrite` e `AllowOverride All` su `webService/`, oppure per
provare:

```bash
cd webService && php -S 0.0.0.0:8000
```

In questo caso le rotte si raggiungono come `/index.php?route=chats`: le regole
`.htaccess` vengono ignorate da `php -S`.

> **In produzione** impostate `QUICE_UPLOADS_DIR` su un percorso **fuori** dal
> DocumentRoot. In quel modo `serve_file.php` è l'unico modo di leggere i file,
> e non serve affidarsi al `.htaccess`.

### 4. App

```bash
cd flutterapp
flutter pub get
flutter run --dart-define=QUICE_BASE_URL=https://chat.example.org
```

`QUICE_BASE_URL` è l'unico parametro necessario. Prima l'indirizzo era una
costante nel sorgente, con dentro un tunnel ngrok di prova: ogni
installazione richiedeva una modifica al codice e una ricompilazione.

| Variabile | Default | Scopo |
|---|---|---|
| `QUICE_BASE_URL` | `http://127.0.0.1:8000/index.php` | Indirizzo del server |
| `QUICE_APP_SECRET` | segreto di sviluppo | Firma anti-manomissione |
| `QUICE_DEVICE_LABEL` | `Quice` | Etichetta nelle sessioni attive |

`QUICE_APP_SECRET` non è un segreto di autenticazione: vive nel binario.
L'autenticazione è il token di sessione.

---

## Struttura

```
projectCapolavoro/
├── flutterapp/            Client Flutter
│   ├── lib/api/           api_client, auth_api, privacy_api, session_store
│   ├── lib/services/      preferenze, firma, P2P, traduzione
│   ├── lib/screens/       interfacce, incluse privacy_settings_screen
│   ├── assets/legal/      informativa privacy incorporata
│   └── test/              31 test
├── webService/            Backend PHP
│   ├── lib/               config, db, http, logging, auth, consent,
│   │                      privacy, retention, upload
│   ├── resources/         auth, chats, chat, settings, security, files,
│   │                      privacy, users
│   ├── tests/             suite SQLite + smoke test HTTP
│   ├── migrate.php        migrazioni, conservazione, cancellazioni
│   ├── docs/SICUREZZA.md  misure tecniche (art. 32)
│   └── .env.example
└── docs/LEGAL/            documentazione di conformità
    ├── ROPA.md            registro attività (art. 30)
    ├── DPIA.md            valutazione d'impatto (art. 35)
    ├── PROCEDURA-VIOLAZIONE.md   notifica (art. 33, 34)
    ├── MATRICE-DATI.md    dato → base giuridica → conservazione
    └── PURGA-GIT.md       rimozione dati dalla cronologia
```

---

## Test

```bash
php webService/tests/run.php          # 50 verifiche (SQLite, senza MySQL)
php webService/tests/smoke_http.php   # 13 verifiche sul cablaggio HTTP
cd flutterapp && flutter test         # 31 test
```

Le suite PHP non richiedono un server MySQL: girano su SQLite in memoria e
registrano `UTC_TIMESTAMP()` per produrre lo stesso SQL di produzione.

I test coprono le regressioni sui difetti di sicurezza principali. Un test
chiamato «un token non può impersonare un altro utente» fallisce se qualcuno
reintroduce l'identità dichiarata dal client.

---

## Come funziona

```
Client Flutter
  ├── HTTPS + Bearer ──► webService/index.php
  │                        ├── firma HMAC (anti-manomissione)
  │                        ├── risoluzione token → utente
  │                        └── resources/*.php
  ├── WebSocket ────────► ws-server.php  [opzionale, richiede composer]
  ├── mDNS + P2P ───────► altri client   [solo con consenso]
  └── polling 8s/2s ────► /chats, /chat
```

L'identità dell'utente viaggia **soltanto** nell'header `Authorization`. Non
compare mai nella query string, quindi non finisce nei log di accesso — dove il
numero di telefono è un dato personale.

**Il tempo reale è il polling HTTP.** Il server WebSocket è opzionale e
richiede `composer install`; senza, l'app funziona normalmente.

---

## Note di sicurezza

- **Nessuna cifratura end-to-end.** Il canale è protetto da TLS, non da E2EE.
  L'app lo dichiara esplicitamente. Vedi
  [`webService/docs/SICUREZZA.md`](webService/docs/SICUREZZA.md) §8.
- **Gli account ospite scadono** dopo 7 giorni.
- **Nessun ruolo amministrativo**: chi ha accesso al database ha accesso a
  tutto. Va dichiarato se l'installazione è condivisa.
- **I file sono pubblici solo per i partecipanti** della chat in cui sono stati
  condivisi.

## Documenti legacy

`gemini.md` e `todo.md` sono piani di lavoro in italiano. Descrivono uno stato
precedente del codice e non sono documentazione corrente. Sono conservati perché
`todo.md` è l'unica enunciazione dei requisiti originali.
