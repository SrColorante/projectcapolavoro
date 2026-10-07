<?php
/**
 * Valori per le colonne BOOLEAN.
 *
 * PDO lega `false` come la stringa vuota, e `''` non è un boolean valido per
 * pdo_pgsql: la richiesta viene rifiutata con
 * `invalid input syntax for type boolean: ""`. Non è un problema della colonna,
 * è di come PHP passa i valori allo statement.
 *
 * Il caso non è teorico. `false` è il valore normale di quasi tutti questi
 * campi: un messaggio non certificato, un file che non aggira il limite, una
 * registrazione senza 2FA. Con il binding diretto quelle operazioni — cioè le
 * più comuni — fallirebbero ogni volta.
 *
 * PostgreSQL accetta più forme testuali di un boolean: `TRUE`, `'true'`, `'t'`,
 * `'1'`, `'yes'`, `'on'` per vero, e i corrispondenti per falso. Qui si sceglie
 * `'t'` e `'f'` perché sono le forme che `psql` stampa e che appaiono in un
 * dump: leggere una tabella a mano restituisce esattamente queste due lettere.
 */

/**
 * Booleano come stringa per un placeholder `?`.
 *
 * Serve `false` → `'f'`, perché `false` → `''` e Postgres lo rifiuta.
 */
function sql_bool($value): string {
    return $value ? 't' : 'f';
}

/**
 * Booleano come letterale SQL, per le query che non usano placeholder.
 *
 * Si scrive `is_group = TRUE` invece di `= 1` in un INSERT: con un placeholder
 * il valore passa come stringa e `'1'` va bene, ma scritto a mano `1` su una
 * colonna BOOLEAN è un errore di tipo che fallisce solo al runtime.
 */
function sql_bool_literal(bool $value): string {
    return $value ? 'TRUE' : 'FALSE';
}
