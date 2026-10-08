import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../modules/appointment/requests.dart';
import '../../modules/appointment/schedule.dart';
import '../../modules/article/c_articles.dart';
import '../../modules/counselling_session/sessions.dart';
import '../../modules/referral/counsellor_referrals.dart';
import '../../state/auth.dart';
import '../../state/notifications.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import '../common/notifications.dart';
import 'c_profile.dart';

class CounsellorShell extends StatelessWidget {
  const CounsellorShell({super.key});

  @override
  Widget build(BuildContext context) => RoleShell(tabs: [
        ShellTab('home', 'home', 'Home', (_) => const CounsellorDashboard()),
        ShellTab('req', 'inbox', 'Requests', (_) => const RequestsScreen()),
        ShellTab('cal', 'calendar_month', 'Calendar', (_) => const CalendarScreen()),
        ShellTab('art', 'edit_note', 'Articles', (_) => const MyArticlesScreen()),
        ShellTab('me', 'person', 'Profile', (_) => const CounsellorAccountScreen()),
      ]);
}

void openCounsellorLink(BuildContext context, Map<String, dynamic> link) {
  final id = link['id'] as String?;
  if (id == null) return;
  switch (link['screen']) {
    case 'request':
      push(context, RequestDetailScreen(id: id));
    case 'appointment':
      push(context, CounsellorAppointmentScreen(id: id));
    case 'referral':
      push(context, CounsellorReferralScreen(id: id));
    case 'my_article':
      push(context, ArticlePreviewScreen(id: id));
  }
}

/// One list row for a booking, seen from the counsellor side.
ListItemData counsellorApptItem(Appointment a, {VoidCallback? onTap, bool showDate = false}) => ListItemData(
      avatar: a.student['initials'] as String? ?? '',
      title: a.studentName,
      sub: '${showDate ? '${Fmt.relDay(a.start) ?? Fmt.day(a.start)} · ' : ''}${a.timeRange} · ${a.modeLabel}',
      meta: a.status == 'pending' ? 'Requested ${Fmt.ago(a.createdAt)}' : null,
      badge: a.duplicateFlag ? 'Duplicate?' : a.statusLabel,
      badgeTone: a.duplicateFlag ? Tone.red : a.statusTone,
      onTap: onTap,
    );

/// M2-05 — requests, today's schedule and duplicate alerts on one screen (FR6, FR7).
class CounsellorDashboard extends StatefulWidget {
  const CounsellorDashboard({super.key});

  @override
  State<CounsellorDashboard> createState() => _CounsellorDashboardState();
}

class _CounsellorDashboardState extends State<CounsellorDashboard> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final unread = context.watch<NotificationsState>().unread;
    final first = (auth.user?['name'] as String? ?? '').replaceFirst(RegExp(r'^(Dr|Mr|Ms|Mrs|Prof)\.?\s+'), '').split(' ').first;
    final greet = Greet(
      eyebrow: Fmt.todayLong(),
      title: '${Fmt.greeting()}, $first',
      actions: [HeaderAction('notifications', tooltip: 'Notifications', dot: unread > 0, onTap: () => push(context, const NotificationsScreen(onOpen: openCounsellorLink, emptyText: 'New requests and changes from students will show up here.')))],
    );
    return Loader<Map<String, dynamic>>(
      load: () => api.get('/staff/dashboard'),
      wrap: (c) => MbPage(children: [greet, c]),
      builder: (context, d, reload) {
        final shell = RoleShell.maybeOf(context);
        final next = d['next'] == null ? null : Appointment(d['next'] as Map<String, dynamic>);
        final today = Appointment.list(d['today']);
        final pending = Appointment.list(d['pending']);
        final dups = Appointment.list(d['duplicates']);
        Future<void> open(Widget page) async {
          await push(context, page);
          reload();
        }

        return MbPage(
          onRefresh: reload,
          children: [
            greet,
            StatsGrid([
              StatItem('${d['pendingCount']}', 'Pending requests', tone: (d['pendingCount'] as num) > 0 ? Tone.amber : null, onTap: () => shell?.switchTo('req')),
              StatItem('${d['todayCount']}', 'Sessions today', onTap: () => open(const CounsellorAppointmentsScreen())),
            ]),
            for (final a in dups.take(1))
              BannerCard(tone: Tone.red, icon: 'content_copy', title: 'Possible duplicate booking', text: '${a.studentName} has more than one active request.', link: 'Review', onLink: () => open(DuplicateScreen(id: a.id))),
            const SectionHeader('Next session'),
            if (next == null)
              const HeroCard(style: HeroStyle.soft, eyebrow: 'Up next', title: 'No confirmed sessions coming up', sub: 'New requests will appear below as students book.')
            else
              HeroCard(
                eyebrow: Fmt.startsIn(next.start),
                badge: next.modeLabel,
                badgeTone: Tone.blue,
                title: next.studentName,
                sub: next.j['sessionNumber'] != null && (next.j['sessionNumber'] as num) > 1 ? 'Follow-up · session ${next.j['sessionNumber']}' : 'First visit',
                rows: [
                  ('schedule', '${Fmt.relDay(next.start) ?? Fmt.day(next.start)} · ${next.timeRange}'),
                  (next.online ? 'videocam' : 'meeting_room', next.online ? 'Secure video link ready' : next.location),
                ],
                actions: [
                  MbButton('Prepare', kind: BtnKind.light, height: 46, fontSize: 14.5, onPressed: () => open(SessionPrepScreen(id: next.id))),
                  MbButton('Start session', kind: BtnKind.outlineLight, height: 46, fontSize: 14.5, onPressed: () => startSession(context, next).then((_) => reload())),
                ],
              ),
            SectionHeader('Today', link: 'Calendar', onLink: () => shell?.switchTo('cal')),
            if (today.isEmpty)
              const BannerCard(tone: Tone.grey, icon: 'event_available', text: 'No sessions today. Students can book any open slot.')
            else
              ListCards([for (final a in today) counsellorApptItem(a, onTap: () => open(CounsellorAppointmentScreen(id: a.id)))]),
            SectionHeader('Pending requests', link: pending.isEmpty ? null : 'See all', onLink: () => shell?.switchTo('req')),
            if (pending.isEmpty)
              const BannerCard(tone: Tone.grey, icon: 'inbox', text: 'No requests waiting for you.')
            else
              ListCards([for (final a in pending.take(3)) counsellorApptItem(a, showDate: true, onTap: () => open(a.duplicateFlag ? DuplicateScreen(id: a.id) : RequestDetailScreen(id: a.id)))]),
          ],
        );
      },
    );
  }
}
