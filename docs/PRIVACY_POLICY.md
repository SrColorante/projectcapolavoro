# Privacy policy — Quice

Testo mostrato nell'app e di riferimento per l'installazione. La versione
incorporata nell'app è `flutterapp/assets/legal/privacy_policy.txt`; la
versione completa da distribuire ai titolari è
`flutterapp/assets/legal/privacy_policy.txt`.

**Versione:** 1.0.0 — 1 ottobre 2026

---

## Sintesi per l'utente

> **Chi tratta i tuoi dati:** il titolare dell'installazione di Quice che
> stai usando. Nel repository pubblico questo non è identificato: prima di
> usare il servizio, chi lo gestisce deve compilare i dati nella sezione 1
> dell'informativa.
>
> **Quali dati:** il tuo numero di telefono (10 cifre), nome, eventuale email,
> i messaggi che invii e ricevi, i file che condividi, e — se lo attivi — la
> tua bio vocale.
>
> **Perché:** per farti usare la messaggistica. È la base del servizio: se non
> lo facciamo, non possiamo offrirtelo.
>
> **Cosa NON facciamo:** non vendiamo i tuoi dati, non li passiamo a servizi
> pubblicitari o di analytics, non usiamo la messaggistica di terzi. Il
> traffico resta sulla rete su cui è installato il server.
>
> **Cifratura:** le comunicazioni viaggiano su canale cifrato (HTTPS), ma
> **non** sono cifrate end-to-end: il server le legge per inoltrarle. Questo
> punto è dichiarato anche nell'app, perché dirlo solo nella documentazione
> sarebbe più comodo ma meno onesto.
>
> **Per quanto tempo:** i messaggi un anno, i file sei mesi, le sessioni un
> mese, il registro delle attività due anni. Puoi vedere e cambiare questi
> termini in *Impostazioni → Privacy e dati*.
>
> **I tuoi diritti, tutti senza scrivere a nessuno:** in *Impostazioni → Privacy
> e dati* puoi scaricare tutto quello che riguarda te, rettificarlo, limitare
> il trattamento, revocare i consensi che hai dato, chiudere le sessioni
> aperte e cancellare il tuo account.
>
> **Attenzione:** cancellare l'account elimina messaggi e file. Non rimuove i
> messaggi che altri hanno nella loro copia, perché non possiamo farlo senza
> ledere un loro diritto. È un limite del servizio, dichiarato per non creare
> aspettative false.

---

## Perché l'app non promette la cifratura end-to-end

Una versione precedente di questa interfaccia mostrava un tutorial che
annunciava la cifratura end-to-end. Non era vero: le coppie di chiavi venivano
generate **sul server** e la chiave privata veniva restituita al client
nell'API. Un sistema in cui il server conosce la chiave privata non è un
sistema end-to-end.

È stato preferito rimuovere la promessa piuttosto che mantenerla: un utente
che crede ai messaggi cifrati end-to-end condivide informazioni che non
condividerebbe, e il danno nasce proprio dalla fiducia riposta in una
dichiarazione falsa.

Le chiavi pubbliche possono essere pubblicate dall'utente e sono conservate,
in attesa che il client implementi il cifrario. Nel frattempo l'app lo dice
esplicitamente.

---

## Perché la cancellazione ha un periodo di attesa

Cancelling un account è irreversibile. Se avviene per errore, o sotto
pressione, o perché qualcun altro ha accesso al dispositivo, la perdita è
definitiva.

Per questo la richiesta non cancella subito: congela l'account e lascia un
periodo di attesa durante il quale la richiesta si può annullare. Al termine,
un processo automatico esegue la cancellazione completa.

La finestra è di 30 giorni e si configura con `QUICE_ERASURE_GRACE_DAYS`.

---

## Perché le prove di consenso sopravvivono alla cancellazione

Dopo che hai eliminato l'account, restano alcune righe che registrano che avevi
concesso determinati consensi. Non contengono nulla che ti riguardi in modo
riconoscibile: sono uno pseudonimo irreversibile e il tipo di decisione.

Senza quelle righe, in caso di controllo, non sarebbe possibile dimostrare che
il trattamento era autorizzato. L'art. 17(3)(b) prevede esattamente questa
eccezione.

---

## Come leggere il resto della documentazione

| Documento | A chi serve | Contenuto |
|---|---|---|
| `docs/LEGAL/ROPA.md` | Titolare, DPO | Registro delle attività di trattamento (art. 30) |
| `docs/LEGAL/DPIA.md` | Titolare, DPO | Valutazione d'impatto (art. 35), rischi e condizioni di esercizio |
| `docs/LEGAL/PROCEDURA-VIOLAZIONE.md` | Titolare, amministratore | Gestione delle violazioni (art. 33, 34), modelli pronti |
| `docs/LEGAL/MATRICE-DATI.md` | Sviluppatore | Matrice dato → base giuridica → consenso → conservazione |
| `docs/LEGAL/PURGA-GIT.md` | Amministratore | Rimozione dei dati personali dalla cronologia |
| `webService/docs/SICUREZZA.md` | Sviluppatore, amministratore | Misure tecniche di sicurezza (art. 32) |
