import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../modules/appointment/booking.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'doctor_shell.dart';

/// M4-09
class ConsultationListScreen extends StatefulWidget {
  const ConsultationListScreen({super.key});

  @override
  State<ConsultationListScreen> createState() => _ConsultationListScreenState();
}

class _ConsultationListScreenState extends State<ConsultationListScreen> {
  int _seg = 0;
  static const _scopes = ['today', 'upcoming', 'completed'];

  @override
  Widget build(BuildContext context) {
    final seg = Segmented(items: const ['Today', 'Upcoming', 'Completed'], index: _seg, onChanged: (i) => setState(() => _seg = i));
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_seg),
      load: () => api.get('/doctor/consultations', query: {'scope': _scopes[_seg]}),
      wrap: (c) => MbPage(title: 'Consultations', root: true, children: [seg, c]),
      builder: (context, d, reload) {
        final list = (d['consultations'] as List).cast<Map<String, dynamic>>();
        return MbPage(
          title: 'Consultations',
          root: true,
          onRefresh: reload,
          children: [
            seg,
            if (list.isEmpty)
              StateView(icon: 'stethoscope', tone: Tone.grey, title: ['Nothing today', 'No upcoming consultations', 'No completed consultations'][_seg], text: 'Consultations are created when you accept a referral or schedule a follow-up.')
            else
              ListCards([
                for (final c in list)
                  consultationItem(c, showDay: _seg != 0, onTap: () async {
                    await push(context, ConsultationDetailScreen(id: c['id'] as String));
                    reload();
                  }),
              ]),
          ],
        );
      },
    );
  }
}

/// M4-10
class ConsultationDetailScreen extends StatelessWidget {
  const ConsultationDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () async => (await api.get('/doctor/consultations/$id'))['consultation'] as Map<String, dynamic>,
        wrap: (c) => MbPage(title: 'Consultation', children: [c]),
        builder: (context, c, reload) {
          final s = c['student'] as Map<String, dynamic>;
          final ref = c['referral'] as Map<String, dynamic>?;
          final status = c['status'] as String;
          final active = status == 'scheduled' || status == 'in_progress';
          return MbPage(
            title: 'Consultation',
            onRefresh: reload,
            children: [
              HeroCard(
                style: active ? HeroStyle.dark : HeroStyle.soft,
                eyebrow: '${Fmt.relDay(c['start']) ?? Fmt.day(c['start'])} · ${Fmt.time(c['start'])}',
                badge: active ? modeLabelOf(c['mode'] as String) : c['statusLabel'] as String,
                badgeTone: active ? Tone.blue : Tone.of(c['statusTone'] as String?),
                title: s['name'] as String,
                sub: c['isFollowUp'] == true ? 'Follow-up consultation' : (ref != null ? 'Referred: ${ref['reason']}' : null),
                rows: [
                  (c['mode'] == 'online' ? 'videocam' : 'location_on', c['room'] as String? ?? ''),
                  if (ref?['counsellor'] != null) ('person', 'Referred by ${ref!['counsellor']}'),
                ],
                actions: [
                  if (active)
                    MbButton(status == 'in_progress' ? 'Continue consultation' : 'Start consultation', kind: BtnKind.light, height: 46, onPressed: () async {
                      final r = await guard(context, () => api.post('/doctor/consultations/$id/start'));
                      if (r != null && context.mounted) {
                        await push(context, DoctorConsultationScreen(id: id), root: true, name: 'consult');
                        reload();
                      }
                    }),
                ],
              ),
              KvCard([('Student ID', s['studentId'] as String? ?? '—'), if (s['year'] != null) ('Year', '${s['year']}'), ('Consent', 'Recorded')]),
              if (ref?['summary'] != null && (ref!['summary'] as String).isNotEmpty) ...[const SectionHeader('Referral summary'), Txt(ref['summary'] as String)],
              if (status == 'completed') ...[
                if ((c['plan'] as String).isNotEmpty) KvCard([('Plan', c['plan'] as String)], title: 'Outcome'),
                if ((c['tags'] as List).isNotEmpty) Tags((c['tags'] as List).cast<String>()),
              ],
            ],
            foot: status == 'completed'
                ? [
                    MbButton('Schedule follow-up', onPressed: () => push(context, FollowUpScreen(consultationId: id, studentName: s['name'] as String), root: true, name: 'followup')),
                    MbButton('Doctor notes', kind: BtnKind.secondary, onPressed: () => push(context, DoctorNotesScreen(id: id), root: true)),
                  ]
                : const [],
          );
        },
      );
}

const _assessTags = ['Insomnia', 'Stress-related', 'Headache', 'Fatigue', 'Lifestyle advice', 'Bloods ordered', 'Follow-up'];

/// M4-11 — the consultation in progress.
class DoctorConsultationScreen extends StatefulWidget {
  const DoctorConsultationScreen({super.key, required this.id});
  final String id;

  @override
  State<DoctorConsultationScreen> createState() => _DoctorConsultationScreenState();
}

class _DoctorConsultationScreenState extends State<DoctorConsultationScreen> {
  final _bp = TextEditingController();
  final _sleep = TextEditingController();
  final _assessment = TextEditingController();
  final Set<int> _tags = {};
  Map<String, dynamic>? _c;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    api.get('/doctor/consultations/${widget.id}').then((r) {
      final c = r['consultation'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _c = c;
        _bp.text = (c['vitals']?['bloodPressure'] ?? '') as String;
        _sleep.text = (c['vitals']?['avgSleep'] ?? '') as String;
        _assessment.text = c['assessment'] as String? ?? '';
        _tags.addAll([for (final t in (c['tags'] as List)) if (_assessTags.contains(t)) _assessTags.indexOf(t as String)]);
      });
    }).catchError((e) {
      if (mounted) toast(context, e is ApiException ? e.message : 'Couldn’t load the consultation.');
    });
  }

  @override
  void dispose() {
    _bp.dispose();
    _sleep.dispose();
    _assessment.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    final r = await guard(context, () => api.put('/doctor/consultations/${widget.id}', {
          'vitals': {'bloodPressure': _bp.text.trim(), 'avgSleep': _sleep.text.trim()},
          'assessment': _assessment.text.trim(),
          'tags': [for (final i in _tags) _assessTags[i]],
        }));
    return r != null;
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    if (!await _save()) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    final r = await guard(context, () => api.post('/doctor/consultations/${widget.id}/complete'));
    if (mounted) setState(() => _busy = false);
    if (r == null || !mounted) return;
    final c = r['consultation'] as Map<String, dynamic>;
    popFlow(context, 'consult');
    push(
      context,
      MbPage(
        bg: PageBg.white,
        children: [
          StateView(icon: 'task_alt', title: 'Consultation complete', text: c['shareSummary'] == true ? 'Notes saved. The counsellor has the shared plan — clinical notes stay private.' : 'Notes saved. Nothing was shared with the counsellor.'),
          KvCard([('Duration', '${r['durationMin']} min'), ('Next step', (c['plan'] as String).isEmpty ? '—' : c['plan'] as String)]),
        ],
        foot: [
          Builder(builder: (ctx) => MbButton('Schedule follow-up', onPressed: () => replace(ctx, FollowUpScreen(consultationId: widget.id, studentName: (c['student'] as Map)['name'] as String), root: true, name: 'followup'))),
          Builder(builder: (ctx) => MbButton('Back to dashboard', kind: BtnKind.secondary, onPressed: () => popToFirst(ctx, root: true))),
        ],
      ),
      root: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final started = c?['startedAt'] != null ? Fmt.parse(c!['startedAt']) : null;
    return MbPage(
      title: 'Consultation',
      subtitle: c == null ? null : '${(c['student'] as Map)['name']}${started != null ? ' · started ${Fmt.time(started)}' : ''}',
      children: c == null
          ? const [LoadingList(n: 3)]
          : [
              Row(children: [
                Expanded(child: MbField(label: 'Blood pressure', controller: _bp, hint: '118/76', maxLength: 20)),
                const SizedBox(width: 10),
                Expanded(child: MbField(label: 'Avg. sleep', controller: _sleep, hint: '4.5 h', maxLength: 20)),
              ]),
              MbField(label: 'Assessment', controller: _assessment, type: FieldType.area, rows: 4, hint: 'Observations and assessment', maxLength: 5000),
              Chips(wrap: true, items: _assessTags, selected: _tags, onTap: (i) => setState(() => _tags.contains(i) ? _tags.remove(i) : _tags.add(i))),
              const BannerCard(icon: 'lock', text: 'Medical notes are encrypted and visible only to Medical Centre staff.'),
            ],
      footRow: true,
      foot: [
        MbButton('Doctor notes', kind: BtnKind.secondary, onPressed: c == null
            ? null
            : () async {
                if (await _save() && context.mounted) push(context, DoctorNotesScreen(id: widget.id), root: true);
              }),
        MbButton('Complete', loading: _busy, onPressed: c == null ? null : _complete),
      ],
    );
  }
}

/// M4-12 — clinical notes stay private; only the plan can be shared back.
class DoctorNotesScreen extends StatefulWidget {
  const DoctorNotesScreen({super.key, required this.id});
  final String id;

  @override
  State<DoctorNotesScreen> createState() => _DoctorNotesScreenState();
}

class _DoctorNotesScreenState extends State<DoctorNotesScreen> {
  final _notes = TextEditingController();
  final _plan = TextEditingController();
  bool _share = true;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    api.get('/doctor/consultations/${widget.id}').then((r) {
      final c = r['consultation'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _notes.text = c['clinicalNotes'] as String? ?? '';
        _plan.text = c['plan'] as String? ?? '';
        _share = c['shareSummary'] != false;
        _loaded = true;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    _plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Doctor notes',
        actions: const [HeaderAction('lock', tooltip: 'Encrypted')],
        children: !_loaded
            ? const [LoadingList(n: 2)]
            : [
                const BannerCard(icon: 'lock', title: 'Medical notes', text: 'Visible only to Medical Centre staff.'),
                MbField(label: 'Clinical notes', controller: _notes, type: FieldType.area, rows: 4, maxLength: 5000),
                MbField(label: 'Plan', controller: _plan, type: FieldType.area, rows: 3, hint: 'e.g. Sleep diary for 2 weeks. Review on 20 Oct.', maxLength: 2000),
                ToggleTile(title: 'Share short summary with counsellor', sub: 'Plan only. Clinical notes stay private', value: _share, onChanged: (v) => setState(() => _share = v)),
              ],
        foot: [
          MbButton('Save notes', loading: _busy, onPressed: !_loaded
              ? null
              : () async {
                  setState(() => _busy = true);
                  final r = await guard(context, () => api.put('/doctor/consultations/${widget.id}', {'clinicalNotes': _notes.text.trim(), 'plan': _plan.text.trim(), 'shareSummary': _share}));
                  if (mounted) setState(() => _busy = false);
                  if (r != null && context.mounted) {
                    Navigator.of(context).pop();
                    toast(context, 'Notes saved and encrypted.');
                  }
                }),
        ],
      );
}

/// M4-14
class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({super.key, required this.consultationId, required this.studentName});
  final String consultationId;
  final String studentName;

  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen> {
  String? _date;
  Map<String, dynamic>? _slot;
  int _mode = 0;
  bool _notify = true;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await api.post('/doctor/consultations/${widget.consultationId}/follow-up', {'start': _slot!['start'], 'mode': _mode == 0 ? 'in_person' : 'online', 'notifyCounsellor': _notify});
      if (!mounted) return;
      popFlow(context, 'followup');
      toast(context, 'Follow-up booked for ${Fmt.dateTime(_slot!['start'])}. ${widget.studentName.split(' ').first} has been notified.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Schedule follow-up',
        subtitle: widget.studentName,
        children: [
          AvailabilityCalendar(monthUrl: '/doctor/month', selected: _date, legend: false, onSelect: (v) => setState(() {
                _date = v;
                _slot = null;
              })),
          if (_date != null) DaySlots(url: '/doctor/slots', date: _date!, selected: _slot, onSelect: (s) => setState(() => _slot = s)),
          Segmented(items: const ['In person', 'Online'], index: _mode, onChanged: (i) => setState(() => _mode = i)),
          ToggleTile(title: 'Notify counsellor', value: _notify, onChanged: (v) => setState(() => _notify = v)),
        ],
        foot: [MbButton('Schedule follow-up', loading: _busy, onPressed: _slot == null ? null : _submit)],
      );
}
