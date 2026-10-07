// MEMBER 1 — Appointment Management: create appointment (student booking) and reschedule.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../features/student/counsellors.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'appointments.dart';

/// Booking in progress (FR2, FR3). Passed through the four steps.
class BookingDraft {
  BookingDraft(this.counsellor);
  final Map<String, dynamic> counsellor;
  String? date; // YYYY-MM-DD (Sri Lanka)
  Map<String, dynamic>? slot; // {time, start, end}
  String mode = 'online';
  String note = '';

  String get counsellorId => counsellor['id'] as String;
  String get name => counsellor['name'] as String;
  String get lastName => name.split(' ').last;
  List<String> get modes => ((counsellor['modes'] as List?) ?? const ['online', 'in_person']).cast<String>();
}

/// Month calendar showing which days still have free slots for a staff member.
class AvailabilityCalendar extends StatefulWidget {
  const AvailabilityCalendar({super.key, required this.monthUrl, required this.selected, required this.onSelect, this.excludeId, this.legend = true});
  final String monthUrl; // e.g. /counsellors/<id>/month
  final String? selected;
  final ValueChanged<String> onSelect;
  final String? excludeId;
  final bool legend;

  @override
  State<AvailabilityCalendar> createState() => _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends State<AvailabilityCalendar> {
  late int _y, _m;
  Map<String, dynamic>? _days; // date -> {free,total}
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = widget.selected != null ? Fmt.fromDateStr(widget.selected!) : Fmt.nowSl();
    _y = base.year;
    _m = base.month;
    _load();
  }

  String get _month => '$_y-${_m.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get(widget.monthUrl, query: {'month': _month, 'exclude': widget.excludeId});
      if (!mounted) return;
      setState(() {
        _days = {for (final d in (r['days'] as List)) d['date'] as String: d};
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _shift(int delta) {
    setState(() {
      _m += delta;
      if (_m == 0) {
        _m = 12;
        _y -= 1;
      } else if (_m == 13) {
        _m = 1;
        _y += 1;
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = Fmt.nowSl();
    final last = Fmt.fromDateStr(Fmt.addDays(Fmt.todayStr(), 21));
    final canPrev = _y > now.year || (_y == now.year && _m > now.month);
    final canNext = _y < last.year || (_y == last.year && _m < last.month);
    final avail = <int>{};
    final marks = <int, Color>{};
    _days?.forEach((date, d) {
      final day = int.parse(date.substring(8));
      if ((d['free'] as num) > 0) avail.add(day);
      if ((d['total'] as num) > 0 && (d['free'] as num) == 0) marks[day] = const Color(0xFFB4BCB6);
    });
    final sel = widget.selected != null && widget.selected!.startsWith(_month) ? int.parse(widget.selected!.substring(8)) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CalendarCard(
        year: _y,
        month: _m,
        selected: sel,
        available: avail,
        marks: marks,
        loading: _loading,
        onPrev: canPrev ? () => _shift(-1) : null,
        onNext: canNext ? () => _shift(1) : null,
        onSelect: (d) => widget.onSelect('$_month-${d.toString().padLeft(2, '0')}'),
        legend: widget.legend ? const [(C.markGood, 'Has free slots'), (Color(0xFFB4BCB6), 'Fully booked')] : const [],
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: BannerCard(tone: Tone.red, icon: 'wifi_off', text: _error, link: 'Try again', onLink: _load)),
    ]);
  }
}

/// Slots for one day, split into morning and afternoon.
class DaySlots extends StatefulWidget {
  const DaySlots({super.key, required this.url, required this.date, required this.selected, required this.onSelect, this.excludeId, this.onNextOpening});
  final String url; // e.g. /counsellors/<id>/slots
  final String date;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final String? excludeId;
  final ValueChanged<Map<String, dynamic>>? onNextOpening;

  @override
  State<DaySlots> createState() => _DaySlotsState();
}

class _DaySlotsState extends State<DaySlots> {
  Future<Map<String, dynamic>>? _f;

  @override
  void initState() {
    super.initState();
    _f = _fetch();
  }

  @override
  void didUpdateWidget(covariant DaySlots old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _f = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() => api.get(widget.url, query: {'date': widget.date, 'exclude': widget.excludeId});

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return ErrorBlock(error: e is ApiException ? e : ApiException(0, 'NETWORK', 'Couldn’t load times.'), onRetry: () => setState(() => _f = _fetch()));
          }
          if (!snap.hasData) return const LoadingList(n: 2);
          final slots = (snap.data!['slots'] as List).cast<Map<String, dynamic>>();
          final next = snap.data!['nextOpening'] as Map<String, dynamic>?;
          if (!slots.any((s) => s['available'] == true)) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StateView(
                icon: 'event_busy',
                tone: Tone.amber,
                title: 'No times left on this day',
                text: next != null ? 'The next opening is ${Fmt.longDateStr(next['date'] as String)} at ${Fmt.hhmmAmPm(next['time'] as String)}.' : 'There are no openings in the next three weeks.',
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              ),
              if (next != null && widget.onNextOpening != null) ...[
                const SizedBox(height: 14),
                MbButton('Choose ${Fmt.shortDateStr(next['date'] as String)}, ${Fmt.hhmm(next['time'] as String)}', onPressed: () => widget.onNextOpening!(next)),
              ],
            ]);
          }
          final morning = slots.where((s) => (s['time'] as String).compareTo('12:00') < 0).toList();
          final afternoon = slots.where((s) => (s['time'] as String).compareTo('12:00') >= 0).toList();
          Widget group(String title, List<Map<String, dynamic>> l) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SectionHeader(title),
                const SizedBox(height: 10),
                SlotsGrid(
                  labels: [for (final s in l) Fmt.hhmm(s['time'] as String)],
                  disabled: {for (var i = 0; i < l.length; i++) if (l[i]['available'] != true) i},
                  selected: l.indexWhere((s) => s['start'] == widget.selected?['start']).let((i) => i < 0 ? null : i),
                  onSelect: (i) => widget.onSelect(l[i]),
                ),
              ]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (morning.isNotEmpty) group('Morning', morning),
            if (morning.isNotEmpty && afternoon.isNotEmpty) const SizedBox(height: 14),
            if (afternoon.isNotEmpty) group('Afternoon', afternoon),
            const SizedBox(height: 14),
            const Txt('All times are Sri Lanka time (GMT+5:30). Crossed-out times are already taken.', size: TxtSize.xs),
          ]);
        },
      );
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Step 1 — M1-09
class BookDateScreen extends StatefulWidget {
  const BookDateScreen({super.key, required this.draft});
  final BookingDraft draft;

  @override
  State<BookDateScreen> createState() => _BookDateScreenState();
}

class _BookDateScreenState extends State<BookDateScreen> {
  BookingDraft get d => widget.draft;

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Choose a date',
        subtitle: d.name,
        children: [
          const StepsBar(n: 1, of: 4, label: 'Date'),
          AvailabilityCalendar(monthUrl: '/counsellors/${d.counsellorId}/month', selected: d.date, onSelect: (v) => setState(() {
                d.date = v;
                d.slot = null;
              })),
          const BannerCard(tone: Tone.blue, icon: 'info', text: 'Sessions are 30 minutes. Grey dates are fully booked or outside working days.'),
        ],
        foot: [MbButton('Continue', onPressed: d.date == null ? null : () => push(context, BookTimeScreen(draft: d), root: true, name: 'book'))],
      );
}

/// Step 2 — M1-10 / M1-35
class BookTimeScreen extends StatefulWidget {
  const BookTimeScreen({super.key, required this.draft});
  final BookingDraft draft;

  @override
  State<BookTimeScreen> createState() => _BookTimeScreenState();
}

class _BookTimeScreenState extends State<BookTimeScreen> {
  BookingDraft get d => widget.draft;

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Choose a time',
        subtitle: Fmt.longDateStr(d.date!),
        children: [
          const StepsBar(n: 2, of: 4, label: 'Time'),
          DaySlots(
            url: '/counsellors/${d.counsellorId}/slots',
            date: d.date!,
            selected: d.slot,
            onSelect: (s) => setState(() => d.slot = s),
            onNextOpening: (s) => setState(() {
              d.date = s['date'] as String;
              d.slot = s;
            }),
          ),
        ],
        foot: [MbButton('Continue', onPressed: d.slot == null ? null : () => push(context, BookMeetingScreen(draft: d), root: true, name: 'book'))],
      );
}

/// Step 3 — M1-11
class BookMeetingScreen extends StatefulWidget {
  const BookMeetingScreen({super.key, required this.draft});
  final BookingDraft draft;

  @override
  State<BookMeetingScreen> createState() => _BookMeetingScreenState();
}

class _BookMeetingScreenState extends State<BookMeetingScreen> {
  BookingDraft get d => widget.draft;
  late final _note = TextEditingController(text: d.note);

  @override
  void initState() {
    super.initState();
    if (!d.modes.contains(d.mode)) d.mode = d.modes.first;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = (d.counsellor['room'] as String?)?.isNotEmpty == true ? d.counsellor['room'] as String : 'Wellbeing Centre, Room 2.14, Main Building';
    final opts = [
      if (d.modes.contains('online')) ('online', const OptionItem('Online session', sub: 'Secure video link, join from anywhere', icon: 'videocam')),
      if (d.modes.contains('in_person')) ('in_person', OptionItem('In person', sub: room, icon: 'meeting_room')),
    ];
    return MbPage(
      title: 'How would you like to meet?',
      children: [
        const StepsBar(n: 3, of: 4, label: 'Meeting type'),
        OptionsList(items: [for (final o in opts) o.$2], selected: opts.indexWhere((o) => o.$1 == d.mode), onSelect: (i) => setState(() => d.mode = opts[i].$1)),
        MbField(label: 'Anything you’d like the counsellor to know? (optional)', controller: _note, type: FieldType.area, rows: 3, hint: 'e.g. I’ve been struggling to sleep before exams', maxLength: 1000),
        BannerCard(icon: 'lock', text: 'Only ${d.name} can read this note.'),
      ],
      foot: [
        MbButton('Review booking', onPressed: () {
          d.note = _note.text.trim();
          push(context, BookReviewScreen(draft: d), root: true, name: 'book');
        }),
      ],
    );
  }
}

/// Step 4 — M1-12 / M1-39 with the duplicate check shown before submit (FR7).
class BookReviewScreen extends StatefulWidget {
  const BookReviewScreen({super.key, required this.draft});
  final BookingDraft draft;

  @override
  State<BookReviewScreen> createState() => _BookReviewScreenState();
}

class _BookReviewScreenState extends State<BookReviewScreen> {
  BookingDraft get d => widget.draft;

  Future<void> _confirm() async {
    final start = d.slot!['start'];
    Appointment? created;
    ApiException? failure;
    await showMbSheet(
      context,
      icon: 'event_available',
      title: 'Send this request?',
      text: '${d.name} will review it. You can reschedule or cancel any time before the session.',
      rows: [('When', Fmt.dateTime(start, relative: false)), ('Meeting', modeLabel(d.mode))],
      actions: [
        SheetAction('Send request', run: (_) async {
          try {
            final r = await api.post('/appointments', {'counsellorId': d.counsellorId, 'start': start, 'mode': d.mode, 'note': d.note});
            created = Appointment(r['appointment'] as Map<String, dynamic>);
          } on ApiException catch (e) {
            if (e.code != 'SLOT_TAKEN' && e.code != 'DUPLICATE_BOOKING') rethrow;
            failure = e;
          }
          return true;
        }),
        const SheetAction('Go back', kind: BtnKind.ghost),
      ],
    );
    if (!mounted) return;
    if (created != null) {
      popFlow(context, 'book');
      push(context, BookingSuccessScreen(appointment: created!), root: true);
    } else if (failure?.code == 'SLOT_TAKEN') {
      push(context, BookingErrorScreen(message: failure!.message, draft: d), root: true, name: 'book');
    } else if (failure?.code == 'DUPLICATE_BOOKING' && failure!.details?['existing'] is Map<String, dynamic>) {
      showDuplicateSheet(context, Appointment(failure!.details!['existing'] as Map<String, dynamic>));
    }
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/appointments/active-check'),
        wrap: (c) => MbPage(title: 'Review booking', children: [const StepsBar(n: 4, of: 4, label: 'Review'), c]),
        builder: (context, check, reload) {
          final existing = check['existing'] == null ? null : Appointment(check['existing'] as Map<String, dynamic>);
          final blocked = existing != null && check['blocking'] == true;
          final s = d.slot!;
          if (blocked) {
            return MbPage(
              title: 'Review booking',
              children: [
                const StepsBar(n: 4, of: 4, label: 'Review'),
                BannerCard(tone: Tone.amber, icon: 'warning', title: 'You already have a ${existing.statusLabel.toLowerCase()} booking', text: 'Finish or change that one first so a slot isn’t wasted.', link: 'View it', onLink: () => push(context, AppointmentDetailScreen(id: existing.id), root: true)),
                KvCard([('Counsellor', existing.counsellorName), ('When', Fmt.dateTime(existing.start)), ('Status', existing.statusLabel)], title: 'Existing booking'),
              ],
              foot: [
                if (existing.canChange) MbButton('Reschedule existing', onPressed: () => push(context, RescheduleScreen(appointment: existing), root: true, name: 'resched')),
                MbButton('View existing booking', kind: BtnKind.secondary, onPressed: () => push(context, AppointmentDetailScreen(id: existing.id), root: true)),
              ],
            );
          }
          return MbPage(
            title: 'Review booking',
            children: [
              const StepsBar(n: 4, of: 4, label: 'Review'),
              KvCard([
                ('Counsellor', d.name),
                ('Date', Fmt.dayYear(s['start'])),
                ('Time', Fmt.timeRange(s['start'], s['end'])),
                ('Meeting', modeLabel(d.mode)),
                ('Your note', d.note.isEmpty ? 'None' : 'Added'),
              ]),
              const BannerCard(icon: 'verified', title: 'No other active booking', text: 'We checked: you don’t have another pending or confirmed appointment.'),
              const Txt('You’ll be notified as soon as the counsellor accepts, usually within 24 hours.', size: TxtSize.sm),
              LinksRow([
                ('Edit details', () {
                  popFlow(context, 'book');
                  push(context, BookDateScreen(draft: d), root: true, name: 'book');
                }),
              ]),
            ],
            foot: [MbButton('Submit request', onPressed: _confirm)],
          );
        },
      );
}

/// M1-15
class BookingSuccessScreen extends StatelessWidget {
  const BookingSuccessScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: [
          StateView(icon: 'check_circle', title: 'Request sent', text: 'We’ll notify you as soon as ${appointment.counsellorName} responds. You don’t need to book again.'),
          TimelineCard(appointment.timeline),
        ],
        foot: [
          MbButton('View booking', onPressed: () => replace(context, AppointmentDetailScreen(id: appointment.id), root: true)),
          MbButton('Back to home', kind: BtnKind.secondary, onPressed: () => popToFirst(context, root: true)),
        ],
      );
}

/// M1-36
class BookingErrorScreen extends StatelessWidget {
  const BookingErrorScreen({super.key, required this.message, required this.draft});
  final String message;
  final BookingDraft draft;

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: [StateView(icon: 'error', tone: Tone.red, title: 'We couldn’t send your request', text: message)],
        foot: [
          MbButton('Choose another time', onPressed: () {
            draft.slot = null;
            popFlow(context, 'book');
            push(context, BookTimeScreen(draft: draft), root: true, name: 'book');
          }),
          MbButton('Back to home', kind: BtnKind.secondary, onPressed: () => popToFirst(context, root: true)),
        ],
      );
}

// ─────────────────────────── Reschedule (FR3) ───────────────────────────

/// M1-19 — pick a new time. The current slot stays reserved until the change is confirmed.
class RescheduleScreen extends StatefulWidget {
  const RescheduleScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  String? _date;
  Map<String, dynamic>? _slot;
  Appointment get a => widget.appointment;
  String get _cid => a.counsellor['id'] as String;

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Reschedule',
        subtitle: 'Current: ${Fmt.dateTime(a.start)}',
        children: [
          BannerCard(
            tone: Tone.blue,
            icon: 'info',
            text: a.status == 'pending' ? 'This moves your existing request. It won’t create a second booking.' : 'Your current slot stays reserved until the new time is confirmed.',
          ),
          AvailabilityCalendar(monthUrl: '/counsellors/$_cid/month', excludeId: a.id, selected: _date, legend: false, onSelect: (v) => setState(() {
                _date = v;
                _slot = null;
              })),
          if (_date != null) ...[
            SectionHeader('Free on ${Fmt.shortDateStr(_date!)}'),
            DaySlots(
              url: '/counsellors/$_cid/slots',
              excludeId: a.id,
              date: _date!,
              selected: _slot,
              onSelect: (s) => setState(() => _slot = s),
              onNextOpening: (s) => setState(() {
                _date = s['date'] as String;
                _slot = s;
              }),
            ),
          ],
        ],
        foot: [MbButton('Review change', onPressed: _slot == null ? null : () => push(context, RescheduleReviewScreen(appointment: a, slot: _slot!), root: true, name: 'resched'))],
      );
}

/// M1-20
class RescheduleReviewScreen extends StatefulWidget {
  const RescheduleReviewScreen({super.key, required this.appointment, required this.slot});
  final Appointment appointment;
  final Map<String, dynamic> slot;

  @override
  State<RescheduleReviewScreen> createState() => _RescheduleReviewScreenState();
}

class _RescheduleReviewScreenState extends State<RescheduleReviewScreen> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await api.post('/appointments/${widget.appointment.id}/reschedule', {'start': widget.slot['start'], 'reason': _reason.text.trim()});
      if (!mounted) return;
      final updated = Appointment(r['appointment'] as Map<String, dynamic>);
      popFlow(context, 'resched');
      push(context, RescheduleSuccessScreen(appointment: updated), root: true);
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
      title: 'Review change',
      children: [
        CompareCard(
          fromLabel: 'Current',
          fromA: Fmt.dayYear(a.start),
          fromB: '${a.timeRange} · ${a.modeLabel}',
          toLabel: 'New time',
          toA: Fmt.dayYear(s['start']),
          toB: '${Fmt.timeRange(s['start'], s['end'])} · ${a.modeLabel}',
        ),
        MbField(label: 'Reason (optional)', controller: _reason, type: FieldType.area, rows: 3, hint: 'e.g. I have a lab on Thursday morning', maxLength: 500),
        const Txt('This updates your existing booking. It won’t create a second one.', size: TxtSize.sm),
      ],
      foot: [MbButton('Confirm reschedule', loading: _busy, onPressed: _submit)],
    );
  }
}

/// M1-21
class RescheduleSuccessScreen extends StatelessWidget {
  const RescheduleSuccessScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final moved = a.status == 'pending';
    final when = moved ? a.start : Fmt.parse(a.proposal?['start'] ?? a.j['start']);
    return MbPage(
      bg: PageBg.white,
      children: [
        StateView(
          icon: 'update',
          tone: Tone.blue,
          title: moved ? 'Request updated' : 'Reschedule requested',
          text: moved ? 'Your request now asks for the new time. ${a.counsellorName} will review it.' : '${a.counsellorName} will confirm the new time. We’ll let you know.',
        ),
        KvCard([('New time', Fmt.dateTime(when)), ('Status', moved ? 'Pending' : 'Awaiting confirmation')]),
      ],
      foot: [
        MbButton('View booking', onPressed: () => replace(context, AppointmentDetailScreen(id: a.id), root: true)),
        MbButton('Back to home', kind: BtnKind.secondary, onPressed: () => popToFirst(context, root: true)),
      ],
    );
  }
}
