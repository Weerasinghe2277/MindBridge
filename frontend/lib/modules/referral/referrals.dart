// MEMBER 4 — Doctor Referral Management: doctor views, accepts, declines, requests info.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../features/doctor/consultations.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../appointment/booking.dart';

/// M4-02
class ReferralListScreen extends StatefulWidget {
  const ReferralListScreen({super.key});

  @override
  State<ReferralListScreen> createState() => _ReferralListScreenState();
}

class _ReferralListScreenState extends State<ReferralListScreen> {
  int _chip = 0;
  static const _status = ['new', 'accepted', 'declined', ''];

  @override
  Widget build(BuildContext context) {
    final chips = Chips(items: const ['New', 'Accepted', 'Declined', 'All'], selected: {_chip}, onTap: (i) => setState(() => _chip = i));
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_chip),
      load: () => api.get('/referrals', query: {'status': _status[_chip]}),
      wrap: (c) => MbPage(title: 'Referrals', root: true, children: [chips, c]),
      builder: (context, d, reload) {
        final list = (d['referrals'] as List).cast<Map<String, dynamic>>();
        return MbPage(
          title: 'Referrals',
          root: true,
          onRefresh: reload,
          children: [
            chips,
            if (list.isEmpty)
              StateView(icon: 'assignment_ind', tone: Tone.grey, title: _chip == 0 ? 'No new referrals' : 'Nothing here', text: 'Referrals from counsellors will appear here.')
            else
              ListCards([
                for (final r in list)
                  ListItemData(
                    avatar: (r['student'] as Map)['initials'] as String,
                    title: (r['student'] as Map)['name'] as String,
                    sub: 'From ${(r['counsellor'] as Map)['name']}',
                    meta: Fmt.stamp(r['createdAt']),
                    badge: r['status'] == 'new' ? r['urgencyLabel'] as String : r['statusLabel'] as String,
                    badgeTone: Tone.of((r['status'] == 'new' ? r['urgencyTone'] : r['statusTone']) as String?),
                    onTap: () async {
                      await push(context, ReferralDetailScreen(id: r['id'] as String));
                      reload();
                    },
                  ),
              ]),
          ],
        );
      },
    );
  }
}

/// M4-03 — only what the counsellor chose to share. Every view is audited.
class ReferralDetailScreen extends StatefulWidget {
  const ReferralDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ReferralDetailScreen> createState() => _ReferralDetailScreenState();
}

class _ReferralDetailScreenState extends State<ReferralDetailScreen> {
  final _key = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _accept(Map<String, dynamic> r) async {
    final sug = await guard(context, () => api.get('/referrals/${widget.id}/suggest-slot'));
    if (sug == null || !mounted) return;
    final slot = sug['slot'] as Map<String, dynamic>?;
    String? consultationId;
    final res = await showMbSheet(
      context,
      icon: 'assignment_turned_in',
      title: 'Accept this referral?',
      text: '${(r['counsellor'] as Map)['name']} and ${(r['student'] as Map)['name'].toString().split(' ').first} will be notified and a consultation slot will be offered.',
      rows: [('Suggested slot', slot == null ? 'No free slots in 3 weeks' : Fmt.dateTime(slot['start']))],
      actions: [
        if (slot != null)
          SheetAction('Accept with this slot', run: (_) async {
            final x = await api.post('/referrals/${widget.id}/accept', {'start': slot['start'], 'mode': 'in_person'});
            consultationId = x['consultationId'] as String?;
            return true;
          }),
        const SheetAction('Choose another time', kind: BtnKind.secondary, value: 'choose'),
        const SheetAction('Go back', kind: BtnKind.ghost),
      ],
    );
    if (!mounted) return;
    if (consultationId != null) {
      replace(context, ReferralAcceptedScreen(consultationId: consultationId!, studentName: (r['student'] as Map)['name'] as String));
    } else if (res == 'choose') {
      await push(context, AcceptWithSlotScreen(referral: r), root: true, name: 'accept');
      _key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        key: _key,
        load: () async => (await api.get('/referrals/${widget.id}'))['referral'] as Map<String, dynamic>,
        wrap: (c) => MbPage(title: 'Referral', children: [c]),
        builder: (context, r, reload) {
          final s = r['student'] as Map<String, dynamic>;
          final isNew = r['status'] == 'new';
          final reqs = (r['infoRequests'] as List).cast<Map<String, dynamic>>();
          final cons = r['consultation'] as Map<String, dynamic>?;
          return MbPage(
            title: 'Referral',
            onRefresh: reload,
            children: [
              HeroCard(
                style: isNew ? (r['urgency'] == 'routine' ? HeroStyle.soft : HeroStyle.amber) : HeroStyle.white,
                eyebrow: '${r['urgencyLabel']} referral',
                badge: r['statusLabel'] as String,
                badgeTone: Tone.of(r['statusTone'] as String?),
                title: s['name'] as String,
                sub: 'Referred by ${(r['counsellor'] as Map)['name']} · ${Fmt.dateTime(r['createdAt'])}',
              ),
              const SectionHeader('Reason for referral'),
              Txt(r['reason'] as String),
              BannerCard(icon: 'shield', title: 'Authorized information only', text: 'You see what the counsellor chose to share.', link: 'What’s shared', onLink: () => push(context, AuthorizedInfoScreen(referral: r))),
              KvCard([
                ('Student ID', s['studentId'] as String? ?? '—'),
                ('Consent', r['consent'] == true ? 'Recorded by counsellor' : 'Not recorded'),
                ('Contact', (r['contact'] as String?)?.isNotEmpty == true ? r['contact'] as String : 'Not shared'),
              ]),
              if (cons != null) ListCards([ListItemData(icon: 'stethoscope', tone: Tone.blue, title: 'Consultation · ${Fmt.dateTime(cons['start'])}', sub: cons['room'] as String?, onTap: () => push(context, ConsultationDetailScreen(id: cons['id'] as String)))]),
              for (final q in reqs)
                BannerCard(tone: Tone.blue, icon: (q['reply'] as String).isEmpty ? 'hourglass_top' : 'reply', title: (q['reply'] as String).isEmpty ? 'You asked · waiting for reply' : 'Counsellor replied', text: (q['reply'] as String).isEmpty ? q['message'] as String : q['reply'] as String),
              if (r['decline'] != null) BannerCard(tone: Tone.grey, icon: 'info', title: 'Declined: ${(r['decline'] as Map)['reason']}', text: (r['decline'] as Map)['note'] as String?),
              if (isNew) LinksRow([('Request more information', () => push(context, RequestInfoScreen(id: widget.id), root: true))]),
            ],
            footRow: true,
            foot: isNew
                ? [
                    MbButton('Decline', kind: BtnKind.dangerSoft, onPressed: () async {
                      await push(context, DeclineReferralScreen(id: widget.id), root: true);
                      reload();
                    }),
                    MbButton('Accept', onPressed: () => _accept(r)),
                  ]
                : const [],
          );
        },
      );
}

/// M4-04
class AuthorizedInfoScreen extends StatelessWidget {
  const AuthorizedInfoScreen({super.key, required this.referral});
  final Map<String, dynamic> referral;

  @override
  Widget build(BuildContext context) {
    final share = referral['share'] as Map<String, dynamic>;
    return MbPage(
      title: 'Shared information',
      children: [
        ChecksCard(title: 'Shared with you', [
          (true, 'Name and student ID'),
          (share['contact'] == true, 'Contact number'),
          (true, 'Reason for referral'),
          (share['summary'] == true, 'Short session summary'),
        ]),
        const ChecksCard(title: 'Not shared', [(false, 'Full counselling notes'), (false, 'Mood check-ins and journal'), (false, 'AI assistant chats')]),
        if ((referral['summary'] as String?)?.isNotEmpty == true) KvCard([('Summary', referral['summary'] as String)], title: 'Counsellor summary'),
        const Txt('Every view is logged. Student Affairs can audit who opened a record, not what it contains.', size: TxtSize.xs),
      ],
    );
  }
}

class AcceptWithSlotScreen extends StatefulWidget {
  const AcceptWithSlotScreen({super.key, required this.referral});
  final Map<String, dynamic> referral;

  @override
  State<AcceptWithSlotScreen> createState() => _AcceptWithSlotScreenState();
}

class _AcceptWithSlotScreenState extends State<AcceptWithSlotScreen> {
  String? _date;
  Map<String, dynamic>? _slot;
  int _mode = 0;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await api.post('/referrals/${widget.referral['id']}/accept', {'start': _slot!['start'], 'mode': _mode == 0 ? 'in_person' : 'online'});
      if (!mounted) return;
      popFlow(context, 'accept');
      push(context, ReferralAcceptedScreen(consultationId: r['consultationId'] as String, studentName: (widget.referral['student'] as Map)['name'] as String), root: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Offer a consultation',
        subtitle: (widget.referral['student'] as Map)['name'] as String,
        children: [
          AvailabilityCalendar(monthUrl: '/doctor/month', selected: _date, legend: false, onSelect: (v) => setState(() {
                _date = v;
                _slot = null;
              })),
          if (_date != null) DaySlots(url: '/doctor/slots', date: _date!, selected: _slot, onSelect: (s) => setState(() => _slot = s)),
          Segmented(items: const ['In person', 'Online'], index: _mode, onChanged: (i) => setState(() => _mode = i)),
        ],
        foot: [MbButton('Accept referral', loading: _busy, onPressed: _slot == null ? null : _submit)],
      );
}

/// M4-06
class ReferralAcceptedScreen extends StatelessWidget {
  const ReferralAcceptedScreen({super.key, required this.consultationId, required this.studentName});
  final String consultationId;
  final String studentName;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () async => (await api.get('/doctor/consultations/$consultationId'))['consultation'] as Map<String, dynamic>,
        wrap: (c) => MbPage(bg: PageBg.white, children: [c]),
        builder: (context, c, reload) => MbPage(
          bg: PageBg.white,
          children: [
            StateView(icon: 'assignment_turned_in', title: 'Referral accepted', text: '${studentName.split(' ').first} has been offered ${Fmt.dateTime(c['start'])}.'),
            TimelineCard([
              const TimelineStep('Referred', state: 'done'),
              const TimelineStep('Accepted', sub: 'Just now', state: 'done'),
              TimelineStep('Consultation', sub: Fmt.dateTime(c['start']), state: 'now'),
              const TimelineStep('Follow-up'),
            ]),
          ],
          foot: [MbButton('View consultation', onPressed: () => replace(context, ConsultationDetailScreen(id: consultationId)))],
        ),
      );
}

/// M4-07
class DeclineReferralScreen extends StatefulWidget {
  const DeclineReferralScreen({super.key, required this.id});
  final String id;

  @override
  State<DeclineReferralScreen> createState() => _DeclineReferralScreenState();
}

class _DeclineReferralScreenState extends State<DeclineReferralScreen> {
  static const _reasons = ['Needs an external specialist', 'Not a medical concern', 'Duplicate referral', 'Other'];
  int _reason = 0;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Decline referral',
        children: [
          OptionsList(items: [for (final r in _reasons) OptionItem(r)], selected: _reason, onSelect: (i) => setState(() => _reason = i)),
          MbField(label: 'Note to counsellor', controller: _note, type: FieldType.area, rows: 3, hint: 'Suggest next steps for the counsellor', maxLength: 1000),
        ],
        foot: [
          MbButton('Decline referral', kind: BtnKind.danger, loading: _busy, onPressed: () async {
            setState(() => _busy = true);
            final r = await guard(context, () => api.post('/referrals/${widget.id}/decline', {'reason': _reasons[_reason], 'note': _note.text.trim()}));
            if (mounted) setState(() => _busy = false);
            if (r != null && context.mounted) {
              Navigator.of(context).pop();
              toast(context, 'Referral declined. The counsellor has your note.');
            }
          }),
        ],
      );
}

/// M4-08
class RequestInfoScreen extends StatefulWidget {
  const RequestInfoScreen({super.key, required this.id});
  final String id;

  @override
  State<RequestInfoScreen> createState() => _RequestInfoScreenState();
}

class _RequestInfoScreenState extends State<RequestInfoScreen> {
  static const _items = ['Medication history', 'Sleep pattern', 'Symptom duration', 'Previous referrals'];
  final Set<int> _sel = {};
  final _msg = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Ask for more information',
        children: [
          const Txt('Your request goes to the counsellor. The student’s full notes stay protected unless the counsellor chooses to share more.', size: TxtSize.sm),
          Chips(wrap: true, items: _items, selected: _sel, onTap: (i) => setState(() => _sel.contains(i) ? _sel.remove(i) : _sel.add(i))),
          MbField(label: 'Message', controller: _msg, type: FieldType.area, rows: 3, hint: 'e.g. Could you share the typical sleep and wake times?', maxLength: 1000),
        ],
        foot: [
          MbButton('Send request', loading: _busy, onPressed: () async {
            if (_msg.text.trim().isEmpty) {
              toast(context, 'Add a short message.');
              return;
            }
            setState(() => _busy = true);
            final r = await guard(context, () => api.post('/referrals/${widget.id}/request-info', {'items': [for (final i in _sel) _items[i]], 'message': _msg.text.trim()}));
            if (mounted) setState(() => _busy = false);
            if (r != null && context.mounted) {
              Navigator.of(context).pop();
              toast(context, 'Request sent to the counsellor.');
            }
          }),
        ],
      );
}
