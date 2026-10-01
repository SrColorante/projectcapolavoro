# Matrice dati → base giuridica → consenso → conservazione

Riepilogo operativo. Per il registro completo vedi [`ROPA.md`](ROPA.md);
per la valutazione del rischio vedi [`DPIA.md`](DPIA.md).

## Matrice

| Dato | Dove sta | Base giuridica | Consenso? | Conservazione | Come si cancella |
|---|---|---|---|---|---|
| Numero di telefono | `utenti.IDutente` | Art. 6(1)(b) | No | Finché l'account esiste | Cancellazione account |
| Nome, nickname | `utenti.nome`, `.nickname` | Art. 6(1)(b) | No | Finché l'account esiste | Cancellazione account |
| Email | `utenti.email` | Art. 6(1)(b) | No | Finché l'account esiste | Cancellazione account |
| Hash password | `utenti.password_hash` | Art. 6(1)(b) | No | Finché l'account esiste | Cancellazione account |
| Token di sessione | `utenti_sessioni.token_hash` | Art. 6(1)(b) | No | 30 giorni | Revoca / scadenza |
| Etichetta dispositivo | `utenti_sessioni.device_label` | Art. 6(1)(b) | No | 30 giorni | Revoca |
| Testo dei messaggi | `messaggi.textmessage` | Art. 6(1)(b) | No | 365 giorni | Cancellazione messaggio o account |
| Orario e stato di lettura | `messaggi.timenow`, `.status` | Art. 6(1)(b) | No | 365 giorni | Con il messaggio |
| **Testo tradotto** | Solo sul dispositivo | Art. 6(1)(a) | **Sì** | Non salvato sul server | Interruttore in Privacy |
| **File scambiati via LAN** | Coda locale del destinatario | Art. 6(1)(a) | **Sì** | Sincronizzata al server | Revoca consenso + eliminazione |
| File allegati | `shared_files`, `uploads/` | Art. 6(1)(b) | No | 180 giorni | Cancellazione file / messaggio / account |
| **Bio vocale** | `shared_files`, `profile_audio_url` | Art. 6(1)(a) | **Sì, specifico** | 180 giorni | Rimozione dal profilo |
| Consenso LAN | Registro locale + `consensi` | Art. 6(1)(a) | **Sì** | 1825 giorni | Revoca |
| Prove di consenso | `consensi` | Art. 6(1)(c) | — | 1825 giorni | **Non si cancellano** (art. 17(3)(b)) |
| Log di controllo | `audit_log` (pseudonimo) | Art. 6(1)(c) | — | 730 giorni | Automatico |
| Hash IP | `audit_log.ip_hash`, `consensi.ip_hash` | Art. 6(1)(c) | — | Con il log | Automatico |
| IP in chiaro | Mai conservato | — | — | — | — |

## Richieste di rete senza consenso

Il consenso non copre i collegamenti di rete effettuati dall'app:

| Azione | Quando avviene |
|---|---|
| Chiamate API al server | Sessione attiva (token) |
| Risoluzione mDNS | **Solo con consenso LAN** |
| Apertura porta per P2P | **Solo con consenso LAN** |
| Traduzione ML Kit | **Solo con consenso traduzione** |
| Notifiche push locali | Sempre (nessuna trasmissione) |

## Esportazione (art. 15 e 20)

Un solo endpoint: `GET /privacy/export` (richiede sessione).

**Contiene:** profilo, conversazioni, messaggi, file, sessioni, consensi,
registro di controllo, termini di conservazione.

**Non contiene:** hash delle password, hash dei token, chiavi di sessione,
scelte del titolare del trattamento.

Formato: JSON leggibile da macchina (`quice-export/1.0`), quindi valido anche
per la portabilità di cui all'art. 20.

## Cancellazione (art. 17)

`POST /privacy {"action":"request_erasure","confirmation":"ELIMINA"}`

1. Le sessioni vengono revocate subito.
2. L'account è congelato: nuove sessioni bloccate.
3. Alla scadenza (default 30 giorni) `php webService/migrate.php purge` esegue
   la cancellazione definitiva.
4. Nel frattempo `POST /privacy {"action":"cancel_erasure"}` annulla.

**Cosa viene eliminato:** profilo, messaggi inviati e ricevuti, chat di gruppo
lasciate senza membri, file su disco e relative righe, sessioni, codici 2FA,
stato di presenza, appartenenza ai gruppi.

**Cosa sopravvive, e perché:**

| Cosa | Motivo |
|---|---|
| Prove di consenso (pseudonime) | Art. 17(3)(b) — dimostrare la liceità del trattamento |
| Registro di controllo (pseudonimo, senza IP) | Art. 17(3)(e) e art. 5(2) — responsabilità e dimostrabilità |
| Chat contenenti messaggi di terzi | Art. 17(2) — non si lede il diritto altrui alla cancellazione |

## Come esercitare i diritti senza scrivere al titolare

| Diritto | Dove nell'app |
|---|---|
| Accesso e portabilità (15, 20) | Privacy e dati → *Scarica tutti i miei dati* |
| Rottazione (16) | Sezione profilo |
| Limitazione (18) | Privacy e dati → *Limita il trattamento* |
| Cancellazione (17) | Privacy e dati → *Elimina il mio account* |
| Opposizione e ritiro (21, 7(3)) | Privacy e dati → interruttori per trattamento |
| Revoca sessioni | Privacy e dati → *Sessioni attive* |
| Reclamo | I dati del titolare, da completare in `PRIVACY_POLICY.md` |
