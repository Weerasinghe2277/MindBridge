// MEMBER 1 — Availability Management: add, view, edit and remove slots (hours, blocks).
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
final _times = [for (var m = 7 * 60; m <= 20 * 60; m += 30) '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}'];

String workingDaysLabel(List<int> d) {
  if (d.isEmpty) return 'None';
  final s = [...d]..sort();
  bool consecutive = true;
  for (var i = 1; i < s.length; i++) {
    if (s[i] != s[i - 1] + 1) consecutive = false;
  }
  if (consecutive && s.length > 2) return '${_days[s.first - 1].substring(0, 3)} – ${_days[s.last - 1].substring(0, 3)}';
  return s.map((x) => _days[x - 1].substring(0, 3)).join(', ');
}

Future<String?> _pickTime(BuildContext context, String title, String current) async {
  final v = await pickOption(context, title: title, options: [for (final t in _times) Fmt.hhmmAmPm(t)], current: Fmt.hhmmAmPm(current));
  return v == null ? null : _times[_times.map(Fmt.hhmmAmPm).toList().indexOf(v)];
}

/// M2-21 — availability overview (FR2). Students only see slots generated from this.
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  final _key = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _open(Widget page) async {
    await push(context, page, root: true);
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        key: _key,
        load: () => api.get('/staff/availability'),
        wrap: (c) => MbPage(title: 'Availability', children: [c]),
        builder: (context, d, reload) {
          final av = d['availability'] as Map<String, dynamic>;
          final week = (d['week'] as List).cast<Map<String, dynamic>>();
          final days = (av['workingDays'] as List).cast<int>();
          final lunch = av['lunchBreak'] as Map<String, dynamic>;
          final hours = '${Fmt.hhmm(av['startTime'] as String)} – ${Fmt.hhmm(av['endTime'] as String)}';
          final working = week.where((w) => w['working'] == true).toList();
          return MbPage(
            title: 'Availability',
            onRefresh: reload,
            children: [
              StatsGrid(cols: 3, [StatItem(workingDaysLabel(days), 'Working days'), StatItem(hours, 'Hours'), StatItem('${av['sessionLength']} min', 'Sessions')]),
              MenuCard([
                MenuItemData('date_range', 'Working days', value: workingDaysLabel(days), onTap: () => _open(WorkingDaysScreen(availability: av))),
                MenuItemData('schedule', 'Working hours', value: '$hours${lunch['enabled'] == true ? ' · break' : ''}', onTap: () => _open(WorkingHoursScreen(availability: av))),
                MenuItemData('timer', 'Session length', value: '${av['sessionLength']} min${(av['bufferMinutes'] as num) > 0 ? ' + ${av['bufferMinutes']}' : ''}', onTap: () => _open(SessionLengthScreen(availability: av))),
                MenuItemData('block', 'Blocked time', value: '${d['upcomingBlocks']} upcoming', onTap: () => _open(const BlockTimeScreen())),
              ]),
              if (working.isNotEmpty)
                BarsChart(
                  title: 'Open slots this week',
                  sub: 'Free slots left on each working day',
                  highlight: working.indexWhere((w) => w['date'] == Fmt.todayStr()),
                  items: [for (final w in working) BarDatum(_days[Fmt.fromDateStr(w['date'] as String).weekday - 1][0], (w['open'] as num).toDouble(), text: '${w['open']}')],
                ),
              MbButton('Preview what students see', kind: BtnKind.secondary, icon: 'visibility', onPressed: () => _open(const SlotPreviewScreen())),
            ],
          );
        },
      );
}

Future<bool> _saveAvailability(BuildContext context, Map<String, dynamic> body) async {
  final r = await guard(context, () => api.put('/staff/availability', body));
  if (r != null && context.mounted) {
    toast(context, 'Availability saved. Students see the change straight away.');
    return true;
  }
  return false;
}

/// M2-22
class WorkingDaysScreen extends StatefulWidget {
  const WorkingDaysScreen({super.key, required this.availability});
  final Map<String, dynamic> availability;

  @override
  State<WorkingDaysScreen> createState() => _WorkingDaysScreenState();
}

class _WorkingDaysScreenState extends State<WorkingDaysScreen> {
  late final Set<int> _on = {...(widget.availability['workingDays'] as List).cast<int>()};
  bool _busy = false;

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Working days',
        children: [
          const Txt('Students can only book on the days you switch on.', size: TxtSize.sm),
          for (var i = 1; i <= 7; i++) ToggleTile(title: _days[i - 1], value: _on.contains(i), onChanged: (v) => setState(() => v ? _on.add(i) : _on.remove(i))),
        ],
        foot: [
          MbButton('Save', loading: _busy, onPressed: () async {
            setState(() => _busy = true);
            final ok = await _saveAvailability(context, {'workingDays': _on.toList()..sort()});
            if (mounted) setState(() => _busy = false);
            if (ok && context.mounted) Navigator.of(context).pop();
          }),
        ],
      );
}

/// M2-23
class WorkingHoursScreen extends StatefulWidget {
  const WorkingHoursScreen({super.key, required this.availability});
  final Map<String, dynamic> availability;

  @override
  State<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends State<WorkingHoursScreen> {
  late String _start = widget.availability['startTime'] as String;
  late String _end = widget.availability['endTime'] as String;
  late final Map<String, dynamic> _l = {...(widget.availability['lunchBreak'] as Map).cast<String, dynamic>()};
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    if (_start.compareTo(_end) >= 0) {
      setState(() => _error = 'End time must be after start time');
      return;
    }
    if (_l['enabled'] == true && (_l['start'] as String).compareTo(_l['end'] as String) >= 0) {
      setState(() => _error = 'The break must end after it starts');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _saveAvailability(context, {'startTime': _start, 'endTime': _end, 'lunchBreak': _l});
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Working hours',
        bg: PageBg.white,
        children: [
          MbField(label: 'Start', type: FieldType.select, value: Fmt.hhmmAmPm(_start), onTap: () async {
            final v = await _pickTime(context, 'Start time', _start);
            if (v != null) setState(() => _start = v);
          }),
          MbField(label: 'End', type: FieldType.select, value: Fmt.hhmmAmPm(_end), error: _error, onTap: () async {
            final v = await _pickTime(context, 'End time', _end);
            if (v != null) setState(() => _end = v);
          }),
          ToggleTile(title: 'Lunch break', sub: 'No sessions are offered during the break', value: _l['enabled'] == true, onChanged: (v) => setState(() => _l['enabled'] = v)),
          if (_l['enabled'] == true)
            Row(children: [
              Expanded(child: MbField(label: 'Break from', type: FieldType.select, value: Fmt.hhmmAmPm(_l['start'] as String), onTap: () async {
                final v = await _pickTime(context, 'Break starts', _l['start'] as String);
                if (v != null) setState(() => _l['start'] = v);
              })),
              const SizedBox(width: 10),
              Expanded(child: MbField(label: 'Break to', type: FieldType.select, value: Fmt.hhmmAmPm(_l['end'] as String), onTap: () async {
                final v = await _pickTime(context, 'Break ends', _l['end'] as String);
                if (v != null) setState(() => _l['end'] = v);
              })),
            ]),
        ],
        foot: [MbButton('Save', loading: _busy, onPressed: _save)],
      );
}

/// M2-24
class SessionLengthScreen extends StatefulWidget {
  const SessionLengthScreen({super.key, required this.availability});
  final Map<String, dynamic> availability;

  @override
  State<SessionLengthScreen> createState() => _SessionLengthScreenState();
}

class _SessionLengthScreenState extends State<SessionLengthScreen> {
  static const _lens = [30, 45, 60];
  static const _buffers = [0, 5, 10, 15];
  late int _len = _lens.indexOf((widget.availability['sessionLength'] as num).toInt()).clamp(0, 2);
  late int _buf = _buffers.indexOf((widget.availability['bufferMinutes'] as num).toInt()).clamp(0, 3);
  bool _busy = false;

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Session length',
        children: [
          OptionsList(
            items: const [OptionItem('30 minutes', sub: 'University default · recommended'), OptionItem('45 minutes'), OptionItem('60 minutes', sub: 'For first assessments')],
            selected: _len,
            onSelect: (i) => setState(() => _len = i),
          ),
          const SectionHeader('Break between sessions'),
          Segmented(items: const ['None', '5 min', '10 min', '15 min'], index: _buf, onChanged: (i) => setState(() => _buf = i)),
          const BannerCard(tone: Tone.blue, icon: 'info', text: 'Existing bookings keep their time. New slots use the new length.'),
        ],
        foot: [
          MbButton('Save', loading: _busy, onPressed: () async {
            setState(() => _busy = true);
            final ok = await _saveAvailability(context, {'sessionLength': _lens[_len], 'bufferMinutes': _buffers[_buf]});
            if (mounted) setState(() => _busy = false);
            if (ok && context.mounted) Navigator.of(context).pop();
          }),
        ],
      );
}

/// M2-25 — exactly what students will see.
class SlotPreviewScreen extends StatefulWidget {
  const SlotPreviewScreen({super.key});

  @override
  State<SlotPreviewScreen> createState() => _SlotPreviewScreenState();
}

class _SlotPreviewScreenState extends State<SlotPreviewScreen> {
  late String _date = Fmt.todayStr();

  @override
  Widget build(BuildContext context) {
    final d = Fmt.fromDateStr(_date);
    return MbPage(
      title: 'Slot preview',
      subtitle: 'What students will see',
      children: [
        const BannerCard(tone: Tone.blue, icon: 'visibility', text: 'Generated from your days, hours, session length and blocks.'),
        CalendarCard(
          year: d.year,
          month: d.month,
          selected: d.day,
          onSelect: (day) => setState(() => _date = Fmt.dateStr(DateTime.utc(d.year, d.month, day))),
          onPrev: () => setState(() => _date = Fmt.dateStr(DateTime.utc(d.year, d.month - 1, 1))),
          onNext: () => setState(() => _date = Fmt.dateStr(DateTime.utc(d.year, d.month + 1, 1))),
        ),
        SectionHeader(Fmt.longDateStr(_date)),
        FutureBuilder<Map<String, dynamic>>(
          key: ValueKey(_date),
          future: api.get('/staff/availability/preview', query: {'date': _date}),
          builder: (context, snap) {
            if (snap.hasError) return const BannerCard(tone: Tone.red, icon: 'wifi_off', text: 'Couldn’t load the preview.');
            if (!snap.hasData) return const LoadingList(n: 1);
            final slots = (snap.data!['slots'] as List).cast<Map<String, dynamic>>();
            if (slots.isEmpty) return const BannerCard(tone: Tone.grey, icon: 'event_busy', text: 'No slots on this day — it’s outside your working days, blocked, past, or beyond the booking window.');
            return SlotsGrid(labels: [for (final s in slots) Fmt.hhmm(s['time'] as String)], disabled: {for (var i = 0; i < slots.length; i++) if (slots[i]['available'] != true) i}, selected: null, onSelect: (_) {});
          },
        ),
      ],
      foot: [MbButton('Looks good', onPressed: () => Navigator.of(context).pop())],
    );
  }
}

/// M2-26 / M2-55 — block time, with a warning if it overlaps a booking.
class BlockTimeScreen extends StatefulWidget {
  const BlockTimeScreen({super.key});

  @override
  State<BlockTimeScreen> createState() => _BlockTimeScreenState();
}

class _BlockTimeScreenState extends State<BlockTimeScreen> {
  late String _date = Fmt.todayStr();
  String _from = '09:00';
  String _to = '10:00';
  bool _allDay = false;
  bool _repeat = false;
  final _reason = TextEditingController();
  bool _busy = false;
  final _key = GlobalKey<LoaderState<Map<String, dynamic>>>();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit({bool force = false}) async {
    setState(() => _busy = true);
    try {
      await api.post('/staff/availability/blocks', {'date': _date, 'allDay': _allDay, 'from': _from, 'to': _to, 'reason': _reason.text.trim(), 'repeatWeekly': _repeat, 'force': force});
      if (!mounted) return;
      toast(context, 'Time blocked.');
      _reason.clear();
      _key.currentState?.reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'BLOCK_CONFLICT') {
        final c = ((e.details?['conflicts'] as List?) ?? []).cast<Map<String, dynamic>>();
        final r = await showMbSheet(
          context,
          icon: 'warning',
          tone: Tone.amber,
          title: 'This overlaps a booked session',
          text: '${c.isNotEmpty ? '${c.first['student']} is booked at ${Fmt.dateTime(c.first['start'])}. ' : ''}Blocking this time won’t cancel it automatically.',
          rows: [for (final x in c.take(3)) ('Conflict', Fmt.dateTime(x['start']))],
          actions: const [SheetAction('Block anyway', value: 'force'), SheetAction('Change time', kind: BtnKind.ghost)],
        );
        if (r == 'force') return _submit(force: true);
      } else {
        toast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Block time',
        children: [
          MbField(label: 'Date', type: FieldType.select, value: Fmt.longDateStr(_date), onTap: () async {
            final now = Fmt.nowSl();
            final p = await showDatePicker(context: context, initialDate: Fmt.fromDateStr(_date), firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 1, now.month, now.day));
            if (p != null) setState(() => _date = Fmt.dateStr(DateTime.utc(p.year, p.month, p.day)));
          }),
          ToggleTile(title: 'All day', value: _allDay, onChanged: (v) => setState(() => _allDay = v)),
          if (!_allDay)
            Row(children: [
              Expanded(child: MbField(label: 'From', type: FieldType.select, value: Fmt.hhmmAmPm(_from), onTap: () async {
                final v = await _pickTime(context, 'From', _from);
                if (v != null) setState(() => _from = v);
              })),
              const SizedBox(width: 10),
              Expanded(child: MbField(label: 'To', type: FieldType.select, value: Fmt.hhmmAmPm(_to), onTap: () async {
                final v = await _pickTime(context, 'To', _to);
                if (v != null) setState(() => _to = v);
              })),
            ]),
          MbField(label: 'Reason (private)', controller: _reason, hint: 'e.g. Faculty meeting', maxLength: 80),
          ToggleTile(title: 'Repeat weekly', sub: 'Blocks the same time every week from this date', value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
          const SectionHeader('Upcoming blocks'),
          Loader<Map<String, dynamic>>(
            key: _key,
            load: () => api.get('/staff/availability'),
            wrap: (c) => c,
            builder: (context, d, reload) {
              final blocks = ((d['availability'] as Map)['blocks'] as List).cast<Map<String, dynamic>>().where((b) => b['repeatWeekly'] == true || (b['date'] as String).compareTo(Fmt.todayStr()) >= 0).toList()
                ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
              if (blocks.isEmpty) return const BannerCard(tone: Tone.grey, icon: 'event_available', text: 'No blocked time coming up.');
              return ListCards([
                for (final b in blocks)
                  ListItemData(
                    icon: 'block',
                    tone: Tone.grey,
                    title: '${Fmt.shortDateStr(b['date'] as String)} · ${b['allDay'] == true ? 'All day' : '${Fmt.hhmm(b['from'] as String)} – ${Fmt.hhmmAmPm(b['to'] as String)}'}',
                    sub: [if ((b['reason'] as String?)?.isNotEmpty == true) b['reason'], if (b['repeatWeekly'] == true) 'Every week'].join(' · '),
                    trailing: IconButton(
                      tooltip: 'Remove block',
                      icon: const MbIcon('delete', size: 20, color: C.dangerText),
                      onPressed: () async {
                        final r = await guard(context, () => api.delete('/staff/availability/blocks/${b['id']}'));
                        if (r != null) reload();
                      },
                    ),
                  ),
              ]);
            },
          ),
        ],
        foot: [MbButton('Block this time', loading: _busy, onPressed: () => _submit())],
      );
}
