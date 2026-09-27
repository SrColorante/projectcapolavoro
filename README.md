# 👑 Crimson Chat (Project Capolavoro)

![Crimson Chat Banner](https://images.unsplash.com/photo-1611162617474-5b21e879e113?q=80&w=1200&auto=format&fit=crop)

**Crimson Chat** (formerly ClassChat) is a high-performance, locally hosted communication platform designed specifically for IT Labs and strict LAN environments. Built with a modern **Flutter** frontend and a robust **PHP/MySQL** backend.

## 🚀 Features

- **Real-time Messaging**: Lightning-fast 1-to-1 and group chat architecture.
- **Media Rich**: Support for audio messages, documents, code snippets, and image sharing with in-app previews.
- **Advanced Profiles**: Customizable profiles including bio, profile pictures, and voice bios.
- **Personalized UI**: Device-specific theming, chat backgrounds, and custom notification sounds.
- **Self-Hosted Security**: Designed to run entirely on a local LAN server (PHP + MySQL), ensuring maximum data privacy for schools, labs, and private organizations.

## 🛠 Tech Stack

- **Frontend:** Flutter & Dart (Material 3 UI, Hive/SharedPreferences for local config)
- **Backend:** PHP (RESTful API Router)
- **Database:** MySQL
- **Assets:** Custom glassmorphism UI elements & fluid animations

## 📦 Project Structure

- `/flutterapp/` - The complete cross-platform Flutter application.
- `/webService/` - The PHP backend handling authentication, chats, files, and routing.
- `/build/` - Pre-compiled assets and deployment scripts.

## ⚙️ Quick Start (Backend)

1. Import `chat.sql` and `chat_migrations_v2.sql` into your MySQL server.
2. Serve the `/webService` directory using Apache or NGINX (e.g., `php -S 0.0.0.0:8000`).
3. Ensure `/uploads` has write permissions for media sharing.

## 📱 Quick Start (Flutter)

1. Open `/flutterapp` in Android Studio or VS Code.
2. Run `flutter pub get`.
3. Update the API Base URL in the networking module to point to your local PHP server.
4. Run on an emulator or physical device.

---
*Created by SrColorante - Digital Craftsmanship*
