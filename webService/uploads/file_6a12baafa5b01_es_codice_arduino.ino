#include <LiquidCrystal.h>

#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <SoftwareSerial.h>

// ============================================================
// 1. CONFIGURAZIONE HARDWARE (PIN E BUS)
// ============================================================
#define RS485_RX    2      // Ricezione dati dal MAX485
#define RS485_TX    3      // Trasmissione dati verso MAX485
#define CTRL_PIN    12     // Pin DE/RE: HIGH per trasmettere, LOW per ricevere
#define MY_ADDR     0x01   // Indirizzo univoco di questa scheda (ID locale)

SoftwareSerial rs485(RS485_RX, RS485_TX);
LiquidCrystal_I2C lcd(0x27, 16, 2);

// Pin Pulsanti (collegati a GND, usano pull-up interno)
int up = 4; int down = 9; int select = 8; int enter = 7;

// ============================================================
// 2. VARIABILI DI STATO (MACCHINA A STATI)
// ============================================================
int paginaCorrente = 0;   // Gestisce il menu: 0=Menu, 1=Master, 2=Slave
int cursore = 0;          // Riga evidenziata nel menu principale
bool evidenziato = false; // Conferma visiva prima di entrare in una pagina

// Variabili per la creazione del pacchetto dati (Master)
int masterAddr = 1;       // Indirizzo del destinatario da configurare
int masterVal = 0;        // Valore (0 o 1) da inviare
int masterStep = 0;       // Sotto-stati Master: 0=Addr, 1=Val, 2=Invio

void setup() {
  Serial.begin(9600);     // Seriale per monitoraggio da PC
  rs485.begin(9600);      // Velocità bus RS485
  
  lcd.init();
  lcd.backlight();
  
  // Configurazione Ingressi/Uscite
  pinMode(up, INPUT_PULLUP); pinMode(down, INPUT_PULLUP);
  pinMode(select, INPUT_PULLUP); pinMode(enter, INPUT_PULLUP);
  pinMode(CTRL_PIN, OUTPUT);
  pinMode(13, OUTPUT);    // LED di sistema per feedback visivo

  digitalWrite(CTRL_PIN, LOW); // Partiamo sempre in modalità ASCOLTO
  aggiornaDisplay();           // Disegna la schermata iniziale
}

void loop() {
  // Lo switch logico: esegue la funzione corretta in base alla pagina attiva
  if (paginaCorrente == 0)      gestisciMenuPrincipale();
  else if (paginaCorrente == 1) gestisciPaginaMaster();
  else if (paginaCorrente == 2) gestisciPaginaSlave();
}

// ============================================================
// 3. LOGICA DI NAVIGAZIONE (MENU PRINCIPALE)
// ============================================================
void gestisciMenuPrincipale() {
  if (digitalRead(up) == LOW) { // Sposta cursore su
    if (cursore > 0) { cursore--; evidenziato = false; aggiornaDisplay(); delay(250); }
  }
  if (digitalRead(down) == LOW) { // Sposta cursore giù
    if (cursore < 1) { cursore++; evidenziato = false; aggiornaDisplay(); delay(250); }
  }
  if (digitalRead(select) == LOW) { // Seleziona graficamente la voce
    evidenziato = true; aggiornaDisplay(); delay(250);
  }
  if (digitalRead(enter) == LOW && evidenziato) { // Conferma ed entra
    paginaCorrente = cursore + 1;
    masterStep = 0; 
    lcd.clear(); aggiornaDisplay(); delay(250);
  }
}

// ============================================================
// 4. LOGICA TRASMISSIONE (PAGINA MASTER)
// ============================================================
void gestisciPaginaMaster() {
  // Cicla tra i parametri da impostare (Indirizzo -> Valore -> Invio)
  if (digitalRead(select) == LOW) {
    masterStep++;
    if (masterStep > 2) masterStep = 0;
    aggiornaDisplay(); delay(250);
  }

  if (masterStep == 0) { // Impostazione Indirizzo (1-255)
    if (digitalRead(up) == LOW) { masterAddr++; if(masterAddr > 255) masterAddr = 1; aggiornaDisplay(); delay(150); }
    if (digitalRead(down) == LOW) { masterAddr--; if(masterAddr < 1) masterAddr = 255; aggiornaDisplay(); delay(150); }
  } 
  else if (masterStep == 1) { // Impostazione Valore (Inverte 0/1)
    if (digitalRead(up) == LOW || digitalRead(down) == LOW) { masterVal = !masterVal; aggiornaDisplay(); delay(250); }
  } 
  else if (masterStep == 2) { // Esecuzione Invio
    if (digitalRead(enter) == LOW) {
      inviaDatiRS485(masterAddr, masterVal);
      paginaCorrente = 0; // Torna al menu principale dopo la spedizione
      aggiornaDisplay(); delay(500);
    }
  }
}

void inviaDatiRS485(byte addr, byte val) {
  lcd.setCursor(0, 1); lcd.print("INVIO IN CORSO..");
  digitalWrite(CTRL_PIN, HIGH); // Commuta il chip MAX485 in TRASMISSIONE
  delay(10); 
  
  // Protocollo a 4 byte: [Header, Header, Indirizzo, Valore]
  byte pacchetto[4] = {0x00, 0x00, addr, val};
  rs485.write(pacchetto, 4);
  
  rs485.flush(); // Aspetta che i bit escano fisicamente dal cavo
  digitalWrite(CTRL_PIN, LOW); // Ritorna immediatamente in ASCOLTO
  delay(500);
}

// ============================================================
// 5. LOGICA RICEZIONE (PAGINA SLAVE)
// ============================================================
void gestisciPaginaSlave() {
  if (digitalRead(select) == LOW) { paginaCorrente = 0; aggiornaDisplay(); delay(250); }

  // Se arrivano almeno 4 byte (lunghezza del nostro pacchetto)
  if (rs485.available() >= 4) {
    // Sincronizzazione: cerchiamo i due byte di header 0x00 0x00
    if (rs485.read() == 0x00 && rs485.read() == 0x00) {
      byte targetAddr = rs485.read(); // Legge chi dovrebbe ricevere il messaggio
      byte val = rs485.read();        // Legge il dato (0 o 1)

      lcd.setCursor(0, 1);
      
      // LOGICA DI INDIRIZZAMENTO:
      if (targetAddr == MY_ADDR) {
        // Il messaggio è destinato a questa scheda
        lcd.print("PER ME! Val: "); lcd.print(val);
        digitalWrite(13, val); 
      } 
      else {
        // Il messaggio è per un altro dispositivo sul bus
        lcd.print("PER: "); lcd.print(targetAddr);
        lcd.print(" Val: "); lcd.print(val);
      }
      lcd.print("      "); // Pulizia riga per evitare scritte sovrapposte
    }
  }
}

// ============================================================
// 6. GESTIONE INTERFACCIA LCD
// ============================================================
void aggiornaDisplay() {
  lcd.setCursor(0, 0);
  if (paginaCorrente == 0) { // MENU PRINCIPALE
    lcd.clear();
    lcd.setCursor(0, 0); lcd.print(cursore == 0 && evidenziato ? "> [MASTER]" : (cursore == 0 ? "> Master" : "  Master"));
    lcd.setCursor(0, 1); lcd.print(cursore == 1 && evidenziato ? "> [SLAVE]" : (cursore == 1 ? "> Slave" : "  Slave"));
  } 
  else if (paginaCorrente == 1) { // SCHERMATA MASTER
    lcd.clear();
    lcd.print("M: ");
    if(masterStep == 0) lcd.print(">ADDR "); else lcd.print("ADDR ");
    if(masterStep == 1) lcd.print(">VAL"); else lcd.print("VAL");
    lcd.setCursor(0, 1);
    if(masterStep == 2) lcd.print("PRESS ENTER TO SEND");
    else { lcd.print("A:"); lcd.print(masterAddr); lcd.print(" V:"); lcd.print(masterVal == 1 ? "ON" : "OFF"); }
  } 
  else if (paginaCorrente == 2) { // SCHERMATA SLAVE
    lcd.clear();
    lcd.print("ASCOLTO (MIO:"); lcd.print(MY_ADDR); lcd.print(")");
    lcd.setCursor(0, 1); lcd.print("In attesa...");
  }
}
