# Procedura di notifica delle violazioni di dati (art. 33 e 34 GDPR)

**Progetto:** Quice
**Versione:** 1.0.0 — 1 ottobre 2026

---

## 1. Cosa conta come violazione

Una **violazione di dati personali** (art. 4(7)) è qualsiasi compromissione
della riservatezza, dell'integrità o della disponibilità dei dati, per
esempio:

- accesso ai dati da parte di chi non ne è autorizzato;
- perdita, distruzione o alterazione dei dati;
- divulgazione dei dati a un destinatario non previsto;
- indisponibilità o perdita dell'accesso al servizio.

Non rientrano fra le violazioni, e non vanno notificate:

- il mancato accesso a un servizio per errore dell'utente;
- l'uso di una password debole scelta dall'utente;
- la mancata installazione di aggiornamenti da parte dell'amministratore
  (**questo, invece, rientra nella notifica a cura del titolare**).

## 2. Tempistiche

| Termine | Base | Scadenza |
|---|---|---|
| Notifica all'autorità di controllo | art. 33(1) | **72 ore** dal momento in cui il titolare ne è venuto a conoscenza |
| Informazione agli interessati | art. 34(1) | **Senza ritardo ingiustificato** |
| Documentazione interna | art. 33(5) | Contestualmente, indipendentemente dalla gravità |

**Il termine di 72 ore decorre dalla conoscenza, non dall'evento.** In
quando si apprende di un fatto avvenuto due giorni prima, il termine residuo
è di 24 ore: non è prorogabile. Se la notifica non è completa entro il
termine, si inviano comunque le informazioni disponibili, integrandole poi a
mezzo di integrazioni successive.

**La notifica non è richiesta se la violazione non è suscettibile di
comportare un rischio per i diritti e le libertà delle persone** (art. 33(3)a).
Nel dubbio, si notifica: il costo di una notifica infondata è molto minore
del costo di una mancata notifica.

## 3. Procedura

### Fase 1 — Rilevazione e contenimento (immediato)

1. **Fermare la perdita.** Se la causa è attiva (endpoint vulnerabile, chiave
   rotata, credenziali in chiaro in un log), mettere in atto il contenimento
   **prima** di indagare a fondo. Il tempo di risposta conta più della
   completezza dell'analisi.
2. **Preservare le prove.** Non riavviare il server, non cancellare log, non
   sovrascrivere i file. Copiare `audit_log`, `error_log` e lo stato del
   filesystem **prima** di qualsiasi operazione di pulizia.
3. **Annotare l'ora esatta della conoscenza del fatto.** È il dies a quo dei
   72 ore. Annotarla in un orologio fidibile, non a posteriori.

### Fase 2 — Accertamento (24–48 ore)

4. **Determinare la natura dei dati coinvolti.** Contentuto dei messaggi,
   file, dati vocali, identificativi? Contenuto delle comunicazioni è la
   categoria più sensibile: lo si dichiara esplicitamente.
5. **Determinare il numero di interessati e di record.** Estrarre i conteggi
   dal database e dal registro di controllo, che per progetto non contiene
   dati in chiaro ma consente la correlazione tramite pseudonimo.
6. **Verificare se l'accesso è stato effettivo**, non solo possibile. Un
   endpoint che non richiedeva autenticazione è un rischio teorico; se nessuna
   richiesta è mai arrivata da una sorgente non identificata, la probabilità
   si riduce.
7. **Misure per contenere e rimediare.** Ruotare le credenziali, revocare i
   token (`POST /privacy {"action":"revoke_session"}` o revoca per utente),
   invalidare la cronologia del repository, rimuovere l'accesso fisico.

### Fase 3 — Valutazione (entro 48 ore)

8. **Decidere se notificar.** Applicare i criteri seguenti e **verbalizzare la
   decisione**, anche quando è negativa: la motivazione va documentata per
   dimostrare che la scelta è stata ragionata e non casuale.
9. **Decidere se informare gli interessati.** Se è probabile un rischio
   elevato, sì. Informare non è un'opzione facoltativa una volta che il rischio
   è elevato.

### Fase 4 — Notifica (entro 72 ore)

10. **Inviare la notifica all'autorità.** Per l'Italia:
    Garante per la protezione dei dati personali
    Piazza Vittorio Emanuele II, 121 — 00186 Roma
    protocollo@gpdp.it — [DA COMPLETARE: canale di trasmissione elettronica
    in uso]
11. **Informare gli interessati** con un messaggio chiaro e diretto.

## 4. Criteri per la decisione di notifica

| Criterio | Valutazione |
|---|---|
| I dati coinvolti sono sensibili? (messaggi, file, dati vocali) | **Sì → rischio elevato, notificare** |
| I dati sono leggibili in chiaro senza competenze particolari? | **Sì → rischio elevato** |
| I dati riguardano minori? | **Sì → rischio elevato** |
| I dati sono pseudonimi ma il peggio per l'interessato si realizza con uno sforzo ragionevole? | **Sì → rischio elevato** |
| I dati sono stati cifrati in modo che solo l'interessato li legga? | **No → rischio ridotto** |
| I dati sono apparsi in un repository pubblico per un tempo breve, prima che l'accesso fosse noto? | **Valutazione caso per caso**; in genere **notificare** se i dati sono sensibili |
| Il titolare ha accettato il rischio residuo documentato nella DPIA? | **Riduce il rischio ma non lo azzera** |

## 5. Modello di notifica

```
A: Garante per la protezione dei dati personali
Oggetto: Notifica di violazione di dati personali ai sensi dell'art. 33 GDPR

1. Titolare del trattamento
   [nome, indirizzo, contatti]

2. Dati della violazione
   - Data e ora (UTC) del fatto:
   - Data e ora (UTC) in cui il titolare ne è venuto a conoscenza:
   - Luogo:
   - Descrizione:
   - Numero di interessati coinvolti (stima):

3. Categorie e volumi dei dati
   - Categorie di interessati:
   - Tipi di dati personali coinvolti:

4. Contatti del referente
   - Responsabile della notifica:
   - Recapiti:

5. Descrizione delle possibili conseguenze
   [perdita di riservatezza del contenuto delle comunicazioni, uso improprio
   di immagini o documenti, possibile impersonamento]

6. Misure adottate o proposte per mitigare
   - Contenimento:
   - Remediation:
   - Misure preventive:

7. Misure per informare gli interessati
   [testo del messaggio, canale utilizzato, data]

Firma del titolare del trattamento
```

## 6. Modello di informazione agli interessati

> **Oggetto: Notifica ai sensi dell'art. 34 GDPR**
>
> Il [data] abbiamo rilevato un problema che ha consentito a [chi] di
> [accesso non autorizzato / leggere] per [durata] i seguenti dati
> relativi al suo account: [elenco].
>
> Abbiamo già [misure di contenimento].
>
> I dati interessati sono [elenco]. Le possibili conseguenze sono [elenco].
>
> Può adottare le seguenti misure: [azioni concrete richieste all'utente].
>
> Per qualsiasi domanda: [recapito].
>
> Titolare del trattamento: [identificativo]

Regole di scrittura: senza minimizzare l'accaduto e senza allarmismo
inutili; indicare fatti, non formule. Se l'utente ha già agito in proprio
conoscendo il fatto, non omettere la notifica solo perché "è già informato":
potrebbe non esserlo.

## 7. Incidenti già occorsi in questo progetto

### V-01 — Dati personali in repository pubblico

| Campo | Valore |
|---|---|
| **Descrizione** | `webService/uploads/` conteneva 11 file caricati da utenti reali (immagini, registrazioni vocali, un brano audio, un file di codice), tracciati in git in un repository **pubblico** |
| **Impatto** | Rischio elevato: dati di comunicazioni, potenzialmente riconducibili a terzi, scaricabili da chiunque |
| **Rilevato** | 30 settembre 2026 |
| **Dati coinvolti** | Contenuto di file; potenzialmente immagini di persone riconoscibili |
| **Contenimento** | `.gitignore` su `uploads/*`; rimozione dall'indice; `docs/LEGAL/PROCEDURA-VIOLAZIONE.md` come guida alla purga della cronologia |
| **Rimediation** | Purga della cronologia Git con `git filter-repo`; revoca di ogni URL ngrok o pubblico usato per le prove |
| **Preventivo** | Template `.gitignore` presente; verifica pre-commit; il `.htaccess` di `uploads/` non è più necessario come unica difesa, perché la validazione è ora nel codice |
| **Stato** | **Contenuto; purga della cronologia richiede l'azione del titolare** |

**Valutazione della notifica.** Il caso ricade nella categoria «dati sensibili
esposti pubblicamente». La raccomandazione è di **notificare** (art. 33) e
**informare gli interessati** (art. 34) se i file contengono dati di persone
riconoscibili. La decisione finale spetta al titolare, che deve valutare
l'effettiva sensibilità del contenuto — **e non può demandarla**: il fatto che
i file fossero "solo di prova" non esclude che siano dati reali.

### V-02 — Impersonazione possibile senza autenticazione

| Campo | Valore |
|---|---|
| **Descrizione** | L'identità dell'utente era letta dalla query string (`?user_id=`) e l'unica protezione era una firma HMAC con segreto unico presente nel repository pubblico: chiunque poteva leggere e scrivere i dati di qualunque utente |
| **Impatto** | Critico |
| **Rilevato** | 30 settembre 2026, prima di qualsiasi messa in produzione |
| **Persone coinvolte** | Utenti di eventuali installazioni di prova |
| **Contenimento** | Autenticazione a token; rimozione dell'identità dalla query string; secret di produzione obbligatorio |
| **Preventivo** | `tests/run.php` e `smoke_http.php` coprono il caso specifico e falliscono se la regressione torna |
| **Stato** | **Risolto** |

**Valutazione della notifica.** Se il sistema è stato usato solo con dati di
prova e nessun accesso non autorizzato risulta dal registro, la notifica
all'autorità è verosimilmente non dovuta (art. 33(3)a, assenza di rischio). Lo
è invece dovuta **se esistono dati reali** di persone che hanno usato
un'installazione raggiungibile via rete.
