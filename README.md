# MindBridge

Mental health check-in and counsellor booking app for university students (IT3060 HCI, Group WD_02).
Built from the **MindBridge App v3** hi-fi design and the Milestone 01/02 requirements.

| Part | Folder | Stack |
|---|---|---|
| Mobile app | [`frontend/`](frontend) | Flutter 3.44 (Android, iOS, web), Provider, Material Symbols, bundled Nunito + Lora |
| REST API | [`backend/`](backend) | Node.js 22, Express 5, Mongoose 9, Zod, JWT |
| Database | — | MongoDB 8 (local service, Docker or Atlas) |

Four roles share one app and one secure login: **Student**, **Counsellor**, **Doctor** (University Medical Centre) and **Admin** (Student Affairs).

---

## 1. Run it

### Prerequisites
- Node.js 20+ and npm
- Flutter 3.44+ (`flutter doctor` should be clean for your target)
- MongoDB running on `mongodb://127.0.0.1:27017` — or skip it and use the in-memory option below

### Backend
```bash
cd backend
npm install
npm run seed       # loads demo data (dates are relative to today)
npm start          # http://localhost:4000/api
```
`backend/.env` holds the secrets (already generated). See `.env.example` for every option.

No MongoDB installed? `npm run dev:memory` starts the API on a throw-away in-memory database with the demo data already loaded.

### Mobile app
```bash
cd frontend
flutter pub get
flutter run                     # Android emulator, iOS simulator or Chrome
```
The app finds the API automatically: `10.0.2.2:4000` on the Android emulator, `localhost:4000` on iOS simulator and web.
On a **physical phone**, use your computer's LAN IP and allow it in `android/app/src/main/res/xml/network_security_config.xml`:
```bash
flutter run --dart-define=API_URL=http://192.168.1.20:4000/api
```

### Build the APK on Windows (one step)
From the project folder in PowerShell: `powershell -ExecutionPolicy Bypass -File .\build-apk.ps1`. It pulls the latest `main`, deletes old APKs, builds a release APK and saves it as `MindBridge.apk` in the project folder.

### Download the APK (built by GitHub)
Every push to `main` that changes `frontend/` builds a release APK on GitHub (`.github/workflows/build-apk.yml`). Open the repository's **Releases** page on your phone and download the newest `MindBridge-build-N.apk`. You can also start a build by hand: **Actions → Build Android APK → Run workflow**.
The APK is signed with a demo key (`frontend/android/ci/`) unless the repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` hold your own release key. Phones only install an update over an app signed with the same key, so uninstall a copy built on another computer first.

### Run from VS Code on the Android Studio emulator
1. Open the `MindBridge` folder in VS Code (Dart and Flutter extensions installed).
2. Start the emulator: `Ctrl+Shift+P` → **Flutter: Launch Emulator** → `Pixel_9_Pro_XL`.
3. Make sure the MongoDB service is running (it starts with Windows).
4. Open **Run and Debug** (`Ctrl+Shift+D`), pick **MindBridge: API + App** and press **F5**.
   This starts the backend and installs the app on the emulator. Save a Dart file to hot reload.

The emulator reaches your computer's API at `10.0.2.2:4000` automatically. In debug builds the login screen has a **Fill demo account** link.

### Demo accounts (password `password123` for all)
| Role | Email | Notes |
|---|---|---|
| Student | `it23714052@my.sliit.lk` | Pasindi Perera — has a pending booking, mood history and journal |
| Counsellor | `hasini.k@sliit.lk` | Dr. Hasini Kalupahana — requests, today's sessions, a duplicate to resolve |
| Doctor | `ruwan.d@sliit.lk` | Dr. Ruwan Dissanayake — a priority referral and consultations |
| Admin | `mindbrige.support@gmail.com` | Malsha Gunawardena — uses a sign-in code (two-factor) |

Without SMTP configured, one-time codes (email verification, password reset, admin sign-in) are printed in the API console **and shown inside the app** in a "Development mode" banner. Set `SMTP_*` in `.env` to send real emails; codes are never exposed when `NODE_ENV=production`.

Optional: set `ANTHROPIC_API_KEY` to power the **Bridge** assistant with Claude. Without it Bridge uses built-in supportive replies. Crisis detection and the 1926 hand-off work either way.

---

## 2. Tests
```bash
cd backend && npm test
# 13 end-to-end suites across all roles, on an isolated in-memory database

cd frontend && flutter analyze
# static analysis, no issues

cd frontend && flutter test
# renders all 125 screens against the running, seeded API and fails on any exception or layout overflow
# small phones: flutter test --dart-define=W=360 --dart-define=H=740
```

---

## 3. How the requirements are met

| ID | Requirement | Where |
|---|---|---|
| FR1 | Register and log in securely | `routes/auth.js` + `modules/user/signup.routes.js` (university-domain emails, 6-digit verification, reset, admin 2FA), `features/auth/*`, `modules/user/register.dart` |
| FR2 | Search counsellors, real-time availability | `services/slots.js` builds slots from working hours − breaks − blocks − bookings; `features/student/counsellors.dart`, `modules/appointment/booking.dart` |
| FR3 | Book, reschedule, cancel; reschedule clearly labelled | 4-step booking, full-width **Reschedule** button, counsellor proposals the student accepts (`modules/appointment/`) |
| FR4 | Status at every stage | One server-generated timeline shown to both sides (`services/appointments.js`) |
| FR5 | Automatic reminders | `services/scheduler.js`: 24 h and 1 h before; in-app notifications with unread badge |
| FR6 | Counsellor dashboard | `features/counsellor/*`, `modules/appointment/` (requests, calendar), `modules/availability/`, `modules/counselling_session/` (sessions, notes) |
| FR7 | Detect duplicate bookings | Server blocks a second active booking (configurable). A unique index prevents two students taking one slot. Counsellors get a duplicate view. |
| FR8 | One-tap 1926 helpline | SOS on Home and Wellness, press-and-hold for 5 s, dialler confirmation (`features/wellness/emergency.dart`) |
| FR9 | Optional mood check-in | Check-in, calendar, history, insights, encrypted journal (`modules/mood/`, `routes/journal.js`) |
| FR10 | AI wellness assistant with escalation | `services/bridge.js`: Claude with offline fallback; crisis messages never reach the model and switch to 1926 |
| FR11 | Admin verifies counsellors/doctors | Document upload, checklist, approve, reject, request changes; unverified staff are gated (`requireVerified`) |
| FR12 | Anonymised reporting | `routes/reports.js`: every group under 10 is hidden; CSV/PDF export through one-time links |
| NFR1 | Privacy | Role-based access on every route. Counsellors see bookings only; mood is shared only if the student opts in. Doctors see only what was shared. Admins never see content. |
| NFR2 | Confidentiality | AES-256-GCM encryption at rest for session notes, clinical notes, journal, mood notes, booking notes and Bridge chats. Referral views are audited. |
| NFR3 | Usability | Onboarding, step indicators, plain-language states and errors; design from the tested hi-fi prototype |
| NFR4 | Security | bcrypt, JWT plus server-side sessions (revocable), inactivity sign-out (admin-configurable, mirrored on device), rate limiting, Helmet, input validation, NoSQL-injection stripping, no tokens in URLs, nothing stored on the device (the token is kept in memory only) |
| NFR5 | Consistent status | Single source of truth for status and timeline; retries on network errors; offline states |
| NFR6 | Fast check-in and booking | Check-in in about 3 taps; booking in 4 steps or 2 via a profile quick slot |

---

## 4. Project structure
The 8 team CRUD features each live in their own folder. **[TEAM_MODULES.md](TEAM_MODULES.md)** lists which member owns which files and endpoints.

```
backend/
  src/
    app.js, server.js        Express app, error format { error: { code, message } }
    config/                  env + MongoDB connection
    models/                  User, Appointment and shared models (journal, consultations, settings…)
    modules/                 one folder per team CRUD feature (see TEAM_MODULES.md):
                             appointment, availability, user, counsellor-approval,
                             mood, counselling-session, article, referral
    routes/                  shared routes: auth, me, counsellors, staff dashboard, journal,
                             notifications, wellness, doctor, admin dashboard, reports, downloads
    services/                slots, scheduler, bridge (AI), notify/audit, settings, otp, mail
    seed/                    demo data
  test/e2e.test.js
frontend/
  lib/
    core/                    api client, theme tokens, formatting (Sri Lanka time), icons
    state/                   auth/session, notifications badge, music player
    widgets/                 design system: page, blocks, charts, sheets, tab shell
    modules/                 one folder per team CRUD feature (see TEAM_MODULES.md):
                             appointment, availability, user, counsellor_approval,
                             mood, counselling_session, article, referral
    features/
      auth/                  onboarding, login, codes, reset
      student/               home, counsellors, journal, profile
      wellness/              hub, breathing, games, music, Bridge, emergency
      counsellor/            dashboard, profile
      doctor/                dashboard, consultations, students, profile
      admin/                 dashboard, moderation, reports, system
  test/screens_smoke_test.dart
  tool/gen_icons.mjs         regenerates lib/core/icons.dart (run after adding icon names)
  tool/icon/                 app icon source (SVG) + render_icons.cjs, which writes every Android/iOS/web icon size
```

## 5. Notes and limits
- **File storage:** set `CLOUDINARY_URL` in `backend/.env` to store uploads in Cloudinary. Credential documents are private Cloudinary files that only the API can fetch. Images and audio use public CDN links through `saveMedia()` in `services/storage.js`. Without it, documents are kept in MongoDB (GridFS). Nothing is stored on the phone: the sign-in token is kept in memory, so closing the app signs the user out.
- **Video sessions:** these open a private Jitsi Meet room generated per booking. **Music:** Student Affairs uploads MP3/M4A tracks (System → Relaxing music). They are stored in Cloudinary and streamed with `just_audio`. The 8 seeded demo tracks have no audio and play as timed demos.
- **Notifications:** these are in-app. Real push (FCM/APNs) needs a Firebase project.
- **Biometric unlock:** the preference is saved, but the device prompt isn't wired up yet.
- **Production:** set `NODE_ENV=production`, real `JWT_SECRET` and `DATA_ENCRYPTION_KEY`, SMTP and HTTPS. Restrict `CORS_ORIGINS`.
