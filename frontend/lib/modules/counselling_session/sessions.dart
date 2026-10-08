// MEMBER 3 — Counselling Session Management: start, view, update notes/checklist, complete.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../referral/counsellor_referrals.dart';

/// Starts a session: records the start, opens the secure video room for online sessions.
Future<void> startSession(BuildContext context, Appointment a) async {
  final r = await guard(context, () => api.post('/appointments/${a.id}/session/start'));
  if (r == null || !context.mounted) return;
  final started = Appointment(r['appointment'] as Map<String, dynamic>);
  if (started.online && started.meetingLink != null) {
    launchUrl(Uri.parse(started.meetingLink!), mode: LaunchMode.externalApplication);
  }
  await push(context, LiveSessionScreen(appointment: started), root: true, name: 'session');
}

/// M2-27 — last notes and goals before the session.
class SessionPrepScreen extends StatelessWidget {
  const SessionPrepScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Loader<List<Map<String, dynamic>>>(
        load: () => Future.wait([api.get('/appointments/$id'), api.get('/appointments/$id/notes')]),
        wrap: (c) => MbPage(title: 'Prepare session', children: [c]),
        builder: (context, r, reload) {
          final a = Appointment(r[0]['appointment'] as Map<String, dynamic>);
          final prev = r[1]['previous'] as Map<String, dynamic>?;
          final goals = ((prev?['goals'] as List?) ?? []).cast<Map<String, dynamic>>();
          return MbPage(
            title: 'Prepare session',
            onRefresh: reload,
            children: [
              HeroCard(style: HeroStyle.soft, eyebrow: Fmt.startsIn(a.start), badge: a.modeLabel, badgeTone: Tone.blue, title: a.studentName, sub: '${Fmt.dateTime(a.start)} · ${a.timeRange}'),
              if (a.note.isNotEmpty) ...[const SectionHeader('Note from student'), Txt('“${a.note}”')],
              const SectionHeader('Last session (your notes)'),
              if (prev == null)
                const BannerCard(tone: Tone.grey, icon: 'person_add', text: 'First session with this student. No earlier notes.')
              else ...[
                if ((prev['summary'] as String).isNotEmpty) Txt(prev['summary'] as String),
                if ((prev['plan'] as String).isNotEmpty) KvCard([('Plan', prev['plan'] as String)]),
                if (goals.isNotEmpty) ChecksCard(title: 'Goals', [for (final g in goals) (g['done'] == true, g['text'] as String)]),
              ],
              const BannerCard(icon: 'lock', text: 'Your notes are encrypted and visible only to you.'),
            ],
            foot: a.status == 'confirmed'
                ? [MbButton(a.online ? 'Start online session' : 'Start in-person session', icon: a.online ? 'videocam' : 'meeting_room', onPressed: () => startSession(context, a))]
                : const [],
          );
        },
      );
}

/// M2-28 / M2-29 — the session in progress.
class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  late Appointment a = widget.appointment;
  late final List<Map<String, dynamic>> _checklist = (((a.session?['checklist'] as List?) ?? [])).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Timer? _timer;

  DateTime get _startedAt => Fmt.parse(a.session?['startedAt'] ?? DateTime.now().toIso8601String());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _toggle(int i) async {
    setState(() => _checklist[i]['done'] = !(_checklist[i]['done'] as bool));
    await guard(context, () => api.patch('/appointments/${a.id}/session', {'checklist': _checklist}));
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(_startedAt);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return MbPage(
      title: a.online ? 'Online session' : 'In-person session',
      subtitle: '${a.studentName} · $mm:$ss',
      children: [
        HeroCard(
          style: HeroStyle.soft,
          eyebrow: 'In progress',
          badge: a.modeLabel,
          badgeTone: Tone.blue,
          title: a.studentName,
          sub: a.online ? 'The secure video room opens in your browser.' : a.location,
          actions: [if (a.online && a.meetingLink != null) MbButton('Open video room', icon: 'videocam', height: 46, onPressed: () => launchUrl(Uri.parse(a.meetingLink!), mode: LaunchMode.externalApplication))],
        ),
        StatsGrid([StatItem('$mm:$ss', 'Elapsed'), StatItem(Fmt.time(_startedAt), 'Started')]),
        if (_checklist.isNotEmpty) ...[
          const SectionHeader('Session checklist'),
          for (var i = 0; i < _checklist.length; i++) ToggleTile(title: _checklist[i]['label'] as String, value: _checklist[i]['done'] == true, onChanged: (_) => _toggle(i)),
        ],
        const BannerCard(icon: 'lock', text: 'Notes you write here are encrypted and visible only to you.'),
      ],
      footRow: true,
      foot: [
        MbButton('Session notes', kind: BtnKind.secondary, icon: 'edit_note', onPressed: () => push(context, SessionNotesScreen(appointment: a), root: true)),
        MbButton('End session', kind: BtnKind.danger, icon: 'call_end', onPressed: () => push(context, SessionNotesScreen(appointment: a, completeAfterSave: true), root: true, name: 'session')),
      ],
    );
  }
}

const _noteTags = ['Stress', 'Anxiety', 'Sleep', 'Academic', 'Relationships', 'Low mood', 'Follow-up needed'];

/// M2-30 / M2-56 — confidential notes (NFR2). Kept on the device if saving fails.
class SessionNotesScreen extends StatefulWidget {
  const SessionNotesScreen({super.key, required this.appointment, this.completeAfterSave = false});
  final Appointment appointment;
  final bool completeAfterSave;

  @override
  State<SessionNotesScreen> createState() => _SessionNotesScreenState();
}

class _SessionNotesScreenState extends State<SessionNotesScreen> {
  final _summary = TextEditingController();
  final _plan = TextEditingController();
  final _goal = TextEditingController();
  final Set<int> _tags = {};
  List<Map<String, dynamic>> _goals = [];
  bool _refer = false;
  bool _loading = true;
  bool _busy = false;
  String? _saveError;

  Appointment get a => widget.appointment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/appointments/${a.id}/notes');
      final n = (r['note'] ?? r['previous']) as Map<String, dynamic>?;
      final isOwn = r['note'] != null;
      if (n != null) {
        if (isOwn) {
          _summary.text = n['summary'] as String? ?? '';
          _plan.text = n['plan'] as String? ?? '';
          _tags.addAll([for (final t in (n['tags'] as List? ?? [])) if (_noteTags.contains(t)) _noteTags.indexOf(t as String)]);
          _refer = n['recommendReferral'] == true;
        }
        _goals = ((n['goals'] as List?) ?? []).map((g) => Map<String, dynamic>.from(g as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _summary.dispose();
    _plan.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _saveError = null;
    });
    try {
      await api.put('/appointments/${a.id}/notes', {
        'summary': _summary.text.trim(),
        'plan': _plan.text.trim(),
        'tags': [for (final i in _tags) _noteTags[i]],
        'goals': _goals,
        'recommendReferral': _refer,
      });
      if (!widget.completeAfterSave) {
        if (mounted) {
          Navigator.of(context).pop();
          toast(context, 'Notes saved and encrypted.');
        }
        return;
      }
      final r = await api.post('/appointments/${a.id}/complete', {'noShow': false});
      if (!mounted) return;
      final done = Appointment(r['appointment'] as Map<String, dynamic>);
      popFlow(context, 'session');
      push(context, SessionCompletedScreen(appointment: done, sessions: (r['sessionsTogether'] as num?)?.toInt() ?? 1, refer: _refer), root: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _saveError = e.isNetwork ? 'Connection lost. Your notes are still here on this screen — try again when you’re back online.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Session notes',
        subtitle: '${a.studentName} · ${Fmt.day(a.start)}',
        actions: const [HeaderAction('lock', tooltip: 'Encrypted, visible only to you')],
        children: _loading
            ? const [LoadingList(n: 2)]
            : [
                if (_saveError != null) BannerCard(tone: Tone.red, icon: 'cloud_off', title: 'Notes not saved yet', text: _saveError),
                const BannerCard(icon: 'lock', title: 'Confidential', text: 'Only you can view these notes. Not visible to admins or doctors.'),
                MbField(label: 'Summary', controller: _summary, type: FieldType.area, rows: 4, hint: 'What did you discuss?', maxLength: 5000),
                MbField(label: 'Plan / next steps', controller: _plan, type: FieldType.area, rows: 3, maxLength: 3000),
                Chips(wrap: true, items: _noteTags, selected: _tags, onTap: (i) => setState(() => _tags.contains(i) ? _tags.remove(i) : _tags.add(i))),
                const SectionHeader('Goals'),
                for (var i = 0; i < _goals.length; i++)
                  ToggleTile(title: _goals[i]['text'] as String, sub: _goals[i]['done'] == true ? 'Done' : 'In progress', value: _goals[i]['done'] == true, onChanged: (v) => setState(() => _goals[i]['done'] = v)),
                Row(children: [
                  Expanded(child: MbField(controller: _goal, hint: 'Add a goal', maxLength: 200)),
                  const SizedBox(width: 8),
                  MbButton('Add', kind: BtnKind.soft, onPressed: () {
                    if (_goal.text.trim().isEmpty) return;
                    setState(() {
                      _goals.add({'text': _goal.text.trim(), 'done': false});
                      _goal.clear();
                    });
                  }),
                ]),
                if (!widget.appointment.anonymous) ToggleTile(title: 'Recommend referral to Medical Centre', value: _refer, onChanged: (v) => setState(() => _refer = v)),
              ],
        foot: [MbButton(widget.completeAfterSave ? 'Save notes and end session' : (_saveError != null ? 'Retry save' : 'Save notes'), loading: _busy, onPressed: _loading ? null : _save)],
      );
}

/// M2-31
class SessionCompletedScreen extends StatelessWidget {
  const SessionCompletedScreen({super.key, required this.appointment, required this.sessions, this.refer = false});
  final Appointment appointment;
  final int sessions;
  final bool refer;

  @override
  Widget build(BuildContext context) {
    final s = appointment.session;
    final mins = s?['startedAt'] != null && s?['endedAt'] != null ? Fmt.parse(s!['endedAt']).difference(Fmt.parse(s['startedAt'])).inMinutes : 30;
    return MbPage(
      bg: PageBg.white,
      children: [
        StateView(icon: 'task_alt', title: 'Session completed', text: 'Notes saved and encrypted. ${appointment.anonymous ? 'The student' : appointment.studentName.split(' ').first} can book a follow-up whenever they’re ready.'),
        KvCard([('Duration', '${mins.clamp(1, 600)} min'), ('Notes', 'Saved'), if (!appointment.anonymous) ('Sessions together', '$sessions')]),
      ],
      foot: [
        if (!appointment.anonymous) MbButton('Refer to doctor', kind: refer ? BtnKind.primary : BtnKind.secondary, icon: 'local_hospital', onPressed: () => replace(context, ReferDoctorScreen(appointment: appointment), root: true, name: 'refer')),
        MbButton('Back to dashboard', kind: refer ? BtnKind.secondary : BtnKind.primary, onPressed: () => popToFirst(context, root: true)),
      ],
    );
  }
}

/// M2-32 — limited student view (NFR1).
class StudentInfoScreen extends StatelessWidget {
  const StudentInfoScreen({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/appointments/$appointmentId/student'),
        wrap: (c) => MbPage(title: 'Student', children: [c]),
        builder: (context, d, reload) {
          final s = d['student'] as Map<String, dynamic>;
          if (d['anonymous'] == true) {
            return MbPage(title: 'Student', children: [
              ProfileHeader(initials: s['initials'] as String, name: s['name'] as String, sub: studentDetailsLine(s)),
              const AnonymousBookingBanner(),
              const ChecksCard(title: 'Hidden for this booking', [(false, 'Name, student ID and faculty'), (false, 'Phone and email'), (false, 'Past sessions with you'), (false, 'Mood trends and journal')]),
            ]);
          }
          final sessions = d['sessions'] as Map<String, dynamic>;
          final trend = (d['moodTrend'] as List?)?.cast<Map<String, dynamic>>();
          return MbPage(
            title: 'Student',
            children: [
              ProfileHeader(initials: s['initials'] as String, name: s['name'] as String, sub: studentDetailsLine(s)),
              const BannerCard(icon: 'shield', title: 'Limited view', text: 'You see booking information only. Mood check-ins stay private unless the student shares them.'),
              KvCard([
                ('Sessions with you', '${sessions['completed']} completed · ${sessions['upcoming']} upcoming'),
                ('Prefers', d['prefers'] == null ? '—' : modeLabel(d['prefers'] as String)),
                ('Language', s['language'] as String? ?? 'English'),
              ]),
              if (trend != null)
                BarsChart(title: 'Mood trend (shared by student)', sub: 'Weekly average · 1 = Awful, 5 = Great', max: 5, highlight: 3, items: [for (final w in trend) BarDatum(w['label'] as String, w['avg'] == null ? null : (w['avg'] as num).toDouble() + 1)])
              else
                const ChecksCard(title: 'Shared by student', [(false, 'Mood trends (not shared)'), (false, 'Journal (never shared)')]),
            ],
          );
        },
      );
}

/// Shown to counsellors on anonymous bookings.
class AnonymousBookingBanner extends StatelessWidget {
  const AnonymousBookingBanner({super.key});

  @override
  Widget build(BuildContext context) => const BannerCard(
        tone: Tone.lilac,
        icon: 'visibility_off',
        title: 'Anonymous booking',
        text: 'The student chose not to share their details for this online session. Please don’t ask for their name or ID. Referrals aren’t available for anonymous sessions.',
      );
}
