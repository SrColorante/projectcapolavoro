# Quice (Project Capolavoro) — Technical Documentation

In-depth reference for **Quice**, a self-hosted LAN-first instant messaging client
(Flutter + PHP/MySQL) built as a final-year "progetto di capolavoro".

> **Snapshot:** branch `main`, 2 commits (`e6da365` initial clone, `3545d4c`
> "docs: add professional README for portfolio showcase"). The existing README was
> written in an LLM pass **from the README, not from the code**, and several of its
> claims are contradicted by the implementation — see §18.
>
> For a quick overview see [`README.md`](./README.md).

---

## Table of contents

1. [Purpose and design intent](#1-purpose-and-design-intent)
2. [Tech stack](#2-tech-stack)
3. [Architecture](#3-architecture)
4. [Source layout](#4-source-layout)
5. [API reference](#5-api-reference)
6. [Data model](#6-data-model)
7. [Networking and request signing](#7-networking-and-request-signing)
8. [The realtime story](#8-the-realtime-story)
9. [Client features](#9-client-features)
10. [Build and run](#10-build-and-run)
11. [Configuration](#11-configuration)
12. [Tests](#12-tests)
13. [Security posture](#13-security-posture)
14. [Dead code](#14-dead-code)
15. [Security findings](#15-security-findings)
16. [Not implemented](#16-not-implemented)
17. [Legacy planning docs](#17-legacy-planning-docs)
18. [README vs code](#18-readme-vs-code)
19. [Appendix](#19-appendix)

---

## 1. Purpose and design intent

### 1.1 The problem

Standard messengers require internet access and third-party infrastructure. In
strict environments — school IT labs, air-gapped corporate LANs, examination
settings — that is unacceptable: **messages must never leave the local network**.

Quice is designed for exactly that: a self-hosted messenger where the backend sits
on the local network and, where the network allows it, clients can deliver to each
other **peer-to-peer** without the server in the middle.

### 1.2 Identity model

A user **is** their phone number. `IDutente` is a 10-digit `BIGINT UNSIGNED` and
serves as the primary key. There is no email-based identity, no contacts import
and no directory server: you find people by exchanging numbers, and typing one in
opens a chat.

This is a deliberate simplification that fits the target environment — a classroom
where everyone knows everyone else's number — and it has a real cost: there is no
way to discover a user you don't already have a number for.

### 1.3 Feature pillars as coded

1-to-1 and group chat · delivery and read receipts · typing and "recording"
presence · file sharing of any type with rich inline previews · per-chat
per-device theming · offline-first with a local Hive queue and LAN P2P delivery ·
on-device translation canonicalising stored messages to English · profiles with
photo, 500-character bio and a 5-second voice bio · HMAC-SHA256 request signing ·
E2EE / PEC / 2FA scaffolding in the schema.

### 1.4 Languages

Code comments, UI strings and the two planning documents are **Italian**; the
original README was English. This document is English to match the code's
identifiers, but the UI is Italian throughout.

---

## 2. Tech stack

### 2.1 `flutterapp/` — Flutter

| Package | Resolved | Role |
|---|---|---|
| `crypto` | 3.0.7 | HMAC-SHA256 request signing |
| `google_mlkit_translation` | 0.13.1 | On-device translation — **Android/iOS only** |
| `http` | 1.6.0 | REST + multipart upload |
| `web_socket_channel` | 2.4.0 | WebSocket (see §8) |
| `hive` | 2.2.3 | Offline message queue |
| `nsd` | 4.1.0 | mDNS service discovery for LAN P2P |
| `shared_preferences` | 2.5.5 | Config, session, per-chat settings |
| `file_picker` | 8.3.7 | Attach any file |
| `image_picker` | 1.2.2 | Profile photo |
| `video_player` / `audioplayers` | 2.11.1 / 6.6.0 | Attachment playback, voice bio |
| `record` | 6.2.1 | Voice-bio recording (5 s cap) |
| `flutter_local_notifications` | 17.2.4 | **Declared but unused** |
| `vibration` | 1.9.0 | Only used by the unused `NotificationService` |
| `url_launcher` | 6.3.2 | "Open" files/links externally |
| `cached_network_image` | 3.4.1 | Cached previews, network backgrounds |
| `shimmer` | 3.0.0 | Loading placeholders |
| `image` | 4.8.0 | **Declared but never imported** |
| `http_parser` | 4.1.2 | **Declared but never imported** |

**Absent by choice:** no `provider`, `bloc`, `go_router`, `dio`, `sqflite`, no
`hive_generator`/`build_runner`, no `mocktail`. **Zero code generation.** State is
`ValueNotifier` + `ChangeNotifier` with a hand-rolled message-merge algorithm.

No `assets:` section in `pubspec.yaml` — every image is code-drawn (`IconData`) or
loaded from network/local files.

### 2.2 `webService/` — PHP and Python

**There is no `composer.json`, no `requirements.txt`, no `pom.xml`.** The backend
is procedural PHP with no framework, no autoloader, and one class. It uses `PDO`,
`password_hash`/`password_verify` (bcrypt), `sodium_*` with an `openssl` RSA-2048
fallback, `finfo`, `move_uploaded_file` and `hash_hmac`.

A **standalone Python 3 module** (`webService/python/otp_2fa.py`, 97 lines) implements
an OTP engine on the standard library alone, with its own `unittest` suite. **Nothing
in PHP calls it**, and the `otp_two_factor_codes` table it would back is never read
or written by any PHP file. It is a design prototype, not an integrated feature.

### 2.3 Platform configuration

- **Android**: `applicationId` is still `com.example.flutterapp` (the default, never
  changed); `release` is signed with the **debug key**; the manifest declares only
  `INTERNET` and `CHANGE_WIFI_MULTICAST_STATE`
- **iOS**: `NSBonjourServices = _cpchat._tcp` and `NSLocalNetworkUsageDescription`
  are present; `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription`
  are **missing**
- **macOS**: `com.apple.security.network.server` in the debug entitlements, matching
  the embedded P2P HTTP server

---

## 3. Architecture

```
                    Flutter client (Quice)
                            │
     ┌──────────────┬───────┴───────┬──────────────────┐
     │              │               │                  │
  HTTP/JSON     WebSocket        mDNS + HTTP       Hive queue
     │              │               │                  │
     ▼              ▼               ▼                  ▼
 index.php    ws-server.php    other clients      offline_message_store
     │         (Ratchet)        on the LAN
     ├── HMAC verification
     ├── resources/auth.php
     ├── resources/chats.php
     ├── resources/chat.php
     ├── resources/settings.php
     ├── resources/files.php
     ├── resources/security.php
     ├── serve_file.php   ← UNAUTHENTICATED
     └── MySQL  chatProject
```

**Backend shape.** `index.php` is a single front controller with a hand-rolled
`switch` on an `action` field, dual-routed so that both `/webService/chat` (Apache
`mod_rewrite`) and `index.php?route=chat` (the `php -S` fallback) work. It is
**not a REST API**: mutations are selected by a field in the JSON body, not by path
or HTTP method.

**Client shape.** `AuthApi` is a static class; `ChatApi` is an injectable instance
taking `http.Client`, `baseUrl` and a `MessageTranslator` — which is what makes the
`MockClient`-based tests possible.

---

## 4. Source layout

### 4.1 `webService/` — 1 696 lines of PHP

| File | Lines | Responsibility |
|---|---:|---|
| `resources/auth.php` | 262 | `guest_login`, `login`, `register`, `enable_2fa`, `certify_pec`; unique-ID generation, 14-field profile projection, language normaliser, 5-second audio-bio validation |
| `resources/chat.php` | 247 | Read receipts + typing snapshot + messages joined to `shared_files`; message insert; nickname update |
| `resources/files.php` | 247 | Real multipart upload (50 MB gate + admin bypass) or metadata-only registration; preview-type resolution |
| `resources/chats.php` | 168 | Chat list (1-1 + groups) with membership join; group creation; 1-1 create/reuse |
| `resources/settings.php` | 93 | Profile read/upsert with `COALESCE(NULLIF(…))` |
| `resources/security.php` | 70 | E2EE keypair generation (libsodium, OpenSSL fallback) — **no client** |
| `db.php` | 78 | PDO connection + **6 self-healing migrations run on every request** |
| `ws-server.php` | 88 | Ratchet `ChatServer` — **cannot run** |
| `index.php` | 200 | Front controller, CORS, HMAC validation, routing, dispatch |
| `serve_file.php` | 64 | **Unauthenticated** binary file server for `uploads/` |
| `seed.php` | 56 | Idempotent 3-user seeder |
| `chat.sql` | 115 | Full schema — **fails on clean import**, see §15.4 |
| `chat_migration_v2.sql` | 45 | Migration for pre-v2 databases |
| `.htaccess` | 4 | Apache catch-all rewrite |
| `python/otp_2fa.py` | 97 | Standalone OTP engine (orphaned) |
| `python/test_otp_2fa.py` | 55 | Its unittest suite |

### 4.2 `flutterapp/lib/` — 12 012 lines of Dart, 27 files

| File | Lines | Responsibility |
|---|---:|---|
| `screens/onboarding_wizard.dart` | 1718 | The real entry/auth flow: 5 steps, custom transition clippers |
| `screens/home_screen.dart` | 3176 | **The monolith**: chat list, adaptive split-pane, 20 `ValueNotifier`s, message merging, adaptive polling, per-chat settings, file pick/upload |
| `widgets/message_attachment_preview.dart` | 1340 | The richest widget: 7 preview kinds, lightbox, two audio player designs, video scrubber, syntax-highlighted code viewer |
| `widgets/rich_color_board.dart` | 579 | 32 curated swatches + custom HEX/HSL picker |
| `api/chat_api.dart` | 532 | REST client, multipart upload, offline queue flush, connectivity detection, translation hooks |
| `screens/auth_screen.dart` | 551 | **Dead code** — a standalone login screen nothing navigates to |
| `screens/profile_screen.dart` | 489 | Avatar, nickname, 500-char bio, 5 s voice bio, language |
| `services/p2p_sync_service.dart` | 400 | LAN mesh: embedded HTTP server, mDNS, offline bridge |
| `services/offline_message_store.dart` | 220 | Hive queue and chat links |
| `ui/BackgroundParticles` (n/a — backend) | — | — |
| `api/auth_api.dart` | 325 | Static auth client, 14-field profile mapping |
| `screens/splash_screen.dart` | 403 | Animated splash + auto-login router at 3.2 s |
| `widgets/user_profile_dialog.dart` | 308 | Profile dialog with voice-bio playback |
| `services/chat_service.dart` | 195 | WebSocket client with reconnect and optimistic sends |
| `services/app_preferences.dart` | 179 | `ChangeNotifier` over SharedPreferences |
| `services/message_translation_service.dart` | 178 | `MessageTranslator` abstraction, ML Kit cache |
| `services/api_exception_handler.dart` | 162 | Error snackbar, retry banner, shimmer placeholders |
| `services/notification_service.dart` | 116 | **Dead code** — zero call sites |
| `services/app_request_signer.dart` | 84 | HMAC-SHA256 canonical signing |
| `widgets/contact_preview_bubble.dart` | 222 | **Dead code** — zero references |
| `widgets/chat_background.dart` | 73 | Per-chat background resolution |
| `screens/group_create_screen.dart` | 226 | Group creation |
| `client/*.dart` | — | `ClientNetwork`-equivalent transport |
| `screens/mobile_chat_screen.dart` | 104 | Adapter re-hosting the shared chat panel on mobile |
| `screens/mobile_settings_screen.dart` | 107 | Same pattern for settings |

### 4.3 `build/` is not what the old README said

The root `build/` is a **generated Windows CMake tree**: `flutterapp.slnx`,
`ALL_BUILD.vcxproj`, `CMakeCache.txt` with absolute Windows paths, `runner/`,
`plugins/`. It contains **no deployment scripts** — the old README's claim was
simply wrong. It is build noise that happens to be committed.

---

## 5. API reference

All requests except `serve_file` must be **HMAC-signed** (see §7). All except
`serve_file` and `seed.php` take `user_id` as a query parameter.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `?file=<name>` on `serve_file` | **No auth.** Stream a file from `uploads/` |
| `POST` | `auth`, `action=guest_login` | Create a guest, return the profile |
| `POST` | `auth`, `action=login` | `phone` + `password` → profile |
| `POST` | `auth`, `action=register` | Create an account; phone is the primary key |
| `POST` | `auth`, `action=enable_2fa` | Sets 2FA fields — **no OTP step at all** |
| `POST` | `auth`, `action=certify_pec` | Stamps `pec_certified_at` |
| `GET` | `chats?user_id=` | All 1-1 and group chats, members, last message |
| `POST` | `chats?user_id=` | `target_user_id` for 1-1, or `is_group`+`name`+`member_ids[]` for a group |
| `GET` | `chat?user_id=&chat_id=` | Messages with joined file metadata, plus a `typing[]` snapshot; marks others' messages read |
| `POST` | `chat?user_id=` | Typing-status upsert, or a message insert |
| `PATCH` | `chat?user_id=` | Update own nickname |
| `GET` | `settings?user_id=` | Own nickname, language, bio, photo, audio |
| `POST`/`PATCH` | `settings?user_id=` | Upsert the same, with 5 s audio validation |
| `POST` | `files?user_id=` (multipart) | Real binary upload |
| `POST` | `files?user_id=` (JSON) | Metadata-only registration |
| `GET` | `files?user_id=` | Own file list |
| `POST` | `security`, `action=generate_e2ee_keypair` | libsodium X25519 or OpenSSL RSA-2048 |
| `POST` | `security`, `action=prepare_encrypted_message` | Echoes the ciphertext envelope — **no client** |
| `GET` | `seed.php` | **No auth.** Idempotent seeder, prints credentials |

The 404 handler enumerates them: `"Endpoint validi: /chats, /chat, /settings,
/auth, /security, /files"`.

### 5.1 Request and response shapes

**Send a message** — `chat_id` when available, else the legacy `reciverID`:

```json
{ "textmessage": "…", "chat_id": "2345678901", "file_attachment_id": 42 }
```

The full response of a fetch:

```json
{ "success": true,
  "data": [ { "id": 1, "textmessage": "…", "senderID": "3391234567",
              "chat_id": "2345678901", "file_attachment_id": null,
              "timenow": "…", "status": "read", "is_certified": 0,
              "message_signature": null, "e2ee_metadata": null,
              "file_name": null, "mime_type": null, "source_url": null,
              "preview_type": null, "preview_payload": null } ],
  "typing": [ { "user_id": "3391234568", "status": "typing", "nickname": "…", "nome": "…" } ] }
```

**Upload** — multipart fields `file`, optional `admin_password`,
`override_limit=true`, `message_id`. `preview_type` is one of
`audio, image, gif, video, pdf, link, file`.

`reciverID` is **misspelled in the API and in the database column** alike, so the
typo is at least consistent.

---

## 6. Data model

MySQL `chatProject`, `utf8mb4`, `ATTR_EMULATE_PREPARES => false`.

```
utenti (IDutente PK = 10-digit phone, nome, cognome, nickname, email? UNIQUE,
        password_hash, dataCreazione, is_guest, preferred_language,
        profile_bio(500), profile_photo_url, profile_audio_url,
        profile_audio_duration_seconds DECIMAL(4,2), e2ee_public_key TEXT,
        two_factor_enabled, two_factor_channel ENUM(email,phone),
        two_factor_destination, two_factor_verified_at, pec_certified_at)
        CHECK (IDutente BETWEEN 1000000000 AND 9999999999)

chat (IDchat PK = random 10 digits, is_group, name?, created_by?, avatar_url?,
      utente1?, utente2?)                       -- utente1/2 NULL for groups
chat_members (chat_id, user_id, joined_at, role ENUM(admin,member),
              PK(chat_id,user_id))
messaggi (id AUTO_INC, textmessage VARCHAR(15000), senderID, reciverID?,
          chat_id?, file_attachment_id?, timenow DATETIME,
          is_certified, message_signature TEXT?, e2ee_metadata JSON?)
shared_files (id AUTO_INC, owner_user_id, file_name, mime_type, size_bytes,
              source_url, preview_type ENUM(...), preview_payload JSON,
              message_id?, bypassed_limit, created_at)
otp_two_factor_codes (...)      -- never read or written by any PHP file
chat_typing_status (chat_id, user_id, status, updated_at, PK(chat_id,user_id))
```

**There is a deliberate circular foreign key**: `messaggi.file_attachment_id →
shared_files.id` and `shared_files.message_id → messaggi.id`, both
`ON DELETE SET NULL`. That works, but it is the direct cause of the import failure
in §15.4.

### 6.1 `chat_typing_status` is created at runtime, not in the schema

`db.php` runs **six `ALTER TABLE`/`CREATE TABLE` statements on every single
request**, each in its own try/catch. `chat_typing_status` exists only there — it
is never in `chat.sql`. So a fresh import of `chat.sql` yields a schema the app
cannot use until the first request repairs it.

This is defensible as a convenience, but it is wasteful, and it **silently masks
schema drift**: a column that should have been migrated simply appears one day.

### 6.2 `db.php` hardcodes root with an empty password

`127.0.0.1`, `chatProject`, `root`, `""`. There is no `.env` and no example file.
Editing the file is the only configuration path.

---

## 7. Networking and request signing

### 7.1 The canonical string

Every request except `serve_file` carries three headers. The canonical form is
identical in `index.php` and `app_request_signer.dart`:

```
METHOD \n
PATH \n
sorted-and-encoded-QUERY \n
UNIX-TIMESTAMP \n
RAW-BODY
```

The signature is `base64(HMAC_SHA256(secret, canonical))`, compared with
`hash_equals`. Timestamp skew beyond 300 s yields `"Richiesta scaduta"`.

> **Multipart uploads sign with an empty body string**, because PHP never populates
> `php://input` for a multipart request. There's an explicit comment explaining
> this in `chat_api.dart`.

### 7.2 The secret is hardcoded on both sides

- PHP default: `'crimson-chat-signing-secret-2026-v1-please-rotate'`, overridable
  by `getenv('CRIMSON_CHAT_APP_SECRET')`
- Dart: `static const String _sharedSecret = 'crimson-chat-signing-secret-2026-v1-please-rotate'`

A Dart `static const` is recoverable from the compiled binary. This is
**obfuscation, not authentication** — see §13.

### 7.3 There are no sessions

Authentication is *the phone number passed as a plain `?user_id=` query parameter*,
signed but **not bound to the connection**. Anyone holding the shared secret can
read any user's chats. Session persistence is a plaintext
`session_phone` + `session_password` pair in SharedPreferences, re-validated on
every app start.

### 7.4 `P2PSyncService.initialize()` runs on every API call

`_initializeOfflineFirst` is invoked at the top of every `ChatApi` method, and it
binds an `HttpServer`, registers an mDNS service and starts a 20-second timer. On a
desktop OS that is a **visible side effect per API call**.

### 7.5 Offline detection

`_isConnectivityError` matches `TimeoutException | SocketException |
http.ClientException` and falls back to `P2PSyncService.buildLocalChats/Message`
plus `sendP2P` and `queueOutgoing`.

---

## 8. The realtime story

**There are three overlapping mechanisms, and only one reliably works.**

| Mechanism | Status |
|---|---|
| **HTTP polling** | ✅ Works. 8 s, tightening to 2 s while anyone is typing or recording, relaxing after a 20 s cooldown |
| **WebSocket** (`ws-server.php`) | ❌ **Cannot run.** No `composer.json`, no `vendor/`. Additionally, its URL derivation is broken for the default `ngrok` base URL |
| **LAN P2P over mDNS** | ⚠️ Works on a shared network only |

`ws-server.php` is a Ratchet `ChatServer` implementing `MessageComponentInterface`
with rooms, `join` / `new_message` / `typing_start|stop` / `recording_start|stop` /
`user_joined` / `user_left` broadcast, and an `IoServer` on port **8080**. Its
first line is `require __DIR__ . '/vendor/autoload.php';` — and there is no
`vendor/`. The file is **unrunnable as committed**.

**The old README's "Real-time messaging" claim therefore rests entirely on the
8-second HTTP poll.** That is still perfectly usable for a classroom, but it is
polling, not real-time.

### 8.1 Translation is canonicalised to English

`MessageTranslationService` declares the canonical language as **English**. Every
message is stored translated, and `canonicalText` keeps the original English form.
`supportsRuntimeTranslationOnCurrentPlatform` is **false off Android/iOS**, because
ML Kit is a native plugin.

---

## 9. Client features

### 9.1 Flow

`SplashScreen` (3.2 s) → `OnboardingWizardScreen` (5 steps) or `HomeScreen`.

### 9.2 Home

- Chat list with **swipe-to-archive** and a dedicated archived view, persisted per
  user under `archived_chats_<userId>`
- Desktop: two-pane (3:5 flex) with `BackdropFilter` glassmorphism; mobile: full-width
  list with chat and settings pushed as routes
- App settings: accent colour (32 curated swatches plus HEX/HSL), app background
  colour, app background image, message language (16), vibration toggle, ringtone
  picker, edit profile, disconnect
- An automatic **self-chat** ("Note personali (Tu)") is created on first load
- Silent background polling: `fetchChats` + `fetchMessages` every 8 s, tightening to
  2 s on activity

### 9.3 Chat

- Header with avatar, title, and either the participant number, `N partecipanti`, or
  a live *"X sta scrivendo…" / "X sta registrando…"* line
- Bubbles: gradient outgoing, glass incoming, timestamp + status ticks, sender name
  above the bubble in groups (tappable → profile)
- **Code blocks**: fenced ` ```lang:filename ` segments are rendered by a
  hand-rolled highlighter; sending a `.py`/`.dart`/`.ino` file **inlines the whole
  file as a fenced block**
- Attachments: 7 preview kinds, each with real play/zoom/open actions
- Per-chat customisation: use-default-theme switch, background colour, bubble colour,
  background image
- Optimistic local echo with `temp_<microseconds>`, plus a merge/diff algorithm that
  avoids reloading media

### 9.4 Dead branch in the offline path

```dart
// chat_api.dart:336
if (chatId == null || !chatId.startsWith('group_')) {
```

`chatId` is always set at that point, and **PHP generates purely numeric 10-digit
group IDs** — so `startsWith('group_')` can never be true. The branch is always
taken; the guard is theatre.

---

## 10. Build and run

```bash
# Database
mysql -u root -p < webService/chat.sql          # ⚠️ fails on clean import, §15.4
php webService/seed.php

# Backend
chmod -R 755 webService/uploads
cd webService && php -S 0.0.0.0:8000            # dev fallback via ?route=

# App
cd flutterapp
flutter pub get
flutter run
flutter run -d windows                          # the developer's main target
flutter test
flutter analyze

# Build
flutter build apk --release
flutter build windows --release
```

### 10.1 WebSocket server (currently broken)

```bash
cd webService
composer require cboden/ratchet react/event-loop   # no composer.json exists
php ws-server.php
```

### 10.2 Python 2FA prototype

```bash
cd webService/python && python -m unittest
```

### 10.3 There is no runtime base-URL setting

The only way to point the app at a server is to edit a `static const` in
`auth_api.dart` and rebuild. `AuthApi.configure(baseUrl: …)` exists and is called
only from a test. **This is the single most annoying thing about working on the
project** — see §11 on build flavours.

---

## 11. Configuration

### 11.1 Environment variables

| Variable | Read at | Fallback |
|---|---|---|
| `CRIMSON_CHAT_APP_SECRET` | `index.php` | `'crimson-chat-signing-secret-2026-v1-please-rotate'` |
| `CRIMSON_CHAT_ADMIN_BYPASS_PASSWORD` | `files.php` (twice) | `'crimson-admin-bypass'` |

The second is compared with `hash_equals` and is **the only gate** on uploads over
50 MB.

### 11.2 Local preference keys

`app_theme_color`, `app_background_color`, `app_background_image_path`,
`preferred_language_code`, `session_phone`, **`session_password` (plaintext)**,
`session_is_guest`, `session_guest_name`, `session_user_profile`,
`notifications_vibration_enabled`, `notifications_ringtone_path`,
`chat_settings_<chatId>` (JSON: background, bubble, image, use-default),
`archived_chats_<userId>`. Hive: `offline_messages`, `offline_chat_links`.

### 11.3 Config files

| File | Note |
|---|---|
| `webService/db.php` | DB credentials, **hardcoded** |
| `webService/.htaccess` | Apache catch-all |
| `flutterapp/lib/api/auth_api.dart` | API base URL |
| `flutterapp/lib/services/app_request_signer.dart` | App key id + shared secret |
| `flutterapp/android/app/build.gradle.kts` | Default `applicationId`; release signed with the **debug key** |
| `flutterapp/android/local.properties` | `flutter.sdk=/home/cristian/flutter` — **machine-specific, committed** |
| `/.vscode/settings.json` | `cmake.sourceDirectory: C:/Users/crist/Desktop/g/projectcapolavoro/flutterapp/windows` — stale absolute path |

### 11.4 No build flavours

No `--dart-define`, no `dart-define-from-file`, no Gradle `flavor` dimension, no
`.env.staging`. One variant, one hardcoded URL, one release key that is the debug
key.

---

## 12. Tests

15 test cases in 7 files (492 lines) plus a Python suite.

**What is good:** the pure logic is genuinely well tested — exact canonical signing
string, 10-digit ID rules, `UserProfile` invariants, `AppPreferences` persistence,
offline queueing and flushing, translation in and out.

**What is missing:**

| Area | Status |
|---|---|
| PHP backend | **Zero tests.** No PHPUnit, no integration tests, no CI |
| `p2p_sync_service.dart` (400 lines) | Only exercised incidentally |
| `message_attachment_preview.dart` (1 340 lines) | 0 tests |
| `rich_color_board.dart` (579 lines) | 0 tests |
| `onboarding_wizard.dart` (1 718 lines) | 0 tests |
| Widget tests | Thin: 2 cases plus 1 in `widget_test.dart` |
| E2E / real server | None |
| Coverage tooling | None |

### 12.1 A test is currently red

```dart
// flutterapp/test/widget_test.dart:24
expect(find.byIcon(Icons.forum_rounded), findsOneWidget);
```

```dart
// flutterapp/lib/screens/splash_screen.dart:291
Icons.chat_bubble_outline_rounded,
```

The test asserts an icon the splash screen does not render. **It cannot pass as
written.** The fix is one identifier.

---

## 13. Security posture

Stated plainly, because this matters for a graded artifact and because the app
*tells users* it is secure.

| Issue | Detail |
|---|---|
| 🔴 **HMAC secret in the binary** | A Dart `static const`, recoverable from the compiled artefact. This is obfuscation, not authentication |
| 🔴 **No sessions** | `?user_id=` in the query string, signed but not bound to the connection. Anyone with the secret can read any user's chats |
| 🔴 **Password stored in cleartext** | `session_password` in SharedPreferences, re-sent on every cold start |
| 🔴 **TLS verification disabled globally** | `main.dart` installs an `HttpOverrides` with `badCertificateCallback => true`, so HTTPS provides no protection against MITM |
| 🔴 **`serve_file.php` is unauthenticated** | Serves any file in `uploads/` by name |
| 🔴 **No upload validation** | Filename sanitised, but **no MIME check and no extension blocklist** — see §15 |
| 🟠 **`Access-Control-Allow-Origin: *`** | On every response |
| 🟠 **E2EE claims are not honoured** | See §15.2 |

What *is* done properly: bcrypt for passwords (`password_hash`/`password_verify`),
`hash_equals` for the HMAC comparison, `basename()` sanitisation in `serve_file`,
`PDO` prepared statements throughout the data path, and a timestamp window of 300 s
against replay.

---

## 14. Dead code

Verified by declaring each symbol and confirming zero callers anywhere in `lib/`.

| Symbol | Lines | Note |
|---|---:|---|
| `NotificationService` | 116 | **Zero call sites.** This is why notifications, vibration and ringtones are non-functional: the milestone is ~50 % implemented but entirely unreachable |
| `auth_screen.dart` | 551 | A whole login screen nothing navigates to; superseded by `onboarding_wizard.dart` |
| `contact_preview_bubble.dart` | 222 | Zero references; superseded by `user_profile_dialog.dart` |
| `flutter_local_notifications` | dep | Only referenced by the dead service |
| `vibration` | dep | Only referenced by the dead service |
| `image`, `http_parser` | dep | Declared, never imported |
| `security.php` endpoints | 70 | No client; `grep route=security` returns zero hits |
| `otp_2fa.py` + its table | 97 | Orphaned design prototype |
| `enable_2fa` | — | Flips a boolean with **no OTP step**, so `certify_pec` needs only a password |
| `chat_id.startsWith('group_')` | — | Dead guard, see §9.4 |

---

## 15. Security findings

### 15.1 A committed executable PHP file in `uploads/` — mitigated, not fixed at the source

**Status: partially remediated.** The file has been deleted and execution is now
denied by configuration, but the underlying upload-validation hole is still open.

`webService/uploads/` contained `file_6a13106569b6c_index.php` — a **125-line PHP
script that has nothing to do with this project**. It is a library-management
exercise against a database called `esercizio`, with **unparameterised,
SQL-injectable queries**:

```php
$conn = new PDO("mysql:host=localhost;dbname=esercizio", "root", "");
$conn->query("SELECT * FROM volumi WHERE isbn = $isbn;");
```

It had been committed to a **public GitHub repository** in the initial commit
(`e6da365`).

**Honest severity assessment.** The direct risk was low: the script targets a
database that almost certainly does not exist on the Quice host, so it fails at the
`PDO` constructor and prints "problemi di connessione al db". But the finding
mattered for two real reasons:

1. **It proved the app performs no upload validation.** `files.php` sanitises only
   the *filename* with `preg_replace('/[^a-zA-Z0-9_.-]/', '_', …)` — there is no
   MIME-type check and no extension blocklist. The file got in through the normal
   upload path, which means any user could upload a `.php` file.
2. **If `webService/` is the Apache DocumentRoot and PHP execution is enabled in
   `uploads/`, the file is directly reachable** and executes. That is a live
   webshell vector, independent of whether this particular script does anything.

#### What was done

| Action | Detail |
|---|---|
| File removed | `git rm webService/uploads/file_6a13106569b6c_index.php`; a copy is kept outside the repository. The deletion is **staged, not yet committed** |
| Execution denied | New `webService/uploads/.htaccess`: `php_flag engine off` for mod_php 5/7/8, `RemoveHandler`/`RemoveType` for the fpm/CGI SAPIs, a `<FilesMatch>` on the executable extensions with `Require all denied`, and `Options -ExecCGI -Includes` |
| Media unaffected | Verified that `.jpg`, `.m4a`, `.mp3`, `.pdf` and `.ino` all still resolve as servable, so the "attach any file" feature is intact |

The `.htaccess` is effective only where Apache has `AllowOverride All` for the
directory — the same prerequisite as the existing rewrite in `webService/.htaccess`.
**With `php -S` the rules are not read at all**, so the development fallback server
gives no protection here; the enforcement has to live in the upload handler.

#### 15.1.1 What is still missing

The `.htaccess` is a perimeter control, not a fix. The authoritative check belongs
in `webService/resources/files.php`, and it is still absent:

- **No extension blocklist.** Deny at least `php`, `phtml`, `phar`, `cgi`, `pl`,
  `py`, `sh`, `asp`, `aspx`, `jsp` — on the *stored* name, not the submitted one.
- **No MIME allowlist.** `finfo` is available and already used in `serve_file.php`;
  comparing it against the extension would reject a `.jpg` that is really a script.
- **The stored name is attacker-influenced.** `uniqid('file_') . '_' . $safe_name`
  keeps the sanitised original name as a suffix, so the extension survives into the
  stored path. A fixed stored name plus the extension in a metadata column would
  remove the class of problem, not one instance of it.

Note the deliberate trade-off: `.exe` and similar binaries are **not** blocked,
because sharing files of any type is a stated product feature. Serving arbitrary
binaries from a public directory is a separate and milder concern — a distribution
channel — and should be a product decision rather than an accident.

### 15.2 The app makes security claims it does not honour

The onboarding tutorial states *"crittografia end-to-end"* and *"firma
crittografica delle richieste API e verifica in due passaggi"*.

- The **request signing is real** — HMAC-SHA256 with a timestamp window. That claim
  is accurate.
- **End-to-end encryption is not implemented at all.** `security.php` has no
  client, nothing generates keys, nothing encrypts or decrypts, and
  `is_certified` / `message_signature` are never sent by the Flutter client even
  though `chat.php` accepts them.

For a graded project this is an integrity risk as much as a technical one: the
product tells end users a protection exists when it does not.

### 15.3 The 8-15 digit vs exactly-10-digit trap

The onboarding screen validates:

```dart
// onboarding_wizard.dart:740,746
label: 'Numero di telefono (8-15 cifre)',
if (val.trim().length < 8 || val.trim().length > 15)
    return 'Il numero deve essere di 8-15 cifre';
```

But the server requires **exactly ten digits**:

```php
// index.php:33,37
return is_string($value) && preg_match('/^\d{10}$/', $value) === 1;
```

and `UserProfile`'s constructor **throws**:

```dart
if (!isValidPhoneId(id)) {
  throw ArgumentError.value(id, 'id', 'User ID (phone) must be exactly 10 digits');
}
```

So a user who types an 8- or 11-digit number **registers successfully and is then
permanently locked out**, because the profile object cannot even be constructed. The
field label is simply wrong. This is the most likely thing a real user will hit.

### 15.4 `chat.sql` fails on a clean import

`CREATE TABLE messaggi` declares:

```sql
CONSTRAINT FK_MSG_FILE FOREIGN KEY (file_attachment_id)
    REFERENCES shared_files(id) ON DELETE SET NULL
```

but `shared_files` is not created until roughly 18 lines later. MySQL rejects a
foreign key to a non-existent table (errno 150), so the very first setup step
fails.

This also forces `messaggi` to be created before `shared_files`, which is why the
back-reference `shared_files.message_id → messaggi.id` is a *circular* dependency:
the two tables must be created in an order that one of the two constraints always
violates. The fix is either to create `shared_files` first with the
`message_id` column added afterwards via `ALTER TABLE`, or to drop one of the two
constraints.

Additionally, `chat.sql` is **out of sync with the code**: `messaggi.status` and the
entire `chat_typing_status` table exist only as "self-healing" `ALTER`/`CREATE`
statements inside `db.php`, run on every request. Importing `chat.sql` alone yields
a schema the app cannot use until a request repairs it.

### 15.5 Android desugaring is missing

`flutter_local_notifications` 17.x requires core library desugaring, but
`android/app/build.gradle.kts` has no `isCoreLibraryDesugaringEnabled` and no
desugaring dependency (zero matches). Any code path touching the plugin would fail
to build. Currently masked, because nothing calls it — remove the dead service and
this becomes a build break.

### 15.6 Missing platform permissions

| Platform | Missing |
|---|---|
| Android | `RECORD_AUDIO` (voice bio), `POST_NOTIFICATIONS` (Android 13+), `VIBRATE` |
| iOS | `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription` |
| macOS | `NSMicrophoneUsageDescription`; `Release.entitlements` lacks `com.apple.security.network.client` |

The voice-bio feature **will not work on Android or iOS as shipped**.

---

## 16. Not implemented

- **Group member management** — add, remove, leave, promote. `chat_members.role` is
  written but never read for authorisation
- **Group avatars**, despite `chat.avatar_url` existing in the schema
- **Unread badges** and per-chat unread counts
- **Real audio messages** — the mic button toggles a `recording` *status*; it never
  records or sends audio from the chat input
- **Push notifications** and background fetch
- **Multi-device sync** of the chat list beyond the local Hive cache
- **Link unfurling** — `preview_type = 'link'` carries only
  `{title, mime_type, url, host}`, with no description or thumbnail, contrary to the
  plan
- No LICENSE, no CI, no screenshots, no architecture diagram, no API docs
- `flutter_highlight` was in the plan; instead a hand-rolled regex highlighter was
  written in `IdeCodeHighlightCanvas`

---

## 17. Legacy planning docs

### 17.1 `gemini.md` (163 lines, Italian)

A 7-milestone implementation plan mapping `todo.md` onto DB + PHP + Flutter. It is a
**useful design artifact but is not documentation and is partially superseded**:

- The "Stato attuale riassunto" section describes the code **at planning time**
  (5 tables, no groups, static `ChatApi`, no notifications). That snapshot is now
  substantially obsolete: groups, files and profiles are all implemented, and
  `ChatApi` is an injectable instance.
- Milestones 1–7 map cleanly onto what was built, and its security requirement —
  *"upload must validate MIME type and block dangerous extensions"* — is **still
  not implemented** (§15.1).
- It ends with *"Alcune modifiche sono gia state implementate."*

### 17.2 `todo.md` (one line, Italian)

The **verbatim original user request**, listing the 9 macro-features. It has no
checkboxes, so the state of the TODO can only be inferred from the code:

| # | Requested | State |
|---|---|---|
| 1 | Modernise the login page | **Done** — via `onboarding_wizard.dart` (5 steps, custom wipe transitions) |
| 2 | Graphical errors on failed requests | **Done** — `api_exception_handler.dart`; shimmer only partially wired |
| 3 | Attach any file type, incl. DB changes | **Done**, except the plan's own security requirement and the 50 MB ceiling |
| 4 | Previews for audio / documents / code / video / photos / sites | **Done** — all six kinds, plus generic |
| 5 | Per-device chat customisation, defaulting to the first-launch theme | **Done** — `chat_settings_<chatId>`, `useDefaultTheme` inherits from `AppPreferences` |
| 6 | Chat background images | **Done** at three levels: app-wide, per-chat, and URL |
| 7 | Notifications, vibration, custom ringtones | **Partial** — vibration implemented but only inside the unused service; ringtone *selection* persisted but never played; no notifications at all. **Effectively unreachable** |
| 8 | Group chat, incl. DB level | **Mostly done** — schema, PHP and UI exist; member management and group info panel missing |
| 9 | Profile photo, written bio, voice bio, incl. DB | **Done** — with the 5 s cap enforced identically in the model, the UI, `auth.php` and `settings.php` |

**Items 1–6, 8 and 9 are complete. Item 7 is incomplete. Item 3 is complete except
for its own stated security requirement.**

### 17.3 Work in neither document

Beyond the 9 requests, the codebase contains substantial work that appears in
**neither** `todo.md` nor `gemini.md` — and it is the most impressive part of the
project:

- On-device ML Kit translation canonicalised to English
- The mDNS + HTTP LAN P2P mesh with an embedded HTTP server
- The Hive offline queue and the message-merging/diff algorithm
- HMAC request signing
- The `serve_file` endpoint and the `chat_typing_status` table
- The E2EE / 2FA / PEC schema surface
- The archive feature, the syntax-highlight widget, the ripple transitions
- `serve_file`'s preview-type taxonomy (`resolve_preview_type`, 7 kinds)

**The original README mentions none of this.** It is the single biggest missed
opportunity in the project's own documentation, and fixing it was the main goal of
this rewrite.

---

## 18. README vs code

Discrepancies found in the previous README (42 lines), now corrected above.

| Claim | Reality |
|---|---|
| "**Crimson Chat**" | The shipped app is **Quice**: `app.dart`, `AndroidManifest.xml`, `Info.plist`, `web/index.html`, the splash title, all onboarding copy. "Crimson Chat" survives only in legacy DB comments, the HMAC key id and Hive box paths |
| "formerly ClassChat" | No occurrence anywhere in the repository |
| "import `chat_migrations_v2.sql`" | The file is `chat_migration_v2.sql` — **singular**. The name in the README does not exist |
| "`/build/` — pre-compiled assets and **deployment scripts**" | A generated Windows CMake tree. No deployment scripts |
| "**Real-time** messaging" | Three overlapping mechanisms, of which only the 8 s HTTP poll works (§8) |
| "custom **notification sounds**" | `NotificationService` is entirely unreferenced. The ringtone picker saves a path nothing plays |
| "voice bios" | Implemented, but **silently capped at 5.0 s** — and the screen says so while the README does not |
| "PHP **RESTful API Router**" | Not REST. A front controller with a hand-rolled `switch`, dual-routed, mutated by a body field |
| "Run on an emulator or physical device" | Also targets Windows, Linux, macOS and Web, with a **Windows-desktop-first** workflow |
| "`php -S 0.0.0.0:8000`" | Works only via the `?route=` fallback; media URLs are built through `?route=serve_file`, which needs the `.htaccess` rewrite, i.e. Apache |
| "Ensure `/uploads` has write permissions" | True but insufficient — `uploads/` has no `.htaccess` and no extension validation (§15.1) |
| "Hive for local config" | Hive is the **offline message queue**; config is SharedPreferences |
| "MySQL" | Correct, but the README never mentions `chatProject`, the `root`/empty-password credentials, or the 6 `ALTER TABLE`s per request |
| Missing | The HMAC secret in the binary, `CRIMSON_CHAT_ADMIN_BYPASS_PASSWORD`, the base-URL being hardcoded |

---

## 19. Appendix

### 19.1 Reference values

| Value | Where |
|---|---|
| Database name | `chatProject` (`db.php:3`, `chat.sql:2`) |
| Seed users / password | `3391234567`, `3391234568`, `3391234569` / `password` |
| User ID | Phone number, **exactly 10 digits** |
| Voice bio cap | 5.0 s, enforced in 4 places |
| Upload cap | 50 MB + `CRIMSON_CHAT_ADMIN_BYPASS_PASSWORD` |
| HMAC app key id | `crimson-chat-v1` |
| Signature skew window | 300 s |
| mDNS service | `cp-<userId>`, type `_cpchat._tcp` |
| P2P path | `POST /p2p/message` |
| WebSocket port | 8080 |
| Polling cadence | 8 s ⇄ 2 s |
| Translation canonical | English |
| Per-chat settings key | `chat_settings_<chatId>` |
| Timeouts | 10 s REST, 30 s multipart, 4 s typing |

### 19.2 Glossary

| Term | Meaning here |
|---|---|
| **Aria LAN** | A local network with no route to the internet |
| **mDNS / Bonjour** | Service discovery that lets devices find each other on a LAN without a server |
| **Hive** | A lightweight key-value store; here it holds the offline message queue |
| **Canonical language** | The language all stored messages are translated into — here English |
| **ML Kit** | Google's on-device translation library; Android and iOS only |
| **HMAC** | A keyed hash; here it signs each request to prove it came from the app |
| **Multipart** | The `multipart/form-data` encoding used for file uploads |
| **PDO** | PHP's database access layer; used with prepared statements |
| **bcrypt** | A deliberately slow password hash, used here via `password_hash` |
| **X25519 / XSalsa20-Poly1305** | The key agreement and authenticated encryption libsodium would use for the E2EE scaffolding |
| **Dismissible** | Flutter's swipe-to-dismiss widget, used for archive-on-swipe |
| **`d:q` type** | The format of a `Duration` literal in Dart, e.g. `1:30` |
| **Glassmorphism** | Frosted, translucent UI surfaces; here via `BackdropFilter` |
| **O(n²)** | Quadratic cost; the old evaluator was O(n²), the new one O(n) |

### 19.3 What cannot be determined from the code

- Whether `1cdc-93-71-139-206.ngrok-free.app` is still reachable or is a dead
  tunnel from a previous session
- Whether the committed PHP file in `uploads/` was uploaded by the author or by
  someone with access to the database
- Whether the deliberately automatic threefold/50-move rules were intended
  deviations or oversights — no comments or issue tracker address it
- Why the project is called `projectCapolavoro` in the repository but "Quice" in the
  product; a comment in `projects/page.tsx` of the portfolio site says the repo was
  renamed and the canonical lowercase URL was chosen deliberately

### 19.4 Method

Direct reading of `pubspec.yaml`/`pubspec.lock`, all 27 Dart files under `lib/`, all
PHP resources, `index.php`, `db.php`, both SQL files, the Python module, the test
suites, and both planning documents; line counts; targeted greps for call sites when
asserting dead code, for the canonical signing string on both the PHP and Dart
sides, and for the preconditions of the import-failure, test-failure and
phone-length claims. The PHP file in `uploads/` was read in full. Line counts and
all bug claims were re-verified immediately before this document was written, since
other agents were editing the repository during the investigation.
