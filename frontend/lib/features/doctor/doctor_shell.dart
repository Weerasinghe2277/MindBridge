import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../modules/availability/availability.dart';
import '../../modules/referral/referrals.dart';
import '../../state/auth.dart';
import '../../state/notifications.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import '../common/account.dart';
import '../common/notifications.dart';
import '../counsellor/c_profile.dart';
import 'consultations.dart';

class DoctorShell extends StatelessWidget {
  const DoctorShell({super.key});

  @override
  Widget build(BuildContext context) => RoleShell(tabs: [
        ShellTab('home', 'home', 'Home', (_) => const DoctorDashboard()),
        ShellTab('ref', 'assignment_ind', 'Referrals', (_) => const ReferralListScreen()),
        ShellTab('con', 'stethoscope', 'Consults', (_) => const ConsultationListScreen()),
        ShellTab('pat', 'groups', 'Students', (_) => const MyStudentsScreen()),
        ShellTab('me', 'person', 'Profile', (_) => const DoctorProfileScreen()),
      ]);
}

void openDoctorLink(BuildContext context, Map<String, dynamic> link) {
  final id = link['id'] as String?;
  if (id == null) return;
  if (link['screen'] == 'referral') push(context, ReferralDetailScreen(id: id));
  if (link['screen'] == 'consultation') push(context, ConsultationDetailScreen(id: id));
}

ListItemData consultationItem(Map<String, dynamic> c, {VoidCallback? onTap, bool showDay = false}) {
  final s = c['student'] as Map<String, dynamic>;
  final ref = c['referral'] as Map<String, dynamic>?;
  final day = c['dayLabel'] as String? ?? Fmt.day(c['start']);
  return ListItemData(
    avatar: s['initials'] as String,
    title: s['name'] as String,
    sub: [if (showDay) day, Fmt.time(c['start']), modeLabelOf(c['mode'] as String), if (c['isFollowUp'] == true) 'Follow-up' else if (ref != null) _short(ref['reason'] as String?)].whereType<String>().join(' · '),
    badge: c['status'] == 'scheduled' ? (c['dayLabel'] as String? ?? 'Scheduled') : c['statusLabel'] as String,
    badgeTone: c['status'] == 'scheduled' ? (c['dayLabel'] == 'Today' ? Tone.green : Tone.blue) : Tone.of(c['statusTone'] as String?),
    onTap: onTap,
  );
}

String modeLabelOf(String m) => m == 'online' ? 'Online' : 'In person';
String? _short(String? s) => s == null ? null : (s.length > 28 ? '${s.substring(0, 28)}…' : s);

/// M4-01 — urgent referrals first, then today's consultations.
class DoctorDashboard extends StatelessWidget {
  const DoctorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final unread = context.watch<NotificationsState>().unread;
    final last = (auth.user?['name'] as String? ?? '').split(' ').last;
    final greet = Greet(
      eyebrow: 'University Medical Centre',
      title: '${Fmt.greeting()}, Dr. $last',
      actions: [HeaderAction('notifications', tooltip: 'Notifications', dot: unread > 0, onTap: () => push(context, const NotificationsScreen(onOpen: openDoctorLink, emptyText: 'New referrals and reminders will appear here.')))],
    );
    return Loader<Map<String, dynamic>>(
      load: () => api.get('/doctor/dashboard'),
      wrap: (c) => MbPage(children: [greet, c]),
      builder: (context, d, reload) {
        final shell = RoleShell.maybeOf(context);
        final today = (d['today'] as List).cast<Map<String, dynamic>>();
        final fu = (d['followUps'] as List).cast<Map<String, dynamic>>();
        final pr = d['priority'] as Map<String, dynamic>?;
        Future<void> open(Widget page) async {
          await push(context, page);
          reload();
        }

        return MbPage(
          onRefresh: reload,
          children: [
            greet,
            StatsGrid([
              StatItem('${d['newReferrals']}', 'New referrals', tone: (d['newReferrals'] as num) > 0 ? Tone.amber : null, onTap: () => shell?.switchTo('ref')),
              StatItem('${d['todayCount']}', 'Consultations today', onTap: () => shell?.switchTo('con')),
            ]),
            if (pr != null)
              BannerCard(tone: Tone.red, icon: 'priority_high', title: '${pr['urgency'] == 'urgent' ? 'Urgent' : 'Priority'} referral', text: '${pr['student']} · from ${pr['counsellor']} · respond within 24 hours', link: 'Review', onLink: () => open(ReferralDetailScreen(id: pr['id'] as String))),
            SectionHeader('Today’s consultations', link: 'All', onLink: () => shell?.switchTo('con')),
            if (today.isEmpty)
              const BannerCard(tone: Tone.grey, icon: 'event_available', text: 'No consultations booked for today.')
            else
              ListCards([for (final c in today) consultationItem(c, onTap: () => open(ConsultationDetailScreen(id: c['id'] as String)))]),
            const SectionHeader('Follow-ups due'),
            if (fu.isEmpty)
              const BannerCard(tone: Tone.grey, icon: 'event_repeat', text: 'No follow-ups in the next week.')
            else
              ListCards([for (final c in fu) consultationItem(c, showDay: true, onTap: () => open(ConsultationDetailScreen(id: c['id'] as String)))]),
          ],
        );
      },
    );
  }
}

/// X-09 — only students referred to this doctor (NFR1).
class MyStudentsScreen extends StatefulWidget {
  const MyStudentsScreen({super.key});

  @override
  State<MyStudentsScreen> createState() => _MyStudentsScreenState();
}

class _MyStudentsScreenState extends State<MyStudentsScreen> {
  final _q = TextEditingController();
  int _chip = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/doctor/students'),
        wrap: (c) => MbPage(title: 'My students', root: true, children: [c]),
        builder: (context, d, reload) {
          final q = _q.text.trim().toLowerCase();
          final all = (d['students'] as List).cast<Map<String, dynamic>>();
          final list = all.where((s) {
            if (q.isNotEmpty && !'${s['name']} ${s['studentId']}'.toLowerCase().contains(q)) return false;
            if (_chip == 1) return s['nextVisit'] != null;
            if (_chip == 2) return s['followUpDue'] == true;
            return true;
          }).toList();
          return MbPage(
            title: 'My students',
            root: true,
            onRefresh: reload,
            children: [
              SearchBox(controller: _q, hint: 'Search referred students', onChanged: (_) => setState(() {})),
              Chips(items: const ['All', 'Upcoming visit', 'Follow-up due'], selected: {_chip}, onTap: (i) => setState(() => _chip = i)),
              if (list.isEmpty)
                const StateView(icon: 'groups', tone: Tone.grey, title: 'No students', text: 'Students appear here once a counsellor refers them to you.')
              else
                ListCards([
                  for (final s in list)
                    ListItemData(
                      avatar: s['initials'] as String,
                      title: s['name'] as String,
                      sub: s['nextVisit'] != null ? 'Next visit ${Fmt.dateTime(s['nextVisit'])}' : (s['lastSeen'] != null ? 'Last seen ${Fmt.stamp(s['lastSeen'])}' : 'Referral received'),
                      badge: s['followUpDue'] == true ? 'Follow-up' : 'Active',
                      badgeTone: s['followUpDue'] == true ? Tone.amber : Tone.green,
                      onTap: () => push(context, DoctorStudentScreen(id: s['id'] as String)),
                    ),
                ]),
              const Txt('Only students referred to you appear here.', size: TxtSize.xs, align: TextAlign.center),
            ],
          );
        },
      );
}

/// X-10
class DoctorStudentScreen extends StatelessWidget {
  const DoctorStudentScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/doctor/students/$id'),
        wrap: (c) => MbPage(title: 'Student', children: [c]),
        builder: (context, d, reload) {
          final s = d['student'] as Map<String, dynamic>;
          final refs = (d['referrals'] as List).cast<Map<String, dynamic>>();
          final cons = (d['consultations'] as List).cast<Map<String, dynamic>>();
          final latest = d['latestConsultationId'] as String?;
          return MbPage(
            title: 'Student',
            onRefresh: reload,
            children: [
              ProfileHeader(initials: s['initials'] as String, name: s['name'] as String, sub: [(s['faculty'] as String?)?.replaceFirst('Faculty of ', ''), if (s['year'] != null) 'Year ${s['year']}', s['studentId']].whereType<String>().join(' · ')),
              const BannerCard(icon: 'shield', text: 'Only referral information is shown. Mood data and journals are never visible to doctors.'),
              ListCards([
                for (final r in refs) ListItemData(icon: 'assignment_ind', title: 'Referral · ${Fmt.stamp(r['createdAt'])}', sub: 'From ${r['counsellor']}', badge: '${r['status']}'[0].toUpperCase() + '${r['status']}'.substring(1), badgeTone: r['status'] == 'new' ? Tone.amber : Tone.green, onTap: () => push(context, ReferralDetailScreen(id: r['id'] as String))),
                for (final c in cons) ListItemData(icon: 'stethoscope', tone: Tone.blue, title: '${c['isFollowUp'] == true ? 'Follow-up' : 'Consultation'} · ${Fmt.day(c['start'])}', sub: (c['tags'] as List).isEmpty ? c['status'] as String : (c['tags'] as List).join(', '), onTap: () => push(context, ConsultationDetailScreen(id: c['id'] as String))),
              ]),
            ],
            foot: latest == null
                ? const []
                : [
                    MbButton('Schedule follow-up', onPressed: () => push(context, FollowUpScreen(consultationId: latest, studentName: s['name'] as String), root: true, name: 'followup')),
                    MbButton('Add clinical notes', kind: BtnKind.secondary, onPressed: () => push(context, DoctorNotesScreen(id: latest), root: true)),
                  ],
          );
        },
      );
}

/// M4-15
class DoctorProfileScreen extends StatelessWidget {
  const DoctorProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user ?? const {};
    final p = (u['professional'] as Map?)?.cast<String, dynamic>() ?? {};
    return MbPage(
      title: 'Profile',
      root: true,
      onRefresh: auth.refreshUser,
      children: [
        ProfileHeader(initials: u['initials'] as String? ?? '', photoUrl: u['photoUrl'] as String?, editable: true, onAvatarTap: () => changeProfilePhoto(context), name: u['name'] as String? ?? '', sub: [p['title'], p['qualifications'], p['office'] ?? 'University Medical Centre'].whereType<String>().where((e) => e.isNotEmpty).join(' · '), badge: 'Verified doctor'),
        MenuCard([
          MenuItemData('person', 'Edit profile', onTap: () => push(context, const EditStaffProfileScreen(), root: true)),
          MenuItemData('schedule', 'Consultation hours', onTap: () => push(context, const AvailabilityScreen())),
          MenuItemData('verified', 'Verification', value: 'Verified', onTap: () => push(context, const VerificationInfoScreen())),
          MenuItemData('settings', 'Settings', onTap: () => push(context, const StaffSettingsScreen())),
          MenuItemData('notifications', 'Notifications', onTap: () => push(context, const NotificationsScreen(onOpen: openDoctorLink))),
        ]),
        MenuCard([MenuItemData('logout', 'Sign out', danger: true, onTap: () => confirmSignOut(context))]),
      ],
    );
  }
}
