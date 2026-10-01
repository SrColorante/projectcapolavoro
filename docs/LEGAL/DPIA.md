# Data Protection Impact Assessment (DPIA) — art. 35 GDPR

**Progetto:** Quice — messaggistica per reti locali
**Valutazione:** 1 ottobre 2026
**Esito:** trattamento a rischio medio-alto; mitigazioni obbligatorie
implementate, con tre condizioni di esercizio.

---

## 1. Sintesi

Quice è un'applicazione di messaggistica destinata a laboratori informatici,
scuole e ambienti isolati dalla rete pubblica. Elabora contenuti
potenzialmente molto sensibili: messaggi fra persone, foto, documenti,
registrazioni vocali.

La DPIA è **obbligatoria** ai sensi dell'art. 35(1) perché il trattamento è
"sistematico e su larga scala" di dati personali e perché è probabile che
comporti un rischio elevato per i diritti e le libertà delle persone, tenuto
conto che:

- il contenuto delle comunicazioni non è prevedibile né limitabile per
  categorie (art. 35(3)(b));
- il servizio può essere usato da minori in contesti scolastici (art. 8,
  art. 35(3)(c));
- lo strumento consente la sorveglianza permanente e potenziale (art. 35(3)(c):
  messaggistica con stato di presenza, lettura e consegna).

## 2. Descrizione del trattamento

| Aspetto | Valore |
|---|---|
| **Natura** | Raccolta, conservazione, consultazione, condivisione, cancellazione |
| **Finalità** | Erogazione di un servizio di messaggistica su rete locale |
| **Soggetti interessati** | Utenti dell'installazione; in contesti scolastici, anche minori |
| **Dati** | Identificativi, contenuti delle comunicazioni, file, dati vocali, metadati di sessione |
| **Flusso** | App → server locale (MySQL + filesystem) → partecipanti della chat; inoltre app → app via LAN, se il consenso è concesso |
| **Base giuridica** | Contratto (servizio); consenso (facoltativi); obbligo legale (accountability) |
| **Periodo di conservazione** | 30–1825 giorni per tipo di dato (cfr. `ROPA.md`) |
| **Trasferimenti extra SEE** | Nessuno |

## 3. Necessità e proporzionalità

### 3.1 Necessità

Ogni dato trattato è funzionale al servizio? **Sì, con tre eccezioni da
correggere**, individuate in questa valutazione:

| Dato | Valutazione | Esito |
|---|---|---|
| Numero di telefono | Serve come identificativo e per il contatto su rete locale | Proporzionato |
| Email | Facoltativa, non usata per il funzionamento | **Ridondante** → esposta solo su richiesta esplicita dell'utente |
| Destinazione 2FA | Non usata (l'OTP non è implementato) | **Ridondante** → esposta solo all'utente stesso |
| `password_hash` | Necessario | Escluso dall'export per non distribuire materiale di autenticazione |
| IP nel log | Non necessario per il funzionamento | Conservato solo come hash troncato |
| Contenuto delle chat | Cuore del servizio | Necessario, ma con **limite di conservazione** |

### 3.2 Proporzionalità rispetto ai diritti

Le misure adottate sono proporzionate perché non incidono sui dati degli
interessati oltre il necessario: la cifratura è di trasporto, il peer-to-peer
richiede consenso, l'account ospite scade, i diritti sono esercitabili
dall'app senza scrivere al titolare.

## 4. Rischi identificati

Scala: **Impatto** (basso/medio/alto) × **Probabilità** (bassa/media/alta).

### R-01 — Accesso ai dati da parte di un utente non autorizzato

| | |
|---|---|
| **Descrizione** | Un utente autenticato legge o scrive dati di un altro |
| **Impatto** | **Critico** |
| **Probabilità** | **Certificata prima** — il codice precedente accettava `?user_id=` come identità, senza alcuna autenticazione reale; chiunque poteva leggere e scrivere i dati di chiunque altro |
| **Mitigazione** | Token di sessione Bearer opaco, memorizzato solo come SHA-256; l'identità non viaggia nella query string; token assente ⇒ 401 |
| **Verifica** | `webService/tests/run.php` — «un token non può impersonare un altro utente»; `smoke_http.php` — «il parametro ?user_id non autentica più» |
| **Stato** | **Mitigato e verificato** |

### R-02 — Esposizione dei file caricati

| | |
|---|---|
| **Descrizione** | Un file caricato da un utente è leggibile da chiunque |
| **Impatto** | **Critico** |
| **Probabilità** | **Certificata prima** — `serve_file.php` non richiedeva autenticazione e usava `Access-Control-Allow-Origin: *`; inoltre i file erano committati in un repository pubblico |
| **Mitigazione** | `serve_file.php` richiede sessione valida **e** proprietario o partecipante della chat; chiavi di archiviazione casuali; nome originale solo come metadato; `X-Content-Type-Options: nosniff` |
| **Verifica** | `smoke_http.php` — «serve_file senza sessione non consegna il file» |
| **Stato** | **Mitigato e verificato** |

### R-03 — File eseguibili caricati sul server

| | |
|---|---|
| **Descrizione** | Caricamento di uno script eseguibile, poi esecuzione da parte del web server |
| **Impatto** | **Critico** (esecuzione di codice) |
| **Probabilità** | Alta prima dell'intervento: nessun controllo di MIME o estensione, e il MIME era quello dichiarato dal client |
| **Mitigazione** | Verifica del MIME reale via `finfo`; blocklist di estensioni eseguibili; l'estensione è assegnata dal server; coerenza fra estensione dichiarata e contenuto; `.htaccess` come rete di sicurezza aggiuntiva |
| **Verifica** | `tests/run.php` — «un file con estensione eseguibile viene rifiutato», «un'immagine il cui contenuto è codice viene rifiutata» |
| **Stato** | **Mitigato e verificato** |

### R-04 — Intercettazione del traffico

| | |
|---|---|
| **Descrizione** | Un terzo legge o modifica messaggi e token |
| **Impatto** | **Alto** |
| **Probabilità** | **Certificata prima** — `main.dart` installava `badCertificateCallback => true` globalmente: HTTPS non offriva protezione alcuna |
| **Mitigazione** | Rimozione dell'override globale. Per ambienti di laboratorio con certificato autofirmato: installare la CA nel sistema, non disattivare i controlli |
| **Stato** | **Mitigato** |

### R-05 — Credential sul dispositivo

| | |
|---|---|
| **Descrizione** | La password dell'utente è recuperabile da un dispositivo perso o da un backup |
| **Impatto** | **Alto** |
| **Probabilità** | **Certificata prima** — la password era salvata in chiaro in `SharedPreferences` e reinviata a ogni avvio |
| **Mitigazione** | La password non viene più memorizzata; il token vive in `flutter_secure_storage` (Keychain / EncryptedSharedPreferences) |
| **Verifica** | `test/id_validation_test.dart` — «il token viene salvato e la password no» |
| **Stato** | **Mitigato e verificato** |

### R-06 — Conservazione illimitata

| | |
|---|---|
| **Descrizione** | I dati restano per sempre, anche dopo la cessazione del rapporto con il servizio |
| **Impatto** | Medio-alto |
| **Probabilità** | **Certificata prima** — nessuna cancellazione, nessun termine; account ospite non scaduti mai |
| **Mitigazione** | Termini di conservazione configurabili per tipo di risorsa; job di conservazione automatico; account ospite con scadenza a 7 giorni |
| **Verifica** | `tests/run.php` — «i messaggi scaduti vengono eliminati, gli altri restano», «il dry run non modifica nulla» |
| **Stato** | **Mitigato e verificato** |

### R-07 — Dati personali nel repository pubblico

| | |
|---|---|
| **Descrizione** | File caricati da utenti reali committati in un repository pubblico e recuperabili da qualsiasi commit |
| **Impatto** | **Critico** — dati di terzi esposti senza alcun controllo di accesso |
| **Probabilità** | **Certificata** — 11 file reali in `webService/uploads/`, incluse foto e registrazioni |
| **Mitigazione** | `.gitignore` su `uploads/*`; rimozione dall'indice; purga della cronologia (vedi `PROCEDURA-VIOLAZIONE.md`) |
| **Stato** | **Da completare — richiede azione del titolare** |

### R-08 — Uso da parte di minori

| | |
|---|---|
| **Descrizione** | Trattamento di dati di soggetti di età inferiore a 18 anni senza base specifica |
| **Impatto** | Alto |
| **Probabilità** | Alta in contesto scolastico, che è il caso d'uso dichiarato |
| **Mitigazione** | Condizione di esercizio C-1 sotto: il servizio non va offerto a minori finché la sezione 8 dell'informativa non è completata |
| **Stato** | **Da completare — condizione di esercizio** |

### R-09 — Condivisione sulla rete locale senza consenso

| | |
|---|---|
| **Descrizione** | Il dispositivo espone messaggi agli altri host della LAN senza autorizzazione |
| **Impatto** | Alto |
| **Probabilità** | **Certificata prima** — il servizio mDNS si registrava e apriva una porta HTTP su `anyIPv4`; inoltre il mittente dei messaggi era dichiarato nel corpo e accettato senza verifica |
| **Mitigazione** | Il consenso è verificato **sul dispositivo**: senza, nessuna porta aperta, nessuna registrazione mDNS, nessuna ricerca di peer. L'endpoint peer richiede un token Bearer |
| **Stato** | **Mitigato** |

### R-10 — Affermazioni di sicurezza non corrispondenti al reale

| | |
|---|---|
| **Descrizione** | L'utente crede in una protezione che non esiste (cifratura end-to-end dichiarata in un tutorial; il server generava e conservava le chiavi private) |
| **Impatto** | Medio-alto — lede l'utente su un rischio specifico (art. 5(1)(a), trasparenza) |
| **Probabilità** | **Certificata** |
| **Mitigazione** | La generazione delle chiavi lato server è stata rimossa; l'endpoint rifiuta esplicitamente il materiale privato; l'app dichiara il canale come protetto da TLS e non E2EE |
| **Stato** | **Mitigato** |

## 5. Riepilogo del profilo di rischio

| Rischio | Prima | Dopo |
|---|---|---|
| R-01 Accesso non autorizzato | Critico / Certificata | **Residuo basso** |
| R-02 Esposizione file | Critico / Certificata | **Residuo basso** |
| R-03 Esecuzione di codice | Critico / Alta | **Residuo basso** |
| R-04 Intercettazione | Alto / Certificata | **Residuo basso** |
| R-05 Credenziali su dispositivo | Alto / Certificata | **Residuo basso** |
| R-06 Conservazione illimitata | Medio-alto / Certificata | **Residuo basso** |
| R-07 Dati in repository pubblico | Critico / Certificata | **Da completare** |
| R-08 Minori | Alto / Alta | **Da completare** |
| R-09 P2P senza consenso | Alto / Certificata | **Residuo basso** |
| R-10 Affermazioni false | Medio-alto / Certificata | **Residuo basso** |

Rischio residuo accettabile per R-01…R-06 e R-09/R-10, **a condizione** che le
misure tecniche restino in essere: sono esse, non il regolamento, a rendere il
trattamento lecito in pratica.

## 6. Condizioni di esercizio

Il servizio può essere offerto a utenti **solo se** sono soddisfatte tutte e tre:

**C-1 — Minori.** La sezione 8 dell'informativa è completata con titolare,
meccanismo di consenso verificabile e base giuridica. Fino ad allora il
servizio è riservato a soggetti di età ≥ 18 anni.

**C-2 — Identificazione del titolare.** La sezione 1 dell'informativa contiene
un titolare identificabile. Un'informativa priva di titolare non soddisfa
l'art. 13.

**C-3 — Segreti di produzione.** `APP_ENV=production` con `QUICE_APP_SECRET` e
`QUICE_PRIVACY_PEPPER` distinti e casuali, `QUICE_DB_PASSWORD` valorizzata,
`QUICE_ALLOWED_ORIGINS` senza il carattere jolly. In produzione il server si
rifiuta di avviarsi se questi dati mancano.

## 7. Riesame

Riesaminare la DPIA se si verifica almeno una delle seguenti condizioni:

- modifica sostanziale delle finalità o dei meccanismi di cifratura;
- introduzione di cifratura end-to-end reale (chiude R-10 e ne crea uno nuovo
  sulla gestione delle chiavi);
- apertura a minori (chiude R-08, ne crea uno sulla verifica del consenso);
- attivazione della diagnostica (nuovo trattamento in T-06);
- introduzione di più istanze con trasferimento di dati fra titolari diversi.
