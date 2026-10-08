import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../modules/appointment/appointments.dart';
import '../../modules/appointment/booking.dart';
import '../../modules/mood/mood.dart';
import '../../state/auth.dart';
import '../../state/notifications.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import '../common/notifications.dart';
import '../wellness/bridge.dart';
import '../wellness/emergency.dart';
import 'counsellors.dart';
import 'student_shell.dart';

class _HomeData {
  _HomeData(this.next, this.today, this.availableThisWeek, this.upcomingCount);
  final Appointment? next;
  final Map<String, dynamic>? today;
  final int availableThisWeek;
  final int upcomingCount;
}

/// M1-05 — the next appointment, its status and Reschedule sit side by side.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  final _key = GlobalKey<LoaderState<_HomeData>>();

  Future<_HomeData> _load() async {
    final res = await Future.wait([
      api.get('/appointments', query: {'scope': 'upcoming'}),
      api.get('/mood/today'),
      api.get('/counsellors', query: {'available': 'week'}),
    ]);
    final appts = Appointment.list(res[0]['appointments']);
    return _HomeData(appts.isEmpty ? null : appts.first, res[1]['entry'] as Map<String, dynamic>?, (res[2]['counsellors'] as List).length, appts.length);
  }

  Future<void> _openCheckIn([int? mood]) async {
    await push(context, CheckInScreen(initialMood: mood), root: true);
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final unread = context.watch<NotificationsState>().unread;
    final greet = Greet(
      eyebrow: Fmt.todayLong(),
      title: 'Hi, ${auth.firstName}',
      actions: [
        HeaderAction('notifications', tooltip: 'Notifications', dot: unread > 0, onTap: () => push(context, const NotificationsScreen(onOpen: openStudentLink))),
        HeaderAction('emergency', label: 'SOS', danger: true, tooltip: 'Emergency support', onTap: () => push(context, const EmergencyHoldScreen(), root: true)),
      ],
    );
    return Loader<_HomeData>(
      key: _key,
      load: _load,
      wrap: (c) => MbPage(children: [greet, c]),
      builder: (context, d, reload) {
        final shell = RoleShell.maybeOf(context);
        final a = d.next;
        final checked = d.today != null;
        return MbPage(
          onRefresh: reload,
          children: [
            greet,
            MoodPicker(
              title: checked ? 'You checked in today' : 'How are you feeling today?',
              link: checked ? 'History' : 'Check in',
              onLink: checked ? () => push(context, const MoodHistoryScreen()) : () => _openCheckIn(),
              selected: d.today?['mood'] as int?,
              onSelect: (m) => _openCheckIn(m),
            ),
            SectionHeader('Your next appointment', link: 'See all', onLink: () => shell?.switchTo('appts')),
            if (a == null)
              HeroCard(
                style: HeroStyle.soft,
                eyebrow: 'Counselling',
                title: 'No upcoming sessions',
                sub: 'Book a free, confidential session with a university counsellor. It takes about two minutes.',
                actions: [MbButton('Find a counsellor', icon: 'person_search', onPressed: () => push(context, const CounsellorListScreen()))],
              )
            else
              HeroCard(
                eyebrow: 'Counselling',
                badge: a.statusLabel,
                badgeTone: a.statusTone,
                title: a.counsellorName,
                sub: a.counsellor['title'] as String?,
                rows: [
                  ('calendar_today', '${Fmt.relDay(a.start) ?? Fmt.day(a.start)} · ${a.timeRange}'),
                  (a.online ? 'videocam' : 'meeting_room', a.online ? (a.status == 'pending' ? 'Online · link after confirmation' : 'Online · link opens 10 min before') : a.location),
                ],
                onTap: () async {
                  await push(context, AppointmentDetailScreen(id: a.id));
                  reload();
                },
                actions: [
                  MbButton('View details', kind: BtnKind.light, height: 46, fontSize: 14.5, onPressed: () async {
                    await push(context, AppointmentDetailScreen(id: a.id));
                    reload();
                  }),
                  if (a.status == 'reschedule_proposed')
                    MbButton('Respond', kind: BtnKind.outlineLight, height: 46, fontSize: 14.5, onPressed: () async {
                      await push(context, AppointmentDetailScreen(id: a.id));
                      reload();
                    })
                  else if (a.canChange)
                    MbButton('Reschedule', kind: BtnKind.outlineLight, height: 46, fontSize: 14.5, onPressed: () async {
                      await push(context, RescheduleScreen(appointment: a), root: true, name: 'resched');
                      reload();
                    }),
                ],
              ),
            const SectionHeader('Quick actions'),
            ActionGrid([
              GridItem('person_search', 'Find a counsellor', sub: d.availableThisWeek == 1 ? '1 available this week' : '${d.availableThisWeek} available this week', onTap: () => push(context, const CounsellorListScreen())),
              GridItem('event_note', 'My bookings', sub: d.upcomingCount == 0 ? 'None upcoming' : '${d.upcomingCount} upcoming', tone: Tone.blue, onTap: () => shell?.switchTo('appts')),
              GridItem('self_improvement', 'Wellness hub', sub: 'Breathing, games, music', tone: Tone.lilac, onTap: () => shell?.switchTo('well')),
              GridItem('forum', 'Talk to Bridge', sub: 'AI wellness assistant', tone: Tone.amber, onTap: () => push(context, const BridgeIntroScreen())),
            ]),
            BannerCard(
              tone: Tone.red,
              icon: 'call',
              title: 'Need help right now?',
              text: 'The National Mental Health Helpline is free and open 24/7.',
              link: 'Call 1926',
              onLink: () => push(context, const SupportOptionsScreen(), root: true),
            ),
          ],
        );
      },
    );
  }
}
