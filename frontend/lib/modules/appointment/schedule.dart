// MEMBER 1 — Appointment Management: counsellor appointment list, calendar and propose new time.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../features/counsellor/counsellor_shell.dart';
import '../../state/auth.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../availability/availability.dart';
import '../counselling_session/sessions.dart';
import '../referral/counsellor_referrals.dart';
import 'booking.dart';
import 'requests.dart';

export '../availability/availability.dart' show AvailabilityScreen;

/// M2-06 / M2-50 / M2-51
class CounsellorAppointmentsScreen extends StatefulWidget {
  const CounsellorAppointmentsScreen({super.key});

  @override
  State<CounsellorAppointmentsScreen> createState() => _CounsellorAppointmentsScreenState();
}

class _CounsellorAppointmentsScreenState extends State<CounsellorAppointmentsScreen> {
  int _seg = 0;
  static const _scopes = ['today', 'upcoming', 'past'];

  @override
  Widget build(BuildContext context) {
    final seg = Segmented(items: const ['Today', 'Upcoming', 'Past'], index: _seg, onChanged: (i) => setState(() => _seg = i));
    return Loader<List<Appointment>>(
      key: ValueKey(_seg),
      load: () async => Appointment.list((await api.get('/appointments', query: {'scope': _scopes[_seg]}))['appointments']),
      wrap: (c) => MbPage(title: 'Appointments', children: [seg, c]),
      builder: (context, list, reload) {
        final shown = _seg == 1 ? list.where((a) => a.status != 'pending').toList() : list;
        return MbPage(
          title: 'Appointments',
          onRefresh: reload,
          children: [
            seg,
            if (shown.isEmpty)
              StateView(
                icon: _seg == 0 ? 'event_available' : 'calendar_month',
                tone: Tone.grey,
                title: ['No sessions today', 'No upcoming appointments', 'No past sessions'][_seg],
                text: ['Your calendar is open. Students can book any free slot.', 'Check your availability so students can find open times.', 'Completed sessions will appear here.'][_seg],
              )
            else
              ListCards([
                for (final a in shown)
                  counsellorApptItem(a, showDate: _seg != 0, onTap: () async {
                    await push(context, CounsellorAppointmentScreen(id: a.id));
                    reload();
                  }),
              ]),
          ],
          foot: shown.isEmpty && _seg == 1 ? [MbButton('Open availability', kind: BtnKind.secondary, onPressed: () => push(context, const AvailabilityScreen()))] : const [],
        );
      },
    );
  }
}

/// M2-07 — month view with booked / pending marks and the selected day's agenda.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late int _y = Fmt.nowSl().year;
  late int _m = Fmt.nowSl().month;
  late String _date = Fmt.todayStr();
  Map<String, dynamic>? _marks;
  Map<String, dynamic>? _day;
  ApiException? _error;

  String get _month => '$_y-${_m.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadDay();
  }

  Future<void> _loadMonth() async {
    try {
      final r = await api.get('/staff/calendar', query: {'month': _month});
      if (mounted) setState(() => _marks = (r['days'] as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadDay() async {
    setState(() => _day = null);
    try {
      final r = await api.get('/staff/day', query: {'date': _date});
      if (mounted) setState(() {
        _day = r;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadMonth(), _loadDay()]);
  }

  void _shift(int d) {
    setState(() {
      _m += d;
      if (_m == 0) {
        _m = 12;
        _y--;
      } else if (_m == 13) {
        _m = 1;
        _y++;
      }
      _marks = null;
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final marks = <int, Color>{};
    _marks?.forEach((date, v) {
      if (!date.startsWith(_month)) return;
      marks[int.parse(date.substring(8))] = (v['pending'] as num) > 0 ? C.markLow : C.markGood;
    });
    final day = _day;
    final appts = day == null ? <Appointment>[] : Appointment.list(day['appointments']);
    final blocks = day == null ? <Map<String, dynamic>>[] : (day['blocks'] as List).cast<Map<String, dynamic>>();
    final open = day == null ? <String>[] : (day['openSlots'] as List).cast<String>();
    return MbPage(
      title: 'Calendar',
      root: true,
      onRefresh: _refresh,
      actions: [
        HeaderAction('view_list', tooltip: 'All appointments', onTap: () => push(context, const CounsellorAppointmentsScreen())),
        HeaderAction('tune', tooltip: 'Availability', onTap: () async {
          await push(context, const AvailabilityScreen());
          _refresh();
        }),
      ],
      children: [
        CalendarCard(
          year: _y,
          month: _m,
          marks: marks,
          loading: _marks == null,
          selected: _date.startsWith(_month) ? int.parse(_date.substring(8)) : null,
          onPrev: () => _shift(-1),
          onNext: () => _shift(1),
          onSelect: (d) {
            setState(() => _date = '$_month-${d.toString().padLeft(2, '0')}');
            _loadDay();
          },
          legend: const [(C.markGood, 'Booked'), (C.markLow, 'Pending')],
        ),
        SectionHeader(Fmt.longDateStr(_date)),
        if (_error != null)
          ErrorBlock(error: _error!, onRetry: _refresh)
        else if (day == null)
          const LoadingList(n: 3)
        else if (appts.isEmpty && blocks.isEmpty && open.isEmpty)
          BannerCard(tone: Tone.grey, icon: 'event_busy', text: day['working'] == true ? 'Fully booked or past.' : 'Not a working day.')
        else
          ListCards([
            for (final b in blocks)
              ListItemData(icon: 'block', tone: Tone.grey, title: b['allDay'] == true ? 'All day · Blocked' : '${Fmt.hhmm(b['from'] as String)} – ${Fmt.hhmmAmPm(b['to'] as String)} · Blocked', sub: (b['reason'] as String?)?.isNotEmpty == true ? b['reason'] as String : 'Private'),
            for (final a in appts)
              ListItemData(
                avatar: a.student['initials'] as String? ?? '',
                title: '${Fmt.time(a.start)} · ${a.studentName}',
                sub: a.modeLabel,
                badge: a.statusLabel,
                badgeTone: a.statusTone,
                onTap: () async {
                  await push(context, a.status == 'pending' || a.status == 'reschedule_requested' ? RequestDetailScreen(id: a.id) : CounsellorAppointmentScreen(id: a.id));
                  _refresh();
                },
              ),
            if (open.isNotEmpty)
              ListItemData(icon: 'event_available', tone: Tone.grey, title: '${open.length} open slot${open.length == 1 ? '' : 's'}', sub: '${open.take(4).map(Fmt.hhmm).join(', ')}${open.length > 4 ? '…' : ''} · visible to students'),
          ]),
      ],
    );
  }
}

/// M2-08 — appointment details from the counsellor's side.
class CounsellorAppointmentScreen extends StatefulWidget {
  const CounsellorAppointmentScreen({super.key, required this.id});
  final String id;

  @override
  State<CounsellorAppointmentScreen> createState() => _CounsellorAppointmentScreenState();
}

class _CounsellorAppointmentScreenState extends State<CounsellorAppointmentScreen> {
  final _key = GlobalKey<LoaderState<Appointment>>();

  Future<void> _cancel(Appointment a) async {
    final r = await showMbSheet(
      context,
      icon: 'event_busy',
      tone: Tone.red,
      title: 'Cancel this session?',
      text: 'The student is notified immediately. Please include a reason.',
      areaHint: 'Reason for student',
      actions: [
        SheetAction('Cancel session', kind: BtnKind.danger, run: (text) async {
          if (text.isEmpty) throw ApiException(400, 'VALIDATION_ERROR', 'Please include a reason for the student.');
          await api.post('/appointments/${a.id}/cancel', {'reason': text});
          return true;
        }),
        const SheetAction('Keep session', kind: BtnKind.ghost),
      ],
    );
    if (r == 'Cancel session' && mounted) {
      replace(
        context,
        MbPage(
          bg: PageBg.white,
          children: [StateView(icon: 'event_busy', tone: Tone.grey, title: 'Session cancelled', text: '${a.studentName.split(' ').first} has been notified and the slot is open to other students.')],
          foot: [Builder(builder: (c) => MbButton('Done', onPressed: () => Navigator.of(c).pop()))],
        ),
      );
    }
  }

  Future<void> _complete(Appointment a, {bool noShow = false}) async {
    if (noShow) {
      final r = await showMbSheet(context, icon: 'person_off', tone: Tone.amber, title: 'Mark as missed?', text: 'Use this if the student didn’t attend. It’s recorded for anonymous reporting only.', actions: [
        SheetAction('Mark as missed', kind: BtnKind.danger, run: (_) async {
          await api.post('/appointments/${a.id}/complete', {'noShow': true});
          return true;
        }),
        const SheetAction('Go back', kind: BtnKind.ghost),
      ]);
      if (r == 'Mark as missed') _key.currentState?.reload();
      return;
    }
    await push(context, SessionNotesScreen(appointment: a, completeAfterSave: true), root: true);
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => Loader<Appointment>(
        key: _key,
        load: () async => Appointment((await api.get('/appointments/${widget.id}'))['appointment'] as Map<String, dynamic>),
        wrap: (c) => MbPage(title: 'Appointment', children: [c]),
        builder: (context, a, reload) {
          final started = a.session?['startedAt'] != null;
          final due = a.start.difference(DateTime.now()).inMinutes <= 15;
          final isRequest = a.status == 'pending' || a.status == 'reschedule_requested';
          final style = switch (a.status) { 'confirmed' => HeroStyle.soft, 'completed' => HeroStyle.white, 'cancelled' || 'declined' => HeroStyle.alert, _ => HeroStyle.amber };
          List<Widget> foot;
          if (isRequest) {
            foot = [MbButton('Review request', onPressed: () => replace(context, RequestDetailScreen(id: a.id)))];
          } else if (a.status == 'confirmed' && (started || a.isPast)) {
            foot = [
              MbButton('Complete session', icon: 'task_alt', onPressed: () => _complete(a)),
              MbButton('Student didn’t attend', kind: BtnKind.ghost, onPressed: () => _complete(a, noShow: true)),
            ];
          } else if (a.status == 'confirmed') {
            foot = [
              if (due) MbButton('Start session', icon: a.online ? 'videocam' : 'meeting_room', onPressed: () => startSession(context, a).then((_) => reload())),
              Row(children: [
                Expanded(child: MbButton('Reschedule', kind: due ? BtnKind.secondary : BtnKind.primary, icon: 'update', onPressed: () async {
                  await push(context, ProposeTimeScreen(appointment: a), root: true, name: 'propose');
                  reload();
                })),
                const SizedBox(width: 10),
                Expanded(child: MbButton('Cancel session', kind: BtnKind.dangerSoft, onPressed: () => _cancel(a))),
              ]),
            ];
          } else if (a.status == 'reschedule_proposed') {
            foot = [MbButton('Cancel session', kind: BtnKind.dangerSoft, onPressed: () => _cancel(a))];
          } else if (a.status == 'completed') {
            foot = [
              MbButton('Session notes', kind: BtnKind.secondary, icon: 'edit_note', onPressed: () => push(context, SessionNotesScreen(appointment: a), root: true)),
              if (!a.anonymous) MbButton('Refer to doctor', kind: BtnKind.ghost, icon: 'local_hospital', onPressed: () => push(context, ReferDoctorScreen(appointment: a), root: true, name: 'refer')),
            ];
          } else {
            foot = const [];
          }
          return MbPage(
            title: 'Appointment',
            subtitle: 'Booking ${a.reference}',
            onRefresh: reload,
            children: [
              HeroCard(
                style: style,
                eyebrow: a.statusLabel,
                badge: a.modeLabel,
                badgeTone: Tone.blue,
                title: a.studentName,
                sub: a.studentDetails,
              ),
              if (a.anonymous) const AnonymousBookingBanner(),
              if (a.status == 'reschedule_proposed')
                BannerCard(tone: Tone.blue, icon: 'update', title: 'Waiting for the student', text: 'You proposed ${Fmt.dateTime(Fmt.parse(a.proposal!['start']))}. Until they accept, the booking shows as “New time proposed” for both of you.'),
              KvCard([
                ('Date', Fmt.dayYear(a.start)),
                ('Time', a.timeRange),
                ('Place', a.online ? 'Online · secure video link' : a.location),
                ('Booked', Fmt.dateTime(a.createdAt)),
              ]),
              TimelineCard(a.timeline),
              if (a.note.isNotEmpty) ...[
                const SectionHeader('Note from student'),
                Txt('“${a.note}”'),
                const BannerCard(icon: 'lock', text: 'This note is shared only with you.'),
              ],
              LinksRow([
                ('View student information', () => push(context, StudentInfoScreen(appointmentId: a.id))),
                if (a.status == 'confirmed') ('Prepare', () => push(context, SessionPrepScreen(id: a.id))),
              ]),
            ],
            foot: foot,
          );
        },
      );
}

/// M2-16 → M2-18 — propose a new time; the student must accept (FR3).
class ProposeTimeScreen extends StatefulWidget {
  const ProposeTimeScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<ProposeTimeScreen> createState() => _ProposeTimeScreenState();
}

class _ProposeTimeScreenState extends State<ProposeTimeScreen> {
  String? _date;
  Map<String, dynamic>? _slot;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final me = context.read<AuthState>().user!['id'] as String;
    return MbPage(
      title: 'Propose new time',
      subtitle: a.studentName,
      children: [
        AvailabilityCalendar(monthUrl: '/counsellors/$me/month', excludeId: a.id, selected: _date, legend: false, onSelect: (v) => setState(() {
              _date = v;
              _slot = null;
            })),
        if (_date != null) ...[
          SectionHeader('Free on ${Fmt.shortDateStr(_date!)}'),
          DaySlots(url: '/counsellors/$me/slots', excludeId: a.id, date: _date!, selected: _slot, onSelect: (s) => setState(() => _slot = s), onNextOpening: (s) => setState(() {
                _date = s['date'] as String;
                _slot = s;
              })),
        ],
        MbField(label: 'Reason for student', controller: _reason, type: FieldType.area, rows: 2, hint: 'e.g. I have a clinic meeting on Thursday', maxLength: 500),
      ],
      foot: [
        MbButton('Review proposal', onPressed: _slot == null ? null : () => push(context, _ProposeReview(appointment: a, slot: _slot!, reason: _reason.text.trim()), root: true, name: 'propose')),
      ],
    );
  }
}

class _ProposeReview extends StatefulWidget {
  const _ProposeReview({required this.appointment, required this.slot, required this.reason});
  final Appointment appointment;
  final Map<String, dynamic> slot;
  final String reason;

  @override
  State<_ProposeReview> createState() => _ProposeReviewState();
}

class _ProposeReviewState extends State<_ProposeReview> {
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await api.post('/appointments/${widget.appointment.id}/reschedule', {'start': widget.slot['start'], 'reason': widget.reason});
      if (!mounted) return;
      popFlow(context, 'propose');
      final first = widget.appointment.studentName.split(' ').first;
      push(
        context,
        MbPage(
          bg: PageBg.white,
          children: [
            StateView(icon: 'update', tone: Tone.blue, title: 'New time proposed', text: 'We’ve notified $first. You’ll see the update when they respond.'),
            KvCard([('Proposed', Fmt.dateTime(widget.slot['start'])), ('Status', 'Awaiting student')]),
          ],
          foot: [Builder(builder: (c) => MbButton('Done', onPressed: () => Navigator.of(c).pop()))],
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
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final s = widget.slot;
    return MbPage(
      title: 'Review proposal',
      children: [
        CompareCard(fromLabel: 'Current', fromA: Fmt.dayYear(a.start), fromB: '${Fmt.time(a.start)} · ${a.modeLabel}', toLabel: 'Proposed', toA: Fmt.dayYear(s['start']), toB: '${Fmt.time(s['start'])} · ${a.modeLabel}'),
        Txt('${a.studentName.split(' ').first} will need to accept. Until then the booking shows as “New time proposed” for both of you.', size: TxtSize.sm),
      ],
      foot: [MbButton('Send proposal', loading: _busy, onPressed: _send)],
    );
  }
}
