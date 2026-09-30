# Quice (Project Capolavoro)

> Featured on **[cristianrenosto.party/projects](https://cristianrenosto.party/projects)**

Self-hosted **LAN-first instant messaging** client — Flutter app + PHP/MySQL backend.

Ordinary messengers (WhatsApp, Discord) need the internet and third-party servers,
which is unacceptable in strict or offline environments. Quice targets **IT labs,
schools and air-gapped LANs** where messages must never leave the local network.

Formerly "ClassChat"; shipped under the name **Quice** (branded "Crimson Chat" in
older docs and in a few legacy database strings).

> The repository still contains two sibling planning documents, `gemini.md` and
> `todo.md`, both in Italian. See [Legacy planning docs](#legacy-planning-docs).

---

## Features

- **1-to-1 and group chat**, with delivery and read receipts
- **Typing and "recording" presence** indicators
- **File sharing of any type**, with inline previews for image, GIF, video, audio,
  PDF, code, and links
- **Per-chat, per-device theming** — background colour, background image, bubble colour
- **Offline-first**: local Hive queue plus LAN peer-to-peer delivery over mDNS
- **On-device translation** (ML Kit), canonicalising all stored messages to English
- **Profiles** with photo, 500-character written bio, and a **voice bio capped at 5 s**
- **HMAC-SHA256 request signing** on every API call
- Cryptographic scaffolding for E2EE / PEC / 2FA in the schema (not wired up)

## Tech stack

| Layer | Stack |
|---|---|
| App | Flutter / Dart, Material 3, glassmorphism UI, `framer`-style custom animations |
| State | `ValueNotifier` + `ChangeNotifier` — **no** `provider`/`bloc`, no code generation |
| Local storage | Hive (offline message queue), SharedPreferences (config, session, per-chat settings) |
| Networking | `http` (REST + multipart), `web_socket_channel`, `nsd` (mDNS) |
| Translation | `google_mlkit_translation` (on-device, **Android/iOS only**) |
| Backend | **PHP**, procedural, no framework, PDO + MySQL |
| Database | MySQL / MariaDB, schema `chatProject` |
| Realtime | HTTP polling (8 s ⇄ 2 s adaptive); a Ratchet WebSocket server exists but **cannot run** — see [Known issues](#known-issues) |

Targets **Android, iOS, Windows, Linux, macOS and Web**, with a Windows-desktop-first
development workflow.

## Project structure

```
projectCapolavoro/
├── flutterapp/         Flutter client (~12 000 lines Dart, 27 files)
├── webService/         PHP backend (1 696 lines) + a standalone Python 2FA module
├── build/              Generated Windows CMake tree — build artefacts, not scripts
├── gemini.md           7-milestone implementation plan (legacy)
└── todo.md             The original feature request, verbatim
```

## Prerequisites

| Component | Version |
|---|---|
| Flutter | 3.47.5 stable (`pubspec.lock` requires ≥ 3.38.4), Dart `>=3.11.5 <4.0.0` |
| PHP | **≥ 8.0** (`str_starts_with` / `str_ends_with`), with `pdo_mysql`, `sodium`, `openssl`, `fileinfo`, `json` |
| MySQL | 8 / MariaDB 10.x |
| Composer | Only for the (currently broken) WebSocket server |
| Python 3 | Only for the 2FA prototype tests — stdlib only |
| Android | Android SDK + JDK 17 |

`flutterapp/android/local.properties` hardcodes `flutter.sdk=/home/utente/flutter`
and must be regenerated per machine.

## Setup

### 1. Database

```bash
mysql -u root -p < webService/chat.sql

# Only for a pre-v2 database:
mysql -u root -p chatProject < webService/chat_migration_v2.sql

# Optional: seed three test users
php webService/seed.php
```

Credentials are **hardcoded in `webService/db.php`**: `127.0.0.1`, database
`chatProject`, user `root`, empty password. There is no `.env` — you must edit the
file.

Seed users: `3391234567`, `3391234568`, `3391234569`, password `password`.

> ⚠️ **`chat.sql` fails on a clean import.** `CREATE TABLE messaggi` declares a
> foreign key to `shared_files(id)`, but `shared_files` is only created ~18 lines
> later, and MySQL rejects references to non-existent tables (errno 150). Create
> `shared_files` first or drop the constraint. See
> [`docs.md`](./docs.md) §15.

### 2. Backend

```bash
chmod -R 755 webService/uploads

# Recommended: Apache with mod_rewrite (required for /uploads/*)
#   DocumentRoot = /path/to/webService, AllowOverride All

# Development fallback (uses the ?route= path)
cd webService && php -S 0.0.0.0:8000
```

### 3. App

```bash
cd flutterapp
flutter pub get
flutter run                 # or: flutter run -d windows
```

Then point the app at your server. **There is no runtime base-URL setting** — edit
the constant:

```dart
// flutterapp/lib/api/auth_api.dart
static const String _defaultBaseUrl =
    'https://esempio-tunnel.ngrok-free.app/index.php';
```

`AuthApi.configure(baseUrl: …)` exists but is only called from a test.

## Tests

```bash
cd flutterapp && flutter test
```

15 test cases across 7 files, using `http.MockClient` and a `FakeChatApi` subclass:

| File | Covers |
|---|---|
| `app_request_signer_test.dart` | The exact canonical signing string, header names, 32-byte base64 signature |
| `id_validation_test.dart` | 10-digit ID rules, `UserProfile` throwing on bad input, 5.1 s audio rejection |
| `app_preferences_test.dart` | Theme and language load, settings persistence |
| `chat_api_offline_first_test.dart` | `SocketException` → message queued; online → queue flushed |
| `chat_api_translation_test.dart` | Outgoing translated to English; incoming to `it` while `canonicalText` stays English |
| `home_screen_new_chat_test.dart` | New-chat pane, 10-digit validation |
| `widget_test.dart` | Splash renders — **currently failing**, see Known issues |

**The PHP backend has zero tests.** No PHPUnit, no CI.

## Configuration

Two environment variables, both optional with hardcoded fallbacks:

| Variable | Fallback | Effect |
|---|---|---|
| `CRIMSON_CHAT_APP_SECRET` | `SEGRETO_DA_RUOTARE` | HMAC request-signing secret |
| `CRIMSON_CHAT_ADMIN_BYPASS_PASSWORD` | `SEGRETO_DA_RUOTARE` | The **only** gate on uploads over 50 MB |

There are **no build flavours**: no `--dart-define`, no Gradle dimensions, no
`.env.production`. A single variant targets one hardcoded URL, so every deployment
is a source edit plus a rebuild.

## How it fits together

```
Flutter client (Quice)
  ├── HTTPS/JSON ─────────► webService/index.php
  │                            ├── HMAC verify (X-App-Key / Timestamp / Signature)
  │                            ├── resources/{auth,chats,chat,settings,files,security}.php
  │                            ├── serve_file.php  (uploads, UNAUTHENTICATED)
  │                            └── MySQL  chatProject
  ├── WebSocket ──────────► ws-server.php  (Ratchet)  [cannot run: no vendor/]
  ├── mDNS _cpchat._tcp ───► other clients on the LAN  (P2PSyncService)
  └── 8 s / 2 s polling ───► index.php/chat + /chats   (the only working realtime)
```

**User identity is the phone number**, and it is exactly 10 digits. There is no
email identity, no contacts import and no directory server: you find people by
exchanging numbers.

## Known issues

Ordered by how much they will bite you.

1. **`chat.sql` will not import on a clean database** (FK ordering, above).
2. **The terminal of `ws-server.php` cannot start.** It needs `Ratchet\*` and
   `react/event-loop`, but there is no `composer.json` and no `vendor/`, so
   `require __DIR__.'/vendor/autoload.php'` fatals immediately. The "real-time
   messaging" claim effectively rests on the 8 s HTTP poll.
3. **Registering an 8- or 11-digit number locks you out.** The onboarding screen
   accepts 8–15 digits and labels the field "Numero di telefono (8-15 cifre)", but
   the server requires exactly 10 (`/^\d{10}$/`) and the `UserProfile` constructor
   **throws**. You can register and then never log in again.
4. **`uploads/` performs no MIME or extension validation.** A committed
   executable `.php` file has been **removed** and a `uploads/.htaccess` now
   denies execution of script extensions, but the underlying hole in
   `files.php` is still open: a real blocklist belongs in the upload handler.
   See [`docs.md`](./docs.md) §15.
5. **`test/widget_test.dart` is red**: it asserts `Icons.forum_rounded`, but
   `splash_screen.dart` renders `Icons.chat_bubble_outline_rounded`.
6. **TLS verification is globally disabled** in `main.dart`
   (`badCertificateCallback => true`), so HTTPS gives no protection.
7. **The user's password is stored in cleartext** in SharedPreferences
   (`session_password`) and re-sent on every cold start.
8. **E2EE is decorative.** `security.php` has no client, nothing generates keys, and
   the onboarding tutorial still claims end-to-end encryption.
9. **The dead `group_` prefix check** in `chat_api.dart:336` can never be true,
   because PHP generates purely numeric group IDs.

## Legacy planning docs

`gemini.md` (163 lines) is a 7-milestone implementation plan, and `todo.md` is the
original Italian feature request. **Neither is current documentation** — both
describe an earlier state of the code. They are kept because they record the
project's design intent, and because `todo.md` is the only statement of the
original requirements. Full assessment in [`docs.md`](./docs.md) §17.

## Documentation

| File | Content |
|---|---|
| [`docs.md`](./docs.md) | Architecture, API reference, data model, security posture, dead code, gaps, README-vs-code discrepancies |

## Licence

Not present in the repository.
