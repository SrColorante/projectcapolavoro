# Piano di implementazione — Crimson Chat (Flutter + PHP)
## Panoramica
L’utente richiede 9 macro-funziomalità. Il lavoro è articolato e tocca **database MySQL**, **backend PHP**, **app Flutter** (modelli, API, UI, servizi). Il piano è suddiviso in **7 milestone sequenziali**, ognuna testabile in modo indipendente.
---
## Stato attuale riassunto
- **DB (`chat.sql`)**: 5 tabelle. `chat` è solo 1-to-1. `messaggi` ha solo `senderID`/`reciverID`, nessun FK a `chat`. `shared_files` esiste ma non è collegato ai messaggi. `utenti` ha già `profile_bio`, `profile_photo_url`, `profile_audio_url`, `profile_audio_duration_seconds`.
- **Backend PHP**: RESTful router in `index.php`. Risorse: `auth`, `chats`, `chat`, `settings`, `security`, `files`. Nessun supporto gruppi. `files.php` registra solo metadati (no upload binario).
- **Flutter**: `AuthScreen` base con Material 3. `HomeScreen` split-pane. `ChatApi` statico. No notifiche locali. No file picker. No preview media.
---
## Milestone 1 — Database & Backend: gruppi, file nei messaggi, profilo completo
### 1.1 Schema DB (nuovo file `chat_migrations_v2.sql`)
- **`chat`**: aggiungere `is_group TINYINT(1) DEFAULT 0`, `name VARCHAR(100)`, `created_by BIGINT UNSIGNED`, `avatar_url VARCHAR(500) NULL`.
- **Nuova `chat_members`**: `chat_id`, `user_id`, `joined_at`, `role ENUM('admin','member') DEFAULT 'member'`.
- **`messaggi`**: aggiungere `chat_id BIGINT UNSIGNED NULL` (FK a `chat`). Aggiungere `file_attachment_id BIGINT UNSIGNED NULL` (FK a `shared_files`). Rimuovere il vincolo `NOT NULL` su `reciverID` (nei gruppi il destinatario è implicito via `chat_id`).
- **`shared_files`**: aggiungere `message_id BIGINT UNSIGNED NULL` per legare il file al messaggio.
- **`chat_settings_per_device`** (tabella opzionale, oppure gestita lato client con SharedPreferences): l’utente vuole personalizzazione *per dispositivo*, quindi la teniamo lato Flutter (Hive/SharedPreferences) per semplicità e performance.
### 1.2 Backend PHP
- **`resources/chats.php`**: supportare `POST` con `is_group=1`, `name`, `member_ids[]`. Creare chat + righe in `chat_members`.
- **`resources/chat.php`**: 
  - `GET`: se `chat_id` è un gruppo, restituire tutti i messaggi con quella `chat_id`.
  - `POST`: accettare `chat_id` (obbligatorio per gruppi). Se presente, usare `chat_id` invece di `reciverID`. Supportare `file_attachment_id` opzionale.
- **`resources/files.php`**: 
  - `POST`: accettare `message_id` opzionale per legare il file al messaggio subito dopo l’invio.
  - Aggiungere endpoint `POST /files/upload` che accetti multipart/form-data, salvi il file su disco (`uploads/`) e ritorni `source_url`.
- **`resources/settings.php`**: `GET`/`POST`/`PATCH` devono già restituire/accettare `profile_bio`, `profile_photo_url`, `profile_audio_url`, `profile_audio_duration_seconds` (già presenti nel DB ma da verificare che il PHP li esponga tutti correttamente).
---
## Milestone 2 — Login modernizzato + errori grafici
### 2.1 `auth_screen.dart`
- Nuovo design con **sfondo gradiente**, **hero animation** sul logo, **card glassmorphism** o Material 3 elevato.
- Campi con `TextFormField` + `InputDecoration` moderna (filled, rounded, icone animate).
- Toggle login/registrazione con `AnimatedSwitcher` o `PageTransitionSwitcher`.
- Pulsante "Continua come ospite" stile outlined con icona.
- Supporto dark/light mode responsive.
### 2.2 Errori grafici sulle richieste
- Creare `ApiExceptionHandler` che mostri:
  - **Snackbar** con `SnackBar` + `SnackBarAction` per retry.
  - **Banner** rosso in cima allo schermo per errori 4xx/5xx.
  - **Shimmer placeholder** durante il loading.
- Wrappare tutte le chiamate `AuthApi` e `ChatApi` con `try/catch` che usino questo handler.
---
## Milestone 3 — File sharing + Preview nei messaggi
### 3.1 Selezione file
- Aggiungere `file_picker` a `pubspec.yaml`.
- In `_ChatPanel` aggiungere icona 📎 che apre `FilePicker.platform.pickFiles()`.
- Supportare qualsiasi tipo MIME.
### 3.2 Upload
- Se il file è > 50 MB e l’utente è admin, passare `override_limit`.
- Usare `MultipartRequest` per upload reale (non solo metadata).
- Dopo l’upload, inviare il messaggio con `file_attachment_id`.
### 3.3 Preview nei messaggi
Creare widget `MessageAttachmentPreview` che, in base al `preview_type` / MIME:
- **Audio**: `audioplayers` mini-player con waveform mockup + play/pause.
- **Video**: `video_player` thumbnail + pulsante play in overlay.
- **Immagine / GIF**: `Image.network` / `CachedNetworkImage` con lightbox su tap.
- **Documento (PDF, DOC, ecc.)**: card con icona tipo file + nome + tasto "Apri".
- **Codice**: `flutter_highlight` o semplicemente `SelectableText` in `Container` con sfondo scuro e font monospace.
- **Link / Sito**: `flutter_link_preview` (o fetch OpenGraph server-side) che mostra titolo, descrizione, immagine miniatura.
- **Generico**: card con icona e nome file.
### 3.4 Modello `ChatMessage`
- Aggiungere `fileAttachment` opzionale con `previewType`, `sourceUrl`, `fileName`.
---
## Milestone 4 — Personalizzazione chat per dispositivo + sfondi immagine
### 4.1 Persistenza locale (SharedPreferences / Hive)
- Chiave: `chat_settings_<chatId>`.
- JSON con: `backgroundColor`, `bubbleColor`, `backgroundImagePath` (path locale o URL), `useDefaultTheme`.
- Default al primo accesso: `useDefaultTheme = true` (eredità da `AppPreferences.themeColorValue`).
### 4.2 UI
- In `_ChatPanel`: se `backgroundImagePath` è impostato, usare `DecoratedBox` con `NetworkImage` / `FileImage`.
- Aggiungere nel pannello impostazioni della chat:
  - Picker colore sfondo / bolle.
  - Picker immagine sfondo (galleria o URL).
  - Switch "Usa tema predefinito".
---
## Milestone 5 — Notifiche, vibrazioni, suonerie personalizzate
### 5.1 Dipendenze
- `flutter_local_notifications`
- `vibration`
- `audioplayers` (già usato per le audio bio)
### 5.2 Implementazione
- **Notifiche locali**: quando arriva un nuovo messaggio in background / app chiusa (tramite periodic fetch o quando app è in foreground).
- **Notifiche in-app**: badge non letti sulla lista chat.
- **Vibrazione**: pattern personalizzabile (`Vibration.vibrate(pattern: [...])`).
- **Suoneria**: picker file audio locale (assets o galleria). Salvare path in `AppPreferences`.
- **Canali notifica**: creare canali Android distinti per messaggi normali, gruppi, chiamate.
---
## Milestone 6 — Group Chat
### 6.1 UI Creazione gruppo
- Nuovo pulsante "Nuovo gruppo" in `HomeScreen`.
- Schermata: nome gruppo, selezione multipla partecipanti (da lista contatti/esistenti), scelta avatar.
### 6.2 UI Chat di gruppo
- Header con nome gruppo + avatar + numero partecipanti.
- Mostrare nome del mittente sopra ogni bolla (se non è il current user).
- Info gruppo: lista membri, opzioni admin.
### 6.3 Backend
- Già coperto nella Milestone 1.
---
## Milestone 7 — Profilo utente completo (foto, bio, bio vocale)
### 7.1 DB
- Già presente in `utenti`: `profile_photo_url`, `profile_bio`, `profile_audio_url`, `profile_audio_duration_seconds`.
### 7.2 UI
- Nuova schermata `ProfileScreen` accessibile da `HomeScreen`.
- Avatar tondo con `ImagePicker`.
- Campo bio (max 500 char).
- Registrazione audio bio: `record` + `audioplayers` per riprodurre. Validazione max 5 secondi (già presente nel backend).
- Salvataggio tramite `settings.php` `PATCH`.
### 7.3 Visualizzazione in chat
- Tapping su un mittente mostra popup profilo con foto, bio, audio bio.
---
## File coinvolti (principali)
### Database & Backend
- `webService/chat.sql` → aggiungere migration
- `webService/resources/chats.php`
- `webService/resources/chat.php`
- `webService/resources/files.php`
- `webService/resources/settings.php`
- `webService/index.php` (se necessario aggiungere CORS/metodi)
### Flutter — Modelli
- `flutterapp/lib/models/chat_thread.dart`
- `flutterapp/lib/models/user_profile.dart`
- `flutterapp/lib/models/chat_message.dart` (da creare se separato)
### Flutter — API
- `flutterapp/lib/api/chat_api.dart`
- `flutterapp/lib/api/auth_api.dart`
### Flutter — Servizi
- `flutterapp/lib/services/app_preferences.dart`
- `flutterapp/lib/services/notification_service.dart` (nuovo)
- `flutterapp/lib/services/api_exception_handler.dart` (nuovo)
### Flutter — UI
- `flutterapp/lib/screens/auth_screen.dart`
- `flutterapp/lib/screens/home_screen.dart`
- `flutterapp/lib/screens/profile_screen.dart` (nuovo)
- `flutterapp/lib/screens/group_create_screen.dart` (nuovo)
- `flutterapp/lib/widgets/message_bubble.dart` (nuovo)
- `flutterapp/lib/widgets/message_attachment_preview.dart` (nuovo)
- `flutterapp/lib/widgets/chat_background.dart` (nuovo)
### Flutter — Config
- `flutterapp/pubspec.yaml` (nuove dipendenze)
---
## Dipendenze Flutter da aggiungere
```yaml
dependencies:
  file_picker: ^8.0.0
  image_picker: ^1.1.0
  image: ^4.1.0
  video_player: ^2.8.0
  audioplayers: ^6.0.0
  record: ^5.0.0
  flutter_local_notifications: ^17.0.0
  vibration: ^1.8.0
  url_launcher: ^6.2.0
  cached_network_image: ^3.3.0
  shimmer: ^3.0.0
  flutter_highlight: ^0.7.0
  path_provider: ^2.1.0
  http_parser: ^4.0.0
```
---
## Note di design
- **Minimalismo**: ogni modifica deve essere il più piccola possibile. Non rifattorizzare per rifattorizzare.
- **Backward compatibility**: i vecchi messaggi 1-to-1 senza `chat_id` devono continuare a funzionare (`reciverID` resta opzionale/retrocompatibile).
- **Offline-first**: le modifiche locali (tema chat, notifiche) devono persistere su Hive/SharedPreferences anche senza rete.
- **Sicurezza**: upload file deve validare MIME type e limitare estensioni pericolose.

Alcune modifiche sono gia state implementate.