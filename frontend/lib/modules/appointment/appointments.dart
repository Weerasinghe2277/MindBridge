// MEMBER 1 — Appointment Management: view appointments (student) and cancel.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../features/student/counsellors.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'booking.dart';

/// M1-16 / M1-17 — every booking with its live status (FR4).
class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen> {
  int _seg = 0;
  final _keys = [GlobalKey<LoaderState<List<Appointment>>>(), GlobalKey<LoaderState<List<Appointment>>>()];

  Future<void> _bookAnother(List<Appointment> upcoming) async {
    final active = upcoming.where((a) => a.isActive).toList();
    if (active.isNotEmpty) {
      await showDuplicateSheet(context, active.first);
    } else {
      await push(context, const CounsellorListScreen());
    }
    _keys[_seg].currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final seg = Segmented(items: const ['Upcoming', 'Past'], index: _seg, onChanged: (i) => setState(() => _seg = i));
    return Loader<List<Appointment>>(
      key: _keys[_seg],
      load: () async => Appointment.list((await api.get('/appointments', query: {'scope': _seg == 0 ? 'upcoming' : 'past'}))['appointments']),
      wrap: (c) => MbPage(title: 'My bookings', root: true, children: [seg, c]),
      builder: (context, list, reload) {
        Future<void> open(Appointment a) async {
          await push(context, AppointmentDetailScreen(id: a.id));
          reload();
        }

        ListItemData item(Appointment a) => ListItemData(
              avatar: a.counsellor['initials'] as String? ?? '',
              title: a.counsellorName,
              sub: '${Fmt.dateTime(a.start)} · ${a.modeLabel}',
              meta: a.isActive && a.remindersOn ? 'Reminder on' : null,
              badge: a.statusLabel,
              badgeTone: a.statusTone,
              onTap: () => open(a),
            );

        return MbPage(
          title: 'My bookings',
          root: true,
          onRefresh: reload,
          children: [
            seg,
            if (list.isEmpty)
              _seg == 0
                  ? const StateView(icon: 'event_busy', tone: Tone.grey, title: 'No bookings yet', text: 'When you book a session, its status will appear here at every step.')
                  : const StateView(icon: 'history', tone: Tone.grey, title: 'No past sessions', text: 'Completed and cancelled sessions will show up here.')
            else
              ListCards(list.map(item).toList()),
            if (_seg == 0 && list.isNotEmpty) MbButton('Book another session', kind: BtnKind.secondary, icon: 'add', onPressed: () => _bookAnother(list)),
          ],
          foot: _seg == 0 && list.isEmpty ? [MbButton('Find a counsellor', onPressed: () => push(context, const CounsellorListScreen()))] : const [],
        );
      },
    );
  }
}

/// M1-18 — status, timeline and clearly labelled Reschedule / Cancel (FR3, FR4).
class AppointmentDetailScreen extends StatefulWidget {
  const AppointmentDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  final _key = GlobalKey<LoaderState<Appointment>>();

  Future<Appointment> _load() async => Appointment((await api.get('/appointments/${widget.id}'))['appointment'] as Map<String, dynamic>);

  Future<void> _cancel(Appointment a) async {
    Appointment? done;
    final r = await showMbSheet(
      context,
      icon: 'event_busy',
      tone: Tone.red,
      title: a.status == 'pending' ? 'Cancel this request?' : 'Cancel this appointment?',
      text: 'Your slot will be released for another student. You can book again any time.',
      areaHint: 'Reason (optional)',
      actions: [
        SheetAction('Yes, cancel', kind: BtnKind.danger, run: (text) async {
          final res = await api.post('/appointments/${a.id}/cancel', {'reason': text});
          done = Appointment(res['appointment'] as Map<String, dynamic>);
          return true;
        }),
        if (a.canChange) const SheetAction('Reschedule instead', kind: BtnKind.secondary, value: 'reschedule'),
        const SheetAction('Keep appointment', kind: BtnKind.ghost),
      ],
    );
    if (!mounted) return;
    if (done != null) {
      replace(context, CancelSuccessScreen(appointment: done!));
    } else if (r == 'reschedule') {
      await push(context, RescheduleScreen(appointment: a), root: true, name: 'resched');
      _key.currentState?.reload();
    }
  }

  Future<void> _respond(Appointment a, bool accept) async {
    final r = await guard(context, () => api.post('/appointments/${a.id}/proposal', {'accept': accept}));
    if (r != null && mounted) {
      toast(context, accept ? 'New time confirmed.' : 'You kept the original time.');
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) => Loader<Appointment>(
        key: _key,
        load: _load,
        wrap: (c) => MbPage(title: 'Appointment', children: [c]),
        builder: (context, a, reload) {
          final (title, sub) = switch (a.status) {
            'pending' => ('Waiting for counsellor', 'Requested ${Fmt.relDay(a.createdAt)?.toLowerCase() ?? 'on ${Fmt.day(a.createdAt)}'} at ${Fmt.time(a.createdAt)}. Most requests are answered within 24 hours.'),
            'confirmed' => ('You’re booked in', a.online ? 'The video link opens 10 minutes before the session.' : 'Please arrive a few minutes early at ${a.location}.'),
            'reschedule_requested' => ('Waiting for the new time', 'You asked to move to ${Fmt.dateTime(Fmt.parse(a.proposal!['start']))}. Your current time stays reserved until it’s confirmed.'),
            'reschedule_proposed' => ('${a.counsellorName} proposed a new time', 'New time: ${Fmt.dateTime(Fmt.parse(a.proposal!['start']))}${(a.proposal!['reason'] as String?)?.isNotEmpty == true ? ' — “${a.proposal!['reason']}”' : ''}'),
            'declined' => ('Request declined', a.decline?['message'] as String? ?? a.decline?['reason'] as String? ?? ''),
            'cancelled' => ('Appointment cancelled', a.cancel?['by'] == 'system' ? 'It wasn’t confirmed in time, so the slot was released.' : (a.cancel?['reason'] as String?)?.isNotEmpty == true ? '“${a.cancel!['reason']}”' : 'This booking is no longer active.'),
            'completed' => ('Session completed', 'You can book a follow-up whenever you’re ready.'),
            _ => ('Session missed', 'You can book again any time.'),
          };
          final style = switch (a.statusTone) { Tone.amber => HeroStyle.amber, Tone.red => HeroStyle.alert, Tone.green => HeroStyle.soft, _ => HeroStyle.white };
          final suggested = ((a.decline?['suggestedSlots'] as List?) ?? []).cast<String>();
          final canJoin = a.status == 'confirmed' && a.online && a.meetingLink != null && a.start.difference(DateTime.now()).inMinutes <= 10 && !a.isPast;
          return MbPage(
            title: 'Appointment',
            subtitle: 'Booking ${a.reference}',
            onRefresh: reload,
            children: [
              HeroCard(
                style: style,
                eyebrow: 'Current status',
                badge: a.statusLabel,
                badgeTone: a.statusTone,
                title: title,
                sub: sub,
                actions: [
                  if (a.status == 'reschedule_proposed') ...[
                    MbButton('Keep original', kind: BtnKind.secondary, height: 46, fontSize: 14.5, onPressed: () => _respond(a, false)),
                    MbButton('Accept new time', height: 46, fontSize: 14.5, onPressed: () => _respond(a, true)),
                  ],
                  if (canJoin) MbButton('Join video session', icon: 'videocam', height: 46, onPressed: () => launchUrl(Uri.parse(a.meetingLink!), mode: LaunchMode.externalApplication)),
                ],
              ),
              TimelineCard(a.timeline),
              KvCard([
                ('Counsellor', a.counsellorName),
                ('Date', Fmt.dayYear(a.start)),
                ('Time', a.timeRange),
                ('Meeting', a.online ? (a.meetingLink != null ? 'Online · secure video link' : 'Online · link after confirmation') : 'In person · ${a.location}'),
                if (a.note.isNotEmpty) ('Your note', 'Shared with your counsellor only'),
              ]),
              if (suggested.isNotEmpty) ...[
                const SectionHeader('Suggested times'),
                Txt('${a.counsellorName} suggested these instead. Tap one to book it.', size: TxtSize.sm),
                ListCards([
                  for (final s in suggested)
                    ListItemData(icon: 'event_available', title: Fmt.dateTime(s), sub: a.modeLabel, onTap: () async {
                      final c = await guard(context, () => api.get('/counsellors/${a.counsellor['id']}'));
                      if (c == null || !context.mounted) return;
                      final draft = BookingDraft(c['counsellor'] as Map<String, dynamic>)
                        ..mode = a.mode
                        ..date = Fmt.dateStr(Fmt.sl(Fmt.parse(s)))
                        ..slot = {'start': s, 'end': Fmt.parse(s).add(a.end.difference(a.start)).toUtc().toIso8601String(), 'time': ''};
                      push(context, BookReviewScreen(draft: draft), root: true, name: 'book');
                    }),
                ]),
              ],
              if (a.isActive)
                ToggleTile(
                  icon: 'notifications_active',
                  title: 'Reminders',
                  sub: 'We’ll remind you 24 hours and 1 hour before.',
                  value: a.remindersOn,
                  onChanged: (v) async {
                    final r = await guard(context, () => api.patch('/appointments/${a.id}/reminders', {'on': v}));
                    if (r != null) reload();
                  },
                ),
            ],
            foot: a.canChange && !a.isPast
                ? [
                    MbButton('Reschedule', icon: 'update', onPressed: () async {
                      await push(context, RescheduleScreen(appointment: a), root: true, name: 'resched');
                      reload();
                    }),
                    MbButton(a.status == 'pending' ? 'Cancel request' : 'Cancel appointment', kind: BtnKind.dangerSoft, onPressed: () => _cancel(a)),
                  ]
                : (a.status == 'reschedule_requested' || a.status == 'reschedule_proposed')
                    ? [MbButton('Cancel appointment', kind: BtnKind.dangerSoft, onPressed: () => _cancel(a))]
                    : (!a.isActive ? [MbButton('Book a new session', kind: BtnKind.secondary, onPressed: () => push(context, const CounsellorListScreen()))] : const []),
          );
        },
      );
}

/// M1-23
class CancelSuccessScreen extends StatelessWidget {
  const CancelSuccessScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: [
          StateView(icon: 'event_busy', tone: Tone.grey, title: 'Appointment cancelled', text: '${appointment.counsellorName} has been notified and the slot is free for others.'),
          KvCard([('Booking', appointment.reference), ('Status', 'Cancelled')]),
        ],
        foot: [
          MbButton('Book a new session', onPressed: () => replace(context, const CounsellorListScreen())),
          MbButton('Back', kind: BtnKind.secondary, onPressed: () => Navigator.of(context).pop()),
        ],
      );
}
