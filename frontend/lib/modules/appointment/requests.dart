// MEMBER 1 — Appointment Management: update appointment status (counsellor accept / decline).
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../features/counsellor/counsellor_shell.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../counselling_session/sessions.dart';
import 'schedule.dart';

/// M2-09 / M2-49 — every pending request in one inbox (FR6).
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  int _chip = 0;

  @override
  Widget build(BuildContext context) => Loader<List<Appointment>>(
        load: () async => Appointment.list((await api.get('/appointments', query: {'scope': 'requests'}))['appointments']),
        wrap: (c) => MbPage(title: 'Requests', root: true, children: [c]),
        builder: (context, all, reload) {
          final list = all.where((a) => switch (_chip) { 1 => a.online, 2 => !a.online, 3 => a.duplicateFlag, _ => true }).toList();
          return MbPage(
            title: 'Requests',
            subtitle: all.isEmpty ? null : '${all.length} waiting for you',
            root: true,
            onRefresh: reload,
            children: [
              Chips(items: const ['All', 'Online', 'In person', 'Flagged'], selected: {_chip}, onTap: (i) => setState(() => _chip = i)),
              if (list.isEmpty)
                StateView(icon: 'inbox', tone: Tone.grey, title: all.isEmpty ? 'No pending requests' : 'Nothing in this filter', text: all.isEmpty ? 'New booking requests will appear here.' : 'Try another filter.')
              else
                ListCards([
                  for (final a in list)
                    counsellorApptItem(a, showDate: true, onTap: () async {
                      await push(context, a.duplicateFlag ? DuplicateScreen(id: a.id) : RequestDetailScreen(id: a.id));
                      reload();
                    }),
                ]),
            ],
            foot: all.isEmpty ? [MbButton('Review availability', kind: BtnKind.secondary, onPressed: () => push(context, const AvailabilityScreen()))] : const [],
          );
        },
      );
}

/// M2-10 — a new request or a student's reschedule request.
class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  Future<Map<String, dynamic>> _load() async {
    final r = await Future.wait([api.get('/appointments/${widget.id}/duplicates'), api.get('/appointments/${widget.id}/student')]);
    return {...r[0], 'info': r[1]};
  }

  Future<void> _accept(Appointment a) async {
    final isMove = a.status == 'reschedule_requested';
    final when = isMove ? Fmt.parse(a.proposal!['start']) : a.start;
    Appointment? done;
    await showMbSheet(
      context,
      icon: 'event_available',
      title: isMove ? 'Confirm the new time?' : 'Accept this request?',
      text: '${a.studentName.split(' ').first} will see “Confirmed” straight away and the slot will be locked in your calendar.',
      rows: [('Slot', Fmt.dateTime(when, relative: false)), ('Meeting', a.modeLabel)],
      actions: [
        SheetAction('Accept and notify', run: (_) async {
          final r = await api.post('/appointments/${a.id}/accept');
          done = Appointment(r['appointment'] as Map<String, dynamic>);
          return true;
        }),
        const SheetAction('Go back', kind: BtnKind.ghost),
      ],
    );
    if (done != null && mounted) replace(context, RequestAcceptedScreen(appointment: done!));
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: _load,
        wrap: (c) => MbPage(title: 'Booking request', children: [c]),
        builder: (context, d, reload) {
          final a = Appointment(d['appointment'] as Map<String, dynamic>);
          final others = (d['others'] as List).cast<Map<String, dynamic>>();
          final info = d['info'] as Map<String, dynamic>;
          final s = info['student'] as Map<String, dynamic>;
          final sessions = info['sessions'] as Map<String, dynamic>;
          final isMove = a.status == 'reschedule_requested';
          final open = a.status == 'pending' || isMove;
          return MbPage(
            title: isMove ? 'Reschedule request' : 'Booking request',
            onRefresh: reload,
            children: [
              ListCards([
                ListItemData(
                  avatar: s['initials'] as String,
                  title: s['name'] as String,
                  sub: [s['studentId'], if (s['year'] != null) 'Year ${s['year']}', (s['faculty'] as String?)?.replaceFirst('Faculty of ', '')].whereType<String>().join(' · '),
                  onTap: () => push(context, StudentInfoScreen(appointmentId: a.id)),
                ),
              ]),
              if (isMove)
                CompareCard(
                  fromLabel: 'Current',
                  fromA: Fmt.dayYear(a.start),
                  fromB: '${a.timeRange} · ${a.modeLabel}',
                  toLabel: 'Requested',
                  toA: Fmt.dayYear(a.proposal!['start']),
                  toB: '${Fmt.timeRange(a.proposal!['start'], a.proposal!['end'])} · ${a.modeLabel}',
                )
              else
                KvCard([
                  ('Requested slot', Fmt.dateTime(a.start, relative: false)),
                  ('Meeting', a.modeLabel),
                  ('Submitted', Fmt.dateTime(a.createdAt)),
                  ('Previous sessions', (sessions['completed'] as num) == 0 ? 'None' : '${sessions['completed']} with you'),
                ]),
              if (!open)
                BannerCard(tone: a.statusTone, icon: 'info', title: 'Already ${a.statusLabel.toLowerCase()}', text: 'This request has been handled.')
              else if (others.isNotEmpty)
                BannerCard(tone: Tone.red, icon: 'content_copy', title: '${others.length + 1} active requests for one student', text: 'Check before accepting so a slot isn’t wasted.', link: 'Review', onLink: () => push(context, DuplicateScreen(id: a.id)))
              else
                const BannerCard(icon: 'check_circle', title: 'No conflicts', text: 'No other active booking for this student, and the slot is free in your calendar.'),
              if (a.note.isNotEmpty) ...[const SectionHeader('Note from student'), Txt('“${a.note}”')],
              if (isMove && (a.proposal?['reason'] as String?)?.isNotEmpty == true) ...[const SectionHeader('Reason for moving'), Txt('“${a.proposal!['reason']}”')],
              if (open && !isMove) LinksRow([('Suggest another time', () => push(context, ProposeTimeScreen(appointment: a), root: true, name: 'propose'))]),
            ],
            footRow: true,
            foot: open
                ? [
                    MbButton(isMove ? 'Keep original' : 'Decline', kind: BtnKind.dangerSoft, onPressed: () async {
                      await push(context, DeclineScreen(appointment: a), root: true, name: 'decline');
                      reload();
                    }),
                    MbButton(isMove ? 'Confirm new time' : 'Accept', onPressed: () => _accept(a)),
                  ]
                : const [],
          );
        },
      );
}

/// M2-12
class RequestAcceptedScreen extends StatelessWidget {
  const RequestAcceptedScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: [
          StateView(icon: 'check_circle', title: 'Booking confirmed', text: '${appointment.studentName.split(' ').first} now sees this as confirmed. Reminders go out automatically.'),
          TimelineCard(appointment.timeline),
        ],
        foot: [
          MbButton('Back to requests', onPressed: () => Navigator.of(context).pop()),
          MbButton('View appointment', kind: BtnKind.secondary, onPressed: () => replace(context, CounsellorAppointmentScreen(id: appointment.id))),
        ],
      );
}

/// M2-13 / M2-14 — decline with a reason and optional alternatives.
class DeclineScreen extends StatefulWidget {
  const DeclineScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<DeclineScreen> createState() => _DeclineScreenState();
}

class _DeclineScreenState extends State<DeclineScreen> {
  static const _reasons = ['Time is no longer available', 'Better suited to another counsellor', 'Needs a medical referral first', 'Other'];
  int _reason = 0;
  final _msg = TextEditingController(text: 'I’m not free at that time, but I have other openings this week.');
  bool _suggest = true;
  bool _busy = false;

  bool get _isMove => widget.appointment.status == 'reschedule_requested';

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await api.post('/appointments/${widget.appointment.id}/decline', {'reason': _reasons[_reason], 'message': _msg.text.trim(), 'suggestSlots': _suggest && !_isMove});
      if (!mounted) return;
      popFlow(context, 'decline');
      push(
        context,
        MbPage(
          bg: PageBg.white,
          children: [
            StateView(
              icon: 'cancel',
              tone: Tone.grey,
              title: _isMove ? 'Original time kept' : 'Request declined',
              text: _isMove ? '${widget.appointment.studentName.split(' ').first} has been told the original time stays.' : '${widget.appointment.studentName.split(' ').first} has your message${_suggest ? ' and three suggested times' : ''}.',
            ),
          ],
          foot: [Builder(builder: (c) => MbButton('Back to requests', onPressed: () => Navigator.of(c).pop()))],
        ),
        root: true,
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: _isMove ? 'Keep original time' : 'Decline request',
        subtitle: '${widget.appointment.studentName} · ${Fmt.day(widget.appointment.start)}',
        children: [
          const SectionHeader('Reason'),
          OptionsList(items: [for (final r in _reasons) OptionItem(r)], selected: _reason, onSelect: (i) => setState(() => _reason = i)),
          MbField(label: 'Message to student', controller: _msg, type: FieldType.area, rows: 3, maxLength: 1000),
          if (!_isMove) ToggleTile(title: 'Suggest my next free slots', sub: 'Student sees 3 alternatives with one tap to rebook', value: _suggest, onChanged: (v) => setState(() => _suggest = v)),
        ],
        foot: [MbButton(_isMove ? 'Keep original time' : 'Decline request', kind: BtnKind.danger, loading: _busy, onPressed: _submit)],
      );
}

/// M2-15 — two active requests for one student (FR7).
class DuplicateScreen extends StatelessWidget {
  const DuplicateScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/appointments/$id/duplicates'),
        wrap: (c) => MbPage(title: 'Possible duplicate', children: [c]),
        builder: (context, d, reload) {
          final a = Appointment(d['appointment'] as Map<String, dynamic>);
          final others = (d['others'] as List).cast<Map<String, dynamic>>();
          final first = a.studentName.split(' ').first;
          return MbPage(
            title: 'Possible duplicate',
            subtitle: a.studentName,
            children: [
              BannerCard(tone: Tone.red, icon: 'content_copy', title: '${others.length + 1} active requests for one student', text: 'Students sometimes book twice when they can’t see a confirmation.'),
              ListCards([
                ListItemData(avatar: 'ME', title: 'With you', sub: '${Fmt.dateTime(a.start)} · ${a.modeLabel}', badge: a.statusLabel, badgeTone: a.statusTone),
                for (final o in others)
                  ListItemData(
                    avatar: (o['counsellor'] as Map)['initials'] as String,
                    title: 'With ${(o['counsellor'] as Map)['name']}',
                    sub: '${Fmt.dateTime(o['start'])} · ${modeLabel(o['mode'] as String)}',
                    badge: o['statusLabel'] as String,
                    badgeTone: Tone.of(o['statusTone'] as String?),
                  ),
              ]),
              if (others.isEmpty) const BannerCard(icon: 'check_circle', text: 'The other booking has since been cancelled. This request is safe to accept.'),
              Txt('Ask $first which session they’d like to keep. The other slot can go to another student.', size: TxtSize.sm),
            ],
            foot: [
              MbButton('Ask student to choose', onPressed: () async {
                final r = await guard(context, () => api.post('/appointments/${a.id}/ask-student'));
                if (r != null && context.mounted) {
                  toast(context, '$first has been asked to keep one booking.');
                  Navigator.of(context).pop();
                }
              }),
              MbButton('Decline mine', kind: BtnKind.dangerSoft, onPressed: () => push(context, DeclineScreen(appointment: a), root: true, name: 'decline')),
              MbButton('Review request', kind: BtnKind.ghost, onPressed: () => replace(context, RequestDetailScreen(id: a.id))),
            ],
          );
        },
      );
}
