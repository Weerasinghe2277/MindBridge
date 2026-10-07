// Renders every major screen at phone size (390×844 by default) against the real API and
// fails on any exception or layout overflow.
//
// Requires the API running with seed data:
//   cd backend && npm run seed && npm start
//   cd frontend && flutter test test/screens_smoke_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mindbridge/core/api.dart';
import 'package:mindbridge/core/models.dart';
import 'package:mindbridge/core/theme.dart';
import 'package:mindbridge/features/admin/admin_shell.dart';
import 'package:mindbridge/features/admin/moderation.dart';
import 'package:mindbridge/features/admin/music_admin.dart';
import 'package:mindbridge/features/admin/reports.dart';
import 'package:mindbridge/features/admin/system.dart';
import 'package:mindbridge/features/auth/login.dart';
import 'package:mindbridge/features/auth/onboarding.dart';
import 'package:mindbridge/features/counsellor/c_profile.dart';
import 'package:mindbridge/features/counsellor/counsellor_shell.dart';
import 'package:mindbridge/features/doctor/consultations.dart';
import 'package:mindbridge/features/doctor/doctor_shell.dart';
import 'package:mindbridge/features/student/counsellors.dart';
import 'package:mindbridge/features/student/home.dart';
import 'package:mindbridge/features/student/journal.dart';
import 'package:mindbridge/features/student/profile.dart';
import 'package:mindbridge/features/wellness/breathing.dart';
import 'package:mindbridge/features/wellness/bridge.dart';
import 'package:mindbridge/features/wellness/emergency.dart';
import 'package:mindbridge/features/wellness/games.dart';
import 'package:mindbridge/features/wellness/music.dart';
import 'package:mindbridge/features/wellness/wellness_home.dart';
import 'package:mindbridge/modules/appointment/appointments.dart';
import 'package:mindbridge/modules/appointment/booking.dart';
import 'package:mindbridge/modules/appointment/requests.dart';
import 'package:mindbridge/modules/appointment/schedule.dart';
import 'package:mindbridge/modules/article/articles.dart';
import 'package:mindbridge/modules/article/c_articles.dart';
import 'package:mindbridge/modules/availability/availability.dart';
import 'package:mindbridge/modules/counselling_session/sessions.dart';
import 'package:mindbridge/modules/counsellor_approval/verification.dart';
import 'package:mindbridge/modules/mood/mood.dart';
import 'package:mindbridge/modules/referral/counsellor_referrals.dart';
import 'package:mindbridge/modules/referral/referrals.dart';
import 'package:mindbridge/modules/user/register.dart';
import 'package:mindbridge/modules/user/users.dart';
import 'package:mindbridge/state/auth.dart';
import 'package:mindbridge/state/notifications.dart';
import 'package:mindbridge/state/player.dart';
import 'package:provider/provider.dart';

const base = 'http://localhost:4000/api';
// Screen size under test; e.g. --dart-define=W=360 --dart-define=H=740 for small Android phones.
const screenW = int.fromEnvironment('W', defaultValue: 390);
const screenH = int.fromEnvironment('H', defaultValue: 844);

Future<Map<String, dynamic>> raw(String method, String path, {String? token, Object? body}) async {
  final c = HttpClient();
  final req = await c.openUrl(method, Uri.parse('$base$path'));
  req.headers.contentType = ContentType.json;
  if (token != null) req.headers.set('Authorization', 'Bearer $token');
  if (body != null) req.write(jsonEncode(body));
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  c.close();
  return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> signIn(String email) async {
  var r = await raw('POST', '/auth/login', body: {'email': email, 'password': 'password123', 'device': 'smoke test'});
  if (r['twoFactor'] == true) r = await raw('POST', '/auth/login/2fa', body: {'email': email, 'code': r['devOtp'], 'device': 'smoke test'});
  return r;
}

void main() {
  final errors = <String>[];

  setUpAll(() {
    HttpOverrides.global = null; // allow real HTTP to the local API
    GoogleFonts.config.allowRuntimeFetching = false; // fall back to default fonts offline
  });

  Future<void> render(WidgetTester tester, String name, Widget screen, AuthState auth, {int waitMs = 1500}) async {
    errors.clear();
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      final msg = d.exceptionAsString();
      // Missing bundled fonts are expected in tests; everything else is a real failure.
      if (msg.contains('google_fonts') || msg.contains('allowRuntimeFetching')) return;
      errors.add('$name: ${msg.split('\n').first}');
    };
    tester.view.physicalSize = Size(screenW * 3.0, screenH * 3.0);
    tester.view.devicePixelRatio = 3;
    await tester.runAsync(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => NotificationsState()),
          ChangeNotifierProvider(create: (_) => PlayerState()),
        ],
        child: MaterialApp(theme: buildTheme(), home: screen),
      ));
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    final ex = tester.takeException();
    if (ex != null) errors.add('$name: $ex');
    FlutterError.onError = old;
    await tester.pumpWidget(const SizedBox());
    expect(errors, isEmpty, reason: errors.join('\n'));
  }

  Future<AuthState> asRole(String email) async {
    final r = await signIn(email);
    api.token = r['token'] as String;
    return AuthState()..setUser(r['user'] as Map<String, dynamic>);
  }

  group('signed out', () {
    final auth = AuthState();
    testWidgets('onboarding', (t) => render(t, 'onboarding', const OnboardingScreen(), auth));
    testWidgets('login', (t) => render(t, 'login', const LoginScreen(), auth));
    testWidgets('staff login', (t) => render(t, 'admin login', const LoginScreen(staff: 'admin'), auth));
    testWidgets('register', (t) => render(t, 'register', const RegisterScreen(), auth));
    testWidgets('register staff', (t) => render(t, 'register staff', const RegisterScreen(initialRole: 1), auth));
  });

  group('student', () {
    late AuthState auth;
    late Appointment appt;
    late Map<String, dynamic> counsellor;
    late String articleId;
    late String journalId;
    setUpAll(() async {
      auth = await asRole('it23714052@my.sliit.lk');
      final up = await raw('GET', '/appointments?scope=upcoming', token: api.token);
      appt = Appointment((up['appointments'] as List).first as Map<String, dynamic>);
      final cs = await raw('GET', '/counsellors', token: api.token);
      counsellor = (await raw('GET', '/counsellors/${(cs['counsellors'] as List).first['id']}', token: api.token))['counsellor'] as Map<String, dynamic>;
      articleId = ((await raw('GET', '/articles', token: api.token))['articles'] as List).first['id'] as String;
      journalId = ((await raw('GET', '/mood/journal', token: api.token))['entries'] as List).first['id'] as String;
    });
    final screens = <String, Widget Function()>{};
    void s(String n, Widget Function() w) => screens[n] = w;
    s('home', () => const StudentHome());
    s('counsellor list', () => const CounsellorListScreen());
    s('filters', () => CounsellorFiltersScreen(initial: CounsellorFilter()));
    s('my bookings', () => const MyAppointmentsScreen());
    s('mood tracker', () => const MoodTrackerScreen());
    s('mood history', () => const MoodHistoryScreen());
    s('mood insights', () => const MoodInsightsScreen());
    s('check-in', () => const CheckInScreen(initialMood: 3));
    s('journal list', () => const JournalListScreen());
    s('journal new', () => const JournalEditScreen());
    s('profile', () => const StudentProfileScreen());
    s('edit profile', () => const EditStudentProfileScreen());
    s('privacy', () => const PrivacySecurityScreen());
    s('data export', () => const DataExportScreen());
    s('delete account', () => const DeleteAccountScreen());
    s('wellness home', () => const WellnessHome());
    s('articles', () => const ArticleListScreen());
    s('articles sleep', () => const ArticleListScreen(initialCategory: 'Sleep'));
    s('saved', () => const SavedArticlesScreen());
    s('breathing home', () => const BreathingHomeScreen());
    s('breathing', () => const BreathingExerciseScreen(pattern: BreathPattern.box));
    s('breathing done', () => const BreathingCompleteScreen(pattern: BreathPattern.box, seconds: 120));
    s('games', () => const GamesHomeScreen());
    s('memory intro', () => const MemoryIntroScreen());
    s('memory', () => const MemoryGameScreen());
    s('focus', () => const FocusGameScreen());
    s('game complete', () => const GameCompleteScreen());
    s('music', () => const MusicListScreen());
    s('player empty', () => const MusicPlayerScreen());
    s('bridge intro', () => const BridgeIntroScreen());
    s('bridge chat', () => const BridgeChatScreen());
    s('bridge escalation', () => const BridgeEscalationScreen(userText: 'I can’t go on like this.', reply: 'I’m really glad you told me. Please call 1926.'));
    s('emergency hold', () => const EmergencyHoldScreen());
    s('support options', () => const SupportOptionsScreen());
    s('emergency info', () => const EmergencyInfoScreen());
    s('emergency cancelled', () => const EmergencyCancelledScreen());
    for (final e in screens.entries) {
      testWidgets(e.key, (t) => render(t, e.key, e.value(), auth));
    }
    testWidgets('appointment detail', (t) => render(t, 'appointment detail', AppointmentDetailScreen(id: appt.id), auth));
    testWidgets('reschedule', (t) => render(t, 'reschedule', RescheduleScreen(appointment: appt), auth));
    testWidgets('counsellor profile', (t) => render(t, 'counsellor profile', CounsellorProfileScreen(id: counsellor['id'] as String), auth));
    testWidgets('book date', (t) => render(t, 'book date', BookDateScreen(draft: BookingDraft(counsellor)), auth));
    testWidgets('book time', (t) => render(t, 'book time', BookTimeScreen(draft: BookingDraft(counsellor)..date = Fmt8.nextWeekday()), auth));
    testWidgets('book meeting', (t) => render(t, 'book meeting', BookMeetingScreen(draft: BookingDraft(counsellor)..date = Fmt8.nextWeekday()), auth));
    testWidgets('book success', (t) => render(t, 'booking success', BookingSuccessScreen(appointment: appt), auth));
    testWidgets('reschedule success', (t) => render(t, 'reschedule success', RescheduleSuccessScreen(appointment: appt), auth));
    testWidgets('cancel success', (t) => render(t, 'cancel success', CancelSuccessScreen(appointment: appt), auth));
    testWidgets('article detail', (t) => render(t, 'article detail', ArticleDetailScreen(id: articleId), auth));
    testWidgets('journal entry', (t) => render(t, 'journal entry', JournalEntryScreen(id: journalId), auth));
    testWidgets('check-in saved', (t) => render(t, 'check-in saved', const CheckInSavedScreen(result: {'streak': 5, 'suggestion': {'kind': 'breathing', 'title': '2-minute box breathing', 'sub': 'Good for exam nerves'}}), auth));
  });

  group('counsellor', () {
    late AuthState auth;
    late Appointment pending;
    late Appointment confirmed;
    late Appointment completed;
    late String articleId;
    setUpAll(() async {
      auth = await asRole('hasini.k@sliit.lk');
      final d = await raw('GET', '/staff/dashboard', token: api.token);
      pending = Appointment((d['pending'] as List).first as Map<String, dynamic>);
      confirmed = Appointment(d['next'] as Map<String, dynamic>);
      final past = await raw('GET', '/appointments?scope=past', token: api.token);
      completed = Appointment((past['appointments'] as List).firstWhere((a) => a['status'] == 'completed') as Map<String, dynamic>);
      articleId = ((await raw('GET', '/articles/mine', token: api.token))['articles'] as List).first['id'] as String;
    });
    testWidgets('dashboard', (t) => render(t, 'dashboard', const CounsellorDashboard(), auth));
    testWidgets('requests', (t) => render(t, 'requests', const RequestsScreen(), auth));
    testWidgets('request detail', (t) => render(t, 'request detail', RequestDetailScreen(id: pending.id), auth));
    testWidgets('duplicate', (t) => render(t, 'duplicate', DuplicateScreen(id: pending.id), auth));
    testWidgets('decline', (t) => render(t, 'decline', DeclineScreen(appointment: pending), auth));
    testWidgets('accepted', (t) => render(t, 'accepted', RequestAcceptedScreen(appointment: confirmed), auth));
    testWidgets('appointments', (t) => render(t, 'appointments', const CounsellorAppointmentsScreen(), auth));
    testWidgets('calendar', (t) => render(t, 'calendar', const CalendarScreen(), auth));
    testWidgets('appointment', (t) => render(t, 'appointment', CounsellorAppointmentScreen(id: confirmed.id), auth));
    testWidgets('appointment done', (t) => render(t, 'appointment completed', CounsellorAppointmentScreen(id: completed.id), auth));
    testWidgets('propose', (t) => render(t, 'propose', ProposeTimeScreen(appointment: confirmed), auth));
    testWidgets('availability', (t) => render(t, 'availability', const AvailabilityScreen(), auth));
    testWidgets('slot preview', (t) => render(t, 'slot preview', const SlotPreviewScreen(), auth));
    testWidgets('block time', (t) => render(t, 'block time', const BlockTimeScreen(), auth));
    testWidgets('prep', (t) => render(t, 'prep', SessionPrepScreen(id: confirmed.id), auth));
    testWidgets('live session', (t) => render(t, 'live session', LiveSessionScreen(appointment: confirmed), auth));
    testWidgets('notes', (t) => render(t, 'notes', SessionNotesScreen(appointment: completed), auth));
    testWidgets('completed', (t) => render(t, 'session completed', SessionCompletedScreen(appointment: completed, sessions: 3), auth));
    testWidgets('student info', (t) => render(t, 'student info', StudentInfoScreen(appointmentId: confirmed.id), auth));
    testWidgets('refer', (t) => render(t, 'refer', ReferDoctorScreen(appointment: completed), auth));
    testWidgets('referrals', (t) => render(t, 'referrals', const CounsellorReferralsScreen(), auth));
    testWidgets('articles', (t) => render(t, 'articles', const MyArticlesScreen(), auth));
    testWidgets('article edit', (t) => render(t, 'article edit', const ArticleEditScreen(), auth));
    testWidgets('article preview', (t) => render(t, 'article preview', ArticlePreviewScreen(id: articleId), auth));
    testWidgets('profile', (t) => render(t, 'profile', const CounsellorAccountScreen(), auth));
    testWidgets('edit profile', (t) => render(t, 'edit profile', const EditStaffProfileScreen(), auth));
    testWidgets('verification', (t) => render(t, 'verification', const VerificationInfoScreen(), auth));
    testWidgets('settings', (t) => render(t, 'settings', const StaffSettingsScreen(), auth));
    testWidgets('prefs', (t) => render(t, 'prefs', const NotificationPrefsScreen(), auth));
  });

  group('doctor', () {
    late AuthState auth;
    late String refId;
    late String consId;
    late String studentId;
    setUpAll(() async {
      auth = await asRole('ruwan.d@sliit.lk');
      refId = ((await raw('GET', '/referrals', token: api.token))['referrals'] as List).first['id'] as String;
      consId = ((await raw('GET', '/doctor/consultations?scope=today', token: api.token))['consultations'] as List).first['id'] as String;
      studentId = ((await raw('GET', '/doctor/students', token: api.token))['students'] as List).first['id'] as String;
    });
    testWidgets('dashboard', (t) => render(t, 'dashboard', const DoctorDashboard(), auth));
    testWidgets('referrals', (t) => render(t, 'referrals', const ReferralListScreen(), auth));
    testWidgets('referral', (t) => render(t, 'referral', ReferralDetailScreen(id: refId), auth));
    testWidgets('decline', (t) => render(t, 'decline', DeclineReferralScreen(id: refId), auth));
    testWidgets('request info', (t) => render(t, 'request info', RequestInfoScreen(id: refId), auth));
    testWidgets('consultations', (t) => render(t, 'consultations', const ConsultationListScreen(), auth));
    testWidgets('consultation', (t) => render(t, 'consultation', ConsultationDetailScreen(id: consId), auth));
    testWidgets('consult live', (t) => render(t, 'consult live', DoctorConsultationScreen(id: consId), auth));
    testWidgets('notes', (t) => render(t, 'doctor notes', DoctorNotesScreen(id: consId), auth));
    testWidgets('follow-up', (t) => render(t, 'follow-up', FollowUpScreen(consultationId: consId, studentName: 'Test Student'), auth));
    testWidgets('students', (t) => render(t, 'students', const MyStudentsScreen(), auth));
    testWidgets('student', (t) => render(t, 'student', DoctorStudentScreen(id: studentId), auth));
    testWidgets('profile', (t) => render(t, 'profile', const DoctorProfileScreen(), auth));
  });

  group('admin', () {
    late AuthState auth;
    late String userId;
    late String appId;
    late String articleId;
    late Map<String, dynamic> dash;
    setUpAll(() async {
      auth = await asRole('malsha.g@sliit.lk');
      userId = ((await raw('GET', '/admin/users?role=student', token: api.token))['users'] as List).first['id'] as String;
      appId = ((await raw('GET', '/admin/verifications?status=pending', token: api.token))['applications'] as List).first['id'] as String;
      articleId = ((await raw('GET', '/admin/articles?status=waiting', token: api.token))['articles'] as List).first['id'] as String;
      dash = await raw('GET', '/admin/dashboard', token: api.token);
    });
    testWidgets('dashboard', (t) => render(t, 'dashboard', const AdminDashboard(), auth));
    testWidgets('quick actions', (t) => render(t, 'quick actions', QuickActionsScreen(data: dash), auth));
    testWidgets('activity', (t) => render(t, 'activity', const ActivityOverviewScreen(), auth));
    testWidgets('users', (t) => render(t, 'users', const UsersScreen(), auth));
    testWidgets('user filter', (t) => render(t, 'user filter', UserFilterScreen(initial: UserFilter()), auth));
    testWidgets('user', (t) => render(t, 'user', UserDetailScreen(id: userId), auth));
    testWidgets('roles', (t) => render(t, 'roles', const RolesScreen(), auth));
    testWidgets('role perms', (t) => render(t, 'role perms', const RolePermissionsScreen(role: 'counsellor', label: 'Counsellor'), auth));
    testWidgets('permission', (t) => render(t, 'permission', const PermissionDetailScreen(), auth));
    testWidgets('verification', (t) => render(t, 'verification', const VerificationCenterScreen(), auth));
    testWidgets('applications', (t) => render(t, 'applications', const ApplicationListScreen(role: 'counsellor'), auth));
    testWidgets('application', (t) => render(t, 'application', ApplicationScreen(id: appId), auth));
    testWidgets('moderation', (t) => render(t, 'moderation', const ModerationScreen(), auth));
    testWidgets('article review', (t) => render(t, 'article review', ArticleReviewScreen(id: articleId), auth));
    testWidgets('reject article', (t) => render(t, 'reject article', RejectArticleScreen(id: articleId), auth));
    testWidgets('reports', (t) => render(t, 'reports', const ReportsScreen(), auth));
    testWidgets('appointment stats', (t) => render(t, 'appointment stats', AppointmentStatsScreen(range: ReportRange(preset: 'semester')), auth));
    testWidgets('type stats', (t) => render(t, 'type stats', TypeStatsScreen(range: ReportRange(preset: 'semester')), auth));
    testWidgets('usage', (t) => render(t, 'usage', ServiceUsageScreen(range: ReportRange(preset: 'semester')), auth));
    testWidgets('wellness usage', (t) => render(t, 'wellness usage', WellnessUsageScreen(range: ReportRange()), auth));
    testWidgets('user stats', (t) => render(t, 'user stats', const UserStatsScreen(), auth));
    testWidgets('date range', (t) => render(t, 'date range', DateRangeScreen(initial: ReportRange()), auth));
    testWidgets('export', (t) => render(t, 'export', const ReportExportScreen(), auth));
    testWidgets('system', (t) => render(t, 'system', const SystemScreen(), auth));
    testWidgets('music library', (t) => render(t, 'music library', const MusicAdminScreen(), auth));
    testWidgets('add track', (t) => render(t, 'add track', const TrackFormScreen(), auth));
    testWidgets('edit track', (t) => render(t, 'edit track', const TrackFormScreen(track: Track(id: 'x', title: 'Night Waves', artist: 'Calm Sounds', category: 'Sleep', seconds: 410, icon: 'bedtime', tone: 'lilac')), auth));
    for (final s in ['appointments', 'notifications', 'privacy', 'security']) {
      testWidgets('settings $s', (t) => render(t, 'settings $s', SettingsScreen(section: s), auth));
    }
    testWidgets('log', (t) => render(t, 'log', const ActivityLogScreen(), auth));
    testWidgets('admin profile', (t) => render(t, 'admin profile', const AdminProfileScreen(), auth));
  });
}

class Fmt8 {
  static String nextWeekday() {
    var d = DateTime.now().toUtc().add(const Duration(minutes: 330));
    do {
      d = d.add(const Duration(days: 1));
    } while (d.weekday > 5);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
