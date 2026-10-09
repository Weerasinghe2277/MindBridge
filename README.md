# MindBridge

**MindBridge** is a mental-health check-in and counsellor booking app for university students, built for **IT3060 Human Computer Interaction (Group WD_02)**.

Students can book a university counsellor in a few taps, check in on their mood, keep a private journal, use calming wellness tools and talk to **Bridge**, an AI wellness assistant. Counsellors manage their availability, requests and sessions, refer students to the University Medical Centre, and write wellness articles. Student Affairs verifies staff, moderates articles and sees anonymised reports. Help is never far away: the **1926 National Mental Health Helpline** is one tap away on every student screen.

One app and one secure sign-in serve four roles: **Student**, **Counsellor**, **Doctor** (University Medical Centre) and **Admin** (Student Affairs).

| Part | Folder | Built with |
|---|---|---|
| Mobile app | [`frontend/`](frontend) | Flutter 3.47 (Android, iOS, web), Provider, Material Symbols, bundled Nunito and Lora fonts |
| REST API | [`backend/`](backend) | Node.js 22, Express 5, Mongoose 9, Zod, JWT |
| Database | — | MongoDB (local, in-memory for development, or MongoDB Atlas) |
| Hosting | [`render.yaml`](render.yaml) | Render web service (Blueprint) |
| AI assistant | [`backend/src/services/bridge.js`](backend/src/services/bridge.js) | Google Gemini |
| File storage | [`backend/src/services/storage.js`](backend/src/services/storage.js) | Cloudinary (or MongoDB GridFS) |

---

## Download the app

📱 **[Download the MindBridge Android APK (Google Drive)](https://drive.google.com/drive/folders/1tGnmtKW6VEuSMwBBpnhvVYW8b4lyU3cR?usp=sharing)**

1. Open the link on your Android phone and download the `.apk` file.
2. Open the downloaded file. If Android asks, allow **Install unknown apps** for your browser or Files app.
3. Open **MindBridge**. It connects to the hosted server, so nothing else needs to run.

The server sleeps when nobody uses it, so the first screen can take up to about a minute to load. If an older MindBridge is already installed and the install fails, uninstall it first.

---

## Team and responsibilities

Each member owns two features, each a full CRUD module with its own backend routes and app screens.

| Member | Function | Create | Read | Update | Delete |
|---|---|---|---|---|---|
| **Weerasinghe** | **Appointment Management** (CRUD 1) | Book a session in 4 steps (counsellor, date, time, meeting type), with an optional anonymous online booking | View upcoming, past and today's appointments, details and a shared status timeline | Reschedule, accept / decline requests, propose a new time, update status, reminders on/off | Cancel a booking (student or counsellor) |
| **Weerasinghe** | **Availability Management** (CRUD 2) | Add working hours and blocked time slots | View the weekly schedule, day view and open slots | Edit hours, session length, buffers and breaks | Remove a blocked slot |
| **Jayodya** | **Mood Check-in Management** (CRUD 1) | Submit a mood check-in (mood, feelings, note) | View mood history, calendar and insights | — | Delete a mood entry |
| **Jayodya** | **Counselling Session Management** (CRUD 2) | Start a session record from a confirmed booking | View the session, the student's limited profile and notes | Update the session checklist and encrypted session notes | Complete the session (or mark no-show) |
| **Dinith** | **User Management** (CRUD 1) | Sign up with a university email and 6-digit verification | View and search users (admin) | Edit a user's role, send a password reset | Deactivate / reactivate a user |
| **Dinith** | **Counsellor Approval** (CRUD 2) | Counsellor / doctor application with credential documents | View pending applications and documents | Approve, request changes, check documents | Reject or deactivate an applicant |
| **Sadeepa** | **Article Management** (CRUD 1) | Write an article with a category and cover photo | View articles, article details and categories | Edit, submit for review, change or adjust the cover | Delete a draft article |
| **Sadeepa** | **Doctor Referral Management** (CRUD 2) | Refer a student to a doctor (with recorded consent) | View referrals, details and status tracking | Accept / decline, request or add information, book a consultation | — |

### Where each feature lives

| Feature | Backend | App screens |
|---|---|---|
| Appointment Management | `backend/src/modules/appointment/` → `/api/appointments` | `frontend/lib/modules/appointment/` |
| Availability Management | `backend/src/modules/availability/` → `/api/staff/availability` | `frontend/lib/modules/availability/` |
| Mood Check-in Management | `backend/src/modules/mood/` → `/api/mood` | `frontend/lib/modules/mood/` |
| Counselling Session Management | `backend/src/modules/counselling-session/` → `/api/appointments/:id/session`, `/notes`, `/complete` | `frontend/lib/modules/counselling_session/` |
| User Management | `backend/src/modules/user/` → `/api/auth/register`, `/api/admin/users` | `frontend/lib/modules/user/` |
| Counsellor Approval | `backend/src/modules/counsellor-approval/` → `/api/me/documents`, `/api/admin/verifications` | `frontend/lib/modules/counsellor_approval/` |
| Article Management | `backend/src/modules/article/` → `/api/articles` | `frontend/lib/modules/article/` |
| Doctor Referral Management | `backend/src/modules/referral/` → `/api/referrals` | `frontend/lib/modules/referral/` |

---

## What you can do with MindBridge

### Students
- **Find and book a counsellor:** search by focus area, language, gender and meeting type, see real-time free slots, and book in 4 steps (or 2 from a quick slot).
- **Anonymous online sessions:** book without sharing your name, student ID or history with the counsellor.
- **Track every booking:** one clear status timeline (pending → confirmed → session), reschedule or cancel, accept a counsellor's proposed time, and get reminders 24 h and 1 h before.
- **Join online sessions** through a private video room created for each booking.
- **Mood check-ins** in about 3 taps, with a calendar, history and insights, plus a private **encrypted journal**.
- **Wellness hub:** guided breathing (box, 4-7-8, quick reset, breathing bubble) with **vibration cues** for eyes-closed breathing, calming games, relaxing music and wellness articles.
- **Bridge, the AI wellness assistant** (Google Gemini): a warm, short, supportive chat. Messages about self-harm never go to the AI; they show the 1926 helpline at once.
- **1926 helpline** on every student screen, with press-and-hold to call.
- **Privacy controls:** choose whether to share mood trends with your counsellor, hide notification previews, see signed-in devices, download your data or delete your account.

### Counsellors
- **Dashboard** with today's sessions, new requests and duplicate-booking alerts.
- **Accept, decline or propose a new time**, with suggested free slots.
- **Availability:** working hours, session length, breaks and blocked time.
- **Run sessions:** checklist, encrypted session notes, goals, and completing the session.
- **Refer students** to the University Medical Centre with recorded consent.
- **Write wellness articles** with a cover photo, sent to Student Affairs for review.
- **Profile photo** with a built-in editor to move, resize and preview the picture.

### Doctors (University Medical Centre)
- See **referrals** from counsellors, accept or decline them, ask for more information and **book consultations**.
- Record consultations and follow-ups; share a short summary with the counsellor.
- Consultation hours and a **profile photo**.

### Admin (Student Affairs)
- **Verify counsellors and doctors:** review credential documents, approve, reject or request changes.
- **Manage users:** search, change roles, deactivate or reactivate accounts, send password resets.
- **Moderate articles** before students can see them.
- **Anonymised reports** (groups under 10 people are hidden) with CSV/PDF export.
- **System settings:** booking rules, notifications, privacy and security (auto sign-out time, two-factor sign-in for staff), relaxing-music library and an activity log.
- Admins always sign in with a one-time email code (two-factor).

### Everyone
- **Quick unlock:** after turning it on, sign in again with fingerprint, face, pattern or PIN instead of a password. After inactivity the app locks instead of signing out.
- **In-app notifications** with an unread badge.
- **Onboarding** shown once on first launch.

---

## Setup and run

### Prerequisites
- **Node.js 20+** and npm
- **Flutter 3.47+** (run `flutter doctor` and fix anything it reports for your target)
- **Android Studio** with an Android emulator (or a phone with USB debugging)
- **MongoDB:** a MongoDB Atlas database, a local MongoDB, or none at all (use the in-memory option below)

### 1. Get the code
```bash
git clone https://github.com/Weerasinghe2277/MindBridge.git
cd MindBridge
```

### 2. Configure the backend
Create `backend/.env` (it is git-ignored, so secrets never go to GitHub):

| Variable | Needed | What it is |
|---|---|---|
| `NODE_ENV` | yes | `development` locally, `production` on a server |
| `PORT` | no | API port (default `4000`) |
| `MONGO_URI` | yes* | MongoDB connection string (*not needed with the in-memory database) |
| `JWT_SECRET` | production | Secret for sign-in tokens (generated automatically in development) |
| `DATA_ENCRYPTION_KEY` | production | 64 hex characters; encrypts journals, notes and chats. **Keep the same value everywhere** that uses the same database |
| `JWT_EXPIRES_IN` | no | Token lifetime, e.g. `12h` |
| `CORS_ORIGINS` | no | Allowed web origins (`*` for any) |
| `STUDENT_EMAIL_DOMAINS` / `STAFF_EMAIL_DOMAINS` | no | Allowed sign-up email domains (`my.sliit.lk` / `sliit.lk`) |
| `GEMINI_API_KEY` | no | Google AI Studio key for the Bridge assistant. Without it, Bridge uses built-in supportive replies |
| `BRIDGE_MODEL` / `BRIDGE_FALLBACK_MODEL` | no | Gemini models (default `gemini-flash-latest`, backup `gemini-flash-lite-latest`) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | no | Email for one-time codes (e.g. Gmail with an app password) |
| `CLOUDINARY_URL` | no | `cloudinary://<api_key>:<api_secret>@<cloud_name>` for photos, covers, music and documents |
| `DEMO_MODE` | no | `true` shows one-time codes inside the app (coursework demos only) |
| `SEED_IF_EMPTY` | no | `true` loads demo data on first start when the database is empty |

Without SMTP in development, one-time codes (email verification, password reset, admin sign-in) are printed in the API console and shown in the app in a "Development mode" banner. They are never shown when `NODE_ENV=production` unless `DEMO_MODE=true`.

### 3. Run the backend
```bash
cd backend
npm install
npm run seed        # optional: load demo data (dates are relative to today)
npm start           # http://localhost:4000/api
```
No MongoDB? `npm run dev:memory` starts the API on a temporary in-memory database with demo data already loaded (it resets when stopped).

Check it works: open `http://localhost:4000/api/health`. You should see `{"ok":true,"db":true}`.

### 4. Run the app on the Android emulator
Keep the backend running, start an emulator from Android Studio (**Device Manager → ▶**), then:
```bash
cd frontend
flutter pub get
flutter run
```
Or open `frontend/lib/main.dart` in VS Code and press **F5**.

The app finds the API by itself:

| Where it runs | API address |
|---|---|
| Android emulator (debug) | `http://10.0.2.2:4000/api` |
| iOS simulator / web (debug) | `http://localhost:4000/api` |
| Release build (APK) | the hosted Render server (`productionApiUrl` in `frontend/lib/core/config.dart`) |
| Physical phone (debug) | `flutter run --dart-define=API_URL=http://<your-PC-LAN-IP>:4000/api` and add that IP to `frontend/android/app/src/main/res/xml/network_security_config.xml` |

While running: `r` hot reloads, `R` restarts, `q` quits. After adding a package or changing Android files, stop the app and run it again.

### 5. Build the Android APK
```bash
cd frontend
flutter build apk --release
```
The APK is saved at `frontend/build/app/outputs/flutter-apk/app-release.apk`. Drag it onto the emulator window, or copy it to a phone and open it to install. Release builds connect to the hosted server.

To just use the app without building it, download the ready-made APK from the [Google Drive folder](https://drive.google.com/drive/folders/1tGnmtKW6VEuSMwBBpnhvVYW8b4lyU3cR?usp=sharing).

---

## Deploy the backend to Render

The repository includes a Render Blueprint ([`render.yaml`](render.yaml)).

1. In **MongoDB Atlas → Network Access**, allow access from anywhere (`0.0.0.0/0`); Render has no fixed IP address.
2. In Render, create a project, then **New → Blueprint** and pick this repository and the `main` branch.
3. Fill in the secret values when asked: `MONGO_URI`, `DATA_ENCRYPTION_KEY` (same as your `.env`), and optionally `GEMINI_API_KEY`, `CLOUDINARY_URL`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`.
4. When the service is **Live**, open `https://<your-service>.onrender.com/api/health`.
5. Put the address in `productionApiUrl` in `frontend/lib/core/config.dart` and build a new APK.

Every merge to `main` redeploys automatically. Free Render services sleep after 15 minutes without use, so the first request afterwards can take about 50 seconds; the app waits for it.

---

## Tests
```bash
cd backend
npm test
# 16 end-to-end tests across all roles, on an isolated in-memory database
```
```bash
cd frontend
flutter analyze
# static analysis
```
```bash
cd frontend
flutter test
# renders every major screen (128 checks) against a running, seeded API at localhost:4000
# and fails on any exception or layout overflow. Small phones: --dart-define=W=360 --dart-define=H=740
```
Run the screen tests against a local demo API (`npm run dev:memory`), not your real database.

---

## How the requirements are met

| ID | Requirement | Where |
|---|---|---|
| FR1 | Register and log in securely | `routes/auth.js` + `modules/user/signup.routes.js` (university-domain emails, 6-digit verification, reset, admin two-factor), `features/auth/*`, `modules/user/register.dart` |
| FR2 | Search counsellors, real-time availability | `services/slots.js` builds slots from working hours − breaks − blocks − bookings; `features/student/counsellors.dart`, `modules/appointment/booking.dart` |
| FR3 | Book, reschedule, cancel; reschedule clearly labelled | 4-step booking, full-width **Reschedule** button, counsellor proposals the student accepts (`modules/appointment/`) |
| FR4 | Status at every stage | One server-generated timeline shown to both sides (`services/appointments.js`) |
| FR5 | Automatic reminders | `services/scheduler.js`: 24 h and 1 h before; in-app notifications with unread badge |
| FR6 | Counsellor dashboard | `features/counsellor/*`, `modules/appointment/` (requests, calendar), `modules/availability/`, `modules/counselling_session/` (sessions, notes) |
| FR7 | Detect duplicate bookings | Server blocks a second active booking (configurable). A unique index prevents two students taking one slot. Counsellors get a duplicate view. |
| FR8 | One-tap 1926 helpline | SOS on Home and Wellness, press-and-hold for 5 s, dialler confirmation (`features/wellness/emergency.dart`) |
| FR9 | Optional mood check-in | Check-in, calendar, history, insights, encrypted journal (`modules/mood/`, `routes/journal.js`) |
| FR10 | AI wellness assistant with escalation | `services/bridge.js`: Google Gemini with a backup model and offline replies; crisis messages never reach the model and switch to 1926 |
| FR11 | Admin verifies counsellors/doctors | Document upload, checklist, approve, reject, request changes; unverified staff are gated (`requireVerified`) |
| FR12 | Anonymised reporting | `routes/reports.js`: every group under 10 is hidden; CSV/PDF export through one-time links |
| NFR1 | Privacy | Role-based access on every route. Counsellors see bookings only; mood is shared only if the student opts in; anonymous bookings hide the student entirely. Doctors see only what was shared. Admins never see content. |
| NFR2 | Confidentiality | AES-256-GCM encryption at rest for session notes, clinical notes, journal, mood notes, booking notes and Bridge chats. Referral views are audited. |
| NFR3 | Usability | Onboarding, step indicators, plain-language states and errors; design from the tested hi-fi prototype |
| NFR4 | Security | bcrypt, JWT plus server-side sessions (revocable), inactivity sign-out (admin-configurable; with quick unlock on, the app locks instead), rate limiting, Helmet, input validation, NoSQL-injection stripping, no tokens in URLs. The sign-in token lives in memory only; the phone keeps just the onboarding flag and, if turned on, a quick-unlock key in secure storage released only after fingerprint, face, pattern or PIN |
| NFR5 | Consistent status | Single source of truth for status and timeline; retries on network errors; offline states |
| NFR6 | Fast check-in and booking | Check-in in about 3 taps; booking in 4 steps or 2 via a profile quick slot |

---

## Project structure
```
backend/
  src/
    app.js, server.js        Express app; errors use { error: { code, message } }
    config/                  environment and MongoDB connection
    middleware/              auth, validation, file uploads
    models/                  User, Appointment and shared models (journal, consultations, settings…)
    modules/                 one folder per team CRUD feature:
                             appointment, availability, mood, counselling-session,
                             user, counsellor-approval, article, referral
    routes/                  shared routes: auth, me, counsellors, staff dashboard, journal,
                             notifications, wellness, music, doctor, admin, reports, downloads
    services/                slots, scheduler, bridge (Gemini), notify/audit, settings, otp, mail, storage
    seed/                    demo data
  test/e2e.test.js           end-to-end API tests
frontend/
  lib/
    core/                    API client, config, theme, formatting (Sri Lanka time), icons, quick unlock
    state/                   sign-in/session, notifications badge, music player
    widgets/                 design system: pages, blocks, charts, sheets, photo editor
    modules/                 one folder per team CRUD feature:
                             appointment, availability, mood, counselling_session,
                             user, counsellor_approval, article, referral
    features/
      auth/                  onboarding, login, codes, password reset
      student/               home, counsellors, journal, profile
      wellness/              hub, breathing, games, music, Bridge, emergency
      counsellor/            dashboard, profile
      doctor/                dashboard, consultations, students, profile
      admin/                 dashboard, moderation, reports, system
      common/                account, security, profile photo
  assets/                    fonts, logo, onboarding illustrations
  test/screens_smoke_test.dart
  tool/gen_icons.mjs         regenerates lib/core/icons.dart (run after using a new icon name)
  tool/icon/                 app icon source (SVG) and render_icons.cjs
  tool/onboarding/           onboarding illustrations (SVG) and render.mjs
render.yaml                  Render Blueprint for the API
```

---

## Notes and limits
- **File storage:** with `CLOUDINARY_URL`, credential documents are private Cloudinary files that only the API can fetch, while photos, article covers and music use public CDN links. Without it, documents are kept in MongoDB (GridFS); photos, covers and music uploads need Cloudinary.
- **Video sessions** open a private Jitsi Meet room generated for each booking.
- **Music:** Student Affairs uploads MP3/M4A tracks (System → Relaxing music), streamed with `just_audio`. Seeded demo tracks have no audio and play as timed demos.
- **Notifications** are in-app. Real push notifications (FCM/APNs) need a Firebase project.
- **Email on Render's free plan** may be blocked; sign-in still works, and with `DEMO_MODE=true` the code appears in the app.
- **Production checklist:** `NODE_ENV=production`, your own `JWT_SECRET` and `DATA_ENCRYPTION_KEY`, SMTP, HTTPS, a restricted `CORS_ORIGINS`, and `DEMO_MODE` turned off before real students use MindBridge.
