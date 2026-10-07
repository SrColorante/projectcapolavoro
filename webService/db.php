<?php
/**
 * Connessione al database condiviso.
 *
 * PostgreSQL dal 7 ottobre 2026: prima era MySQL/MariaDB. Le tre cose che
 * non hanno un equivalente e vengono fatte qui invece che nel codice chiamante:
 *
 * 1. Le credenziali vengono dall'ambiente, non dal file. Il DSN MySQL
 *    hardcodava host, utente e password vuota: chi leggeva il repository
 *    vedeva la topologia del database.
 * 2. Lo schema e' dichiarato in `db-schema/sql/001-schema.sql`, quindi qui non
 *    c'e' piu' nessun CREATE TABLE. Prima c'era un blocco di sei ALTER TABLE
 *    "se non esiste" che girava a ogni richiesta: sei query DDL per ogni
 *    chiamata HTTP, sei andati e ritorni al server a ogni messaggio.
 * 3. Gli indici e i vincoli esistono prima che arrivi il primo utente.
 *
 * Connessione non riuscita = 503 e non un 500 generico: la differenza dice
 * al client se deve ritentare.
 */

// Il separatore è uno spazio perche' i nomi di variabile dentro le stringhe
// doppie verrebbero interpolati.
$dsn = getenv('DATABASE_URL');
if ($dsn === false || $dsn === '') {
    http_response_code(503);
    echo json_encode(["error" => "DATABASE_URL non configurata"]);
    exit;
}

// Neon e Railway distribuiscono la connessione in forma URL
// (`postgresql://utente:password@host:5432/db`), ma pdo_pgsql accetta
// soltanto il DSN classico con prefisso `pgsql:`. Passata cosi' com'e',
// PDO risponde "could not find driver" e il sintomo sembra un driver
// mancante invece di un formato sbagliato.
//
// Qui la si traduce. Se un giorno l'ambiente consegna gia' il formato
// classico, questa funzione lo lascia intatto.
if (!str_starts_with($dsn, 'pgsql:')) {
    $parts = parse_url($dsn);
    if ($parts === false || !isset($parts['host'])) {
        http_response_code(503);
        echo json_encode(["error" => "DATABASE_URL non e' una stringa di connessione PostgreSQL"]);
        exit;
    }
    $dsn = sprintf(
        'pgsql:host=%s;port=%s;dbname=%s',
        $parts['host'],
        $parts['port'] ?? 5432,
        ltrim($parts['path'] ?? '', '/')
    );

    // Le credenziali viaggiano nella parte `utente:password@` della URL e PDO
    // le vuole come argomenti separati, non nel DSN. Vanno decodificate con
    // rawurldecode: gli indirizzi Gmail contengono un '+', che in una URL
    // sta per uno spazio, e senza decodificare la password cambierebbe.
    $db_user = isset($parts['user']) ? rawurldecode($parts['user']) : null;
    $db_pass = isset($parts['pass']) ? rawurldecode($parts['pass']) : null;
} else {
    // DSN gia' classico: le credenziali arrivano da altrove (pgpass, variabili
    // d'ambiente) e PDO puo' procedere senza che gli siano passate.
    $db_user = null;
    $db_pass = null;
}

try {
    $pdo = new PDO($dsn, $db_user, $db_pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        // Reale prepared statement. Con l'emulazione attiva MySQL si
        // sostituisce textualmente i parametri nella stringa, e la firma del
        // client non proteggerebbe nulla: la firma servirebbe a verificare una
        // stringa che il database ha gia' costruito.
        PDO::ATTR_EMULATE_PREPARES => false,
        // Le colonne booleanhe devono arrivare come booleani e non come 't' e
        // 'f': `two_factor_verified` in build_profile() usa isset(), e una
        // stringa 'f' non e' null ma e' anche non vera.
        PDO::ATTR_STRINGIFY_FETCHES => false,
    ]);
} catch (\PDOException $e) {
    http_response_code(503);
    echo json_encode(["error" => "Database non raggiungibile"]);
    exit;
}
