# Purga dei dati personali dalla cronologia Git

## Il problema

Il repository contiene **11 file caricati da utenti reali** in
`webService/uploads/`: immagini, registrazioni vocali, un brano audio, un file
di codice Arduino. Sono tracciati in git e il repository è **pubblico**.

Sono quindi scaricabili da chiunque, da qualunque clone, a prescindere da
qualsiasi configurazione del server.

Rimuoverli dal branch corrente **non basta**: restano nei commit passati, e
finché il repository è pubblico sono recuperabili.

## Cosa è già stato fatto (in questo intervento)

- `webService/uploads/*` aggiunto a `.gitignore` (con eccezione per
  `.htaccess` e `.gitkeep`);
- file rimossi dall'indice;
- `webService/serve_file.php` non consente più l'accesso anonimo, quindi
  anche senza purga della cronologia i file non sono più scaricabili
  dall'istanza in esercizio.

Queste due misure **non eliminano** l'esposizione storica. Serve la procedura
qui sotto.

## Procedura

> **Avvertenza.** La riscrittura della cronologia modifica tutti gli hash dei
> commit. Chiunque abbia già clonato il repository dovrà ri-clonarlo. È
> irreversibile per quanto riguarda la cronologia originale.

### 1. Fare un backup sicuro prima di iniziare

```bash
cd /percorso/del/repository
git clone --mirror . /tmp/quice-backup-$(date +%Y%m%d).git
```

Il backup contiene i dati personali: **non conservarlo a lungo**, e non
copiarlo su supporti non cifrati.

### 2. Installare `git-filter-repo`

```bash
pip install git-filter-repo
```

### 3. Purga

Dalla radice del repository:

```bash
cd /percorso/del/repository

git filter-repo \
  --path webService/uploads \
  --invert-paths \
  --force
```

Questo rimuove dall'intera cronologia tutti i file sotto
`webService/uploads/`.

**Da fare sempre, anche senza i file personali:** il repository contiene
credenziali di database e un segreto di firma in chiaro.

```bash
# Sostituisci i valori con quelli reali da rimuovere
git filter-repo \
  --replace-text <(printf '%s\n' \
    '==>QUICE_DB_PASSWORD==>***REMOVED***' \
    '==>crimson-chat-signing-secret-2026-v1-please-rotate==>***REMOVED***') \
  --force
```

> `git filter-repo` non si può eseguire due volte sullo stesso repository
> senza `--force`: il secondo passaggio sostituisce anche i file già
> rimossi, il che è ciò che si vuole per i segreti.

### 4. Verificare prima di pubblicare

```bash
# Non deve restare traccia dei file personali
git log --all --full-history -- webService/uploads/ | head

# Controllo dei segreti nella cronologia risultante
git log --all -p -S 'crimson-chat-signing-secret' | head
git log --all -p -S 'password' -- webService/ | head -40
```

### 5. Invalidare le cache remote

**Questa parte è quella che si dimentica, ed è la più importante.**

GitHub conserva gli oggetti dei commit cancellati in cache e li rende
raggiungibili per una finestra di tempo. Un clone del repository non basta
per garantire che i dati non siano più recuperabili.

```bash
# 1. Contattare il supporto GitHub per la rimozione dalla cache
#    https://support.github.com/contact
#    Richiedere esplicitamente la rimozione dei dati dagli oggetti git
#    e dai "release assets".
#
# 2. Dopo l'attesa prevista (tipicamente 24-48 ore dalla richiesta),
#    verificare che un clone non contenga più i file:
git clone https://github.com/SrColorante/projectcapolavoro.git /tmp/verifica
find /tmp/verifica -name 'file_6a*' -o -name 'bio_voice*' -o -name 'Old_Money*'
# Il comando non deve restituire nulla.

rm -rf /tmp/verifica
```

### 6. Pubblicare

```bash
git remote add origin2 https://github.com/SrColorante/projectcapolavoro.git
git push --force-with-lease origin2 main
```

Usare `--force-with-lease` e non `--force`: se nel frattempo qualcun altro ha
pubblicato, il push viene rifiutato invece di sovrascrivere il lavoro altrui.

### 7. Ruotare ogni segreto esposto

Anche se la cronologia è pulita, **i segreti devono essere considerati
compromessi**: erano pubblici.

- `QUICE_APP_SECRET` — nuovo valore con `openssl rand -hex 32`
- `QUICE_PRIVACY_PEPPER` — **nuovo valore, diverso dal precedente**. Ruotarlo
  cambia tutti gli pseudonimi già memorizzati: i log storici non saranno più
  correlabili con gli utenti. È il comportamento corretto, ma va messo in
  conto.
- Password del database MySQL — nuova
- Qualsiasi URL ngrok o servizio pubblico usato durante le prove:
  **revocarlo**, non basta cambiare l'applicazione.

## Cosa fare per non ripeterlo

- [ ] `webService/uploads/*` è già in `.gitignore` ✓
- [ ] Nessun file `.env` tracciato ✓ (`.gitignore` in `webService/`)
- [ ] Installare un hook pre-commit:

```bash
# .git/hooks/pre-commit
#!/bin/sh
# Blocca l'aggiunta di file binari fuori dalle directory ammette.
if git diff --cached --name-only --diff-filter=ACM | \
   grep -qE '^(webService/uploads/|.*\.env$)'; then
  echo "Rifiuto: file di dati personali o segreti nell'indice."
  exit 1
fi
```

- [ ] Verificare con `git log --all -- '*.jpg' '*.m4a' '*.mp3'` che non ci
      siano file multimediali nella cronologia.

## Obbligo di notifica

La pubblicazione di dati personali in un repository accessibile a terzi è una
violazione ai sensi dell'art. 4(7) del GDPR. La procedura di valutazione e
notifica è in [`PROCEDURA-VIOLAZIONE.md`](PROCEDURA-VIOLAZIONE.md), sezione
V-01.

**La decisione di notificare spetta al titolare e va verbalizzata**, con la
motivazione: il fatto che i file fossero caricati "solo per una prova" non
esclude che contenessero dati personali reali, e non annulla l'obbligo di
valutare.
