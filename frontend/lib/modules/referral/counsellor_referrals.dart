// MEMBER 4 — Doctor Referral Management: counsellor creates and tracks referrals.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// M2-33 → M2-35 — share only what the doctor needs, with consent.
class ReferDoctorScreen extends StatefulWidget {
  const ReferDoctorScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<ReferDoctorScreen> createState() => _ReferDoctorScreenState();
}

class _ReferDoctorScreenState extends State<ReferDoctorScreen> {
  int _doctor = 0;
  int _urgency = 0;
  bool _shareSummary = true;
  bool _shareContact = true;
  bool _consent = false;
  final _reason = TextEditingController();
  final _summary = TextEditingController();
  final Map<String, String> _err = {};

  @override
  void dispose() {
    _reason.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/staff/doctors'),
        wrap: (c) => MbPage(title: 'Refer to Medical Centre', children: [c]),
        builder: (context, d, reload) {
          final docs = (d['doctors'] as List).cast<Map<String, dynamic>>();
          if (docs.isEmpty) {
            return const MbPage(title: 'Refer to Medical Centre', children: [StateView(icon: 'local_hospital', tone: Tone.grey, title: 'No doctors available', text: 'No verified Medical Centre doctors are on MindBridge yet. Contact Student Affairs.')]);
          }
          return MbPage(
            title: 'Refer to Medical Centre',
            subtitle: widget.appointment.studentName,
            children: [
              if (docs.length == 1)
                ListCards([ListItemData(avatar: docs[0]['initials'] as String, title: docs[0]['name'] as String, sub: '${docs[0]['title']} · ${docs[0]['office']}', badge: 'Available')])
              else
                OptionsList(items: [for (final x in docs) OptionItem(x['name'] as String, sub: '${x['title']} · ${x['openReferrals']} open referrals', icon: 'stethoscope')], selected: _doctor, onSelect: (i) => setState(() => _doctor = i)),
              const SectionHeader('Urgency'),
              Segmented(items: const ['Routine', 'Priority', 'Urgent'], index: _urgency, onChanged: (i) => setState(() => _urgency = i)),
              const SectionHeader('Share with doctor'),
              const ToggleTile(title: 'Reason for referral', sub: 'Required', value: true, locked: true),
              ToggleTile(title: 'Short session summary', value: _shareSummary, onChanged: (v) => setState(() => _shareSummary = v)),
              ToggleTile(title: 'Student contact number', value: _shareContact, onChanged: (v) => setState(() => _shareContact = v)),
              const ToggleTile(title: 'Full session notes', sub: 'Never shared', value: false, locked: true),
              MbField(label: 'Reason for referral', controller: _reason, type: FieldType.area, rows: 3, hint: 'What should the doctor assess?', error: _err['reason'], maxLength: 2000),
              if (_shareSummary) MbField(label: 'Short summary for the doctor', controller: _summary, type: FieldType.area, rows: 2, hint: 'e.g. Two sessions. Sleep 4–5 h a night. No medication.', maxLength: 2000),
              ToggleTile(title: 'Student has consented to this referral', value: _consent, onChanged: (v) => setState(() => _consent = v)),
              if (_err['consent'] != null) Text(_err['consent']!, style: Ty.nunito(size: 12.5, weight: FontWeight.w600, color: C.dangerText)),
            ],
            foot: [
              MbButton('Review referral', onPressed: () {
                _err.clear();
                if (_reason.text.trim().length < 10) _err['reason'] = 'Describe the reason for referral';
                if (!_consent) _err['consent'] = 'Record the student’s consent before referring';
                setState(() {});
                if (_err.isNotEmpty) return;
                push(
                  context,
                  _ReferralReview(
                    appointment: widget.appointment,
                    doctor: docs[docs.length == 1 ? 0 : _doctor],
                    urgency: ['routine', 'priority', 'urgent'][_urgency],
                    reason: _reason.text.trim(),
                    summary: _summary.text.trim(),
                    shareSummary: _shareSummary,
                    shareContact: _shareContact,
                  ),
                  root: true,
                  name: 'refer',
                );
              }),
            ],
          );
        },
      );
}

class _ReferralReview extends StatefulWidget {
  const _ReferralReview({required this.appointment, required this.doctor, required this.urgency, required this.reason, required this.summary, required this.shareSummary, required this.shareContact});
  final Appointment appointment;
  final Map<String, dynamic> doctor;
  final String urgency, reason, summary;
  final bool shareSummary, shareContact;

  @override
  State<_ReferralReview> createState() => _ReferralReviewState();
}

class _ReferralReviewState extends State<_ReferralReview> {
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await api.post('/referrals', {
        'appointmentId': widget.appointment.id,
        'doctorId': widget.doctor['id'],
        'urgency': widget.urgency,
        'reason': widget.reason,
        'summary': widget.summary,
        'share': {'summary': widget.shareSummary, 'contact': widget.shareContact},
        'consent': true,
      });
      if (!mounted) return;
      popFlow(context, 'refer');
      push(
        context,
        MbPage(
          bg: PageBg.white,
          children: [
            StateView(icon: 'send', title: 'Referral sent', text: '${widget.doctor['name']} sees only what you selected. You’ll be notified when it’s accepted.'),
            const TimelineCard([TimelineStep('Referral sent', sub: 'Just now', state: 'done'), TimelineStep('Doctor review', sub: 'Usually same day', state: 'now'), TimelineStep('Consultation')]),
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
  Widget build(BuildContext context) => MbPage(
        title: 'Review referral',
        children: [
          KvCard([('To', widget.doctor['name'] as String), ('Student', widget.appointment.studentName), ('Urgency', '${widget.urgency[0].toUpperCase()}${widget.urgency.substring(1)}'), ('Consent', 'Recorded')]),
          ChecksCard(title: 'Doctor will see', [
            (true, 'Reason for referral'),
            (widget.shareSummary, 'Short session summary'),
            (widget.shareContact, 'Contact number'),
            (false, 'Full session notes'),
            (false, 'Mood check-ins'),
          ]),
        ],
        foot: [MbButton('Send referral', loading: _busy, onPressed: _send)],
      );
}

/// Counsellor's referrals, including replies to a doctor's questions.
class CounsellorReferralsScreen extends StatelessWidget {
  const CounsellorReferralsScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/referrals'),
        wrap: (c) => MbPage(title: 'My referrals', children: [c]),
        builder: (context, d, reload) {
          final list = (d['referrals'] as List).cast<Map<String, dynamic>>();
          return MbPage(
            title: 'My referrals',
            onRefresh: reload,
            children: list.isEmpty
                ? [const StateView(icon: 'local_hospital', tone: Tone.grey, title: 'No referrals yet', text: 'Refer a student to the Medical Centre from a completed session.')]
                : [
                    ListCards([
                      for (final r in list)
                        ListItemData(
                          avatar: (r['student'] as Map)['initials'] as String,
                          title: (r['student'] as Map)['name'] as String,
                          sub: 'To ${(r['doctor'] as Map)['name']} · ${r['urgencyLabel']}',
                          meta: (r['infoRequests'] as List).any((x) => (x['reply'] as String).isEmpty) ? 'Doctor asked for more information' : Fmt.stamp(r['createdAt']),
                          badge: r['statusLabel'] as String,
                          badgeTone: Tone.of(r['statusTone'] as String?),
                          onTap: () async {
                            await push(context, CounsellorReferralScreen(id: r['id'] as String));
                            reload();
                          },
                        ),
                    ]),
                  ],
          );
        },
      );
}

class CounsellorReferralScreen extends StatefulWidget {
  const CounsellorReferralScreen({super.key, required this.id});
  final String id;

  @override
  State<CounsellorReferralScreen> createState() => _CounsellorReferralScreenState();
}

class _CounsellorReferralScreenState extends State<CounsellorReferralScreen> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/referrals/${widget.id}'),
        wrap: (c) => MbPage(title: 'Referral', children: [c]),
        builder: (context, d, reload) {
          final r = d['referral'] as Map<String, dynamic>;
          final student = r['student'] as Map<String, dynamic>;
          final reqs = (r['infoRequests'] as List).cast<Map<String, dynamic>>();
          final open = reqs.where((x) => (x['reply'] as String).isEmpty).toList();
          final cons = r['consultation'] as Map<String, dynamic>?;
          return MbPage(
            title: 'Referral',
            subtitle: 'To ${(r['doctor'] as Map)['name']}',
            onRefresh: reload,
            children: [
              HeroCard(style: r['status'] == 'new' ? HeroStyle.amber : (r['status'] == 'accepted' ? HeroStyle.soft : HeroStyle.white), eyebrow: '${r['urgencyLabel']} referral', badge: r['statusLabel'] as String, badgeTone: Tone.of(r['statusTone'] as String?), title: student['name'] as String, sub: 'Sent ${Fmt.dateTime(r['createdAt'])}'),
              if (cons != null) KvCard([('Consultation', Fmt.dateTime(cons['start'])), ('Where', cons['room'] as String? ?? '')]),
              if (r['decline'] != null) BannerCard(tone: Tone.grey, icon: 'info', title: 'Declined: ${(r['decline'] as Map)['reason']}', text: (r['decline'] as Map)['note'] as String?),
              const SectionHeader('Reason for referral'),
              Txt(r['reason'] as String),
              for (final q in reqs) ...[
                SectionHeader((q['reply'] as String).isEmpty ? 'Doctor asked' : 'Doctor asked · answered'),
                BannerCard(tone: Tone.blue, icon: 'help', title: (q['items'] as List).isEmpty ? null : (q['items'] as List).join(', '), text: q['message'] as String),
                if ((q['reply'] as String).isNotEmpty) Txt('Your reply: ${q['reply']}', size: TxtSize.sm),
              ],
              if (open.isNotEmpty) MbField(label: 'Reply to the doctor', controller: _reply, type: FieldType.area, rows: 3, hint: 'Only share what the doctor needs. Full notes stay private.', maxLength: 2000),
            ],
            foot: open.isEmpty
                ? const []
                : [
                    MbButton('Send reply', loading: _busy, onPressed: () async {
                      if (_reply.text.trim().isEmpty) return;
                      setState(() => _busy = true);
                      final res = await guard(context, () => api.post('/referrals/${widget.id}/reply-info', {'index': open.first['index'], 'reply': _reply.text.trim()}));
                      if (mounted) setState(() => _busy = false);
                      if (res != null) {
                        _reply.clear();
                        reload();
                      }
                    }),
                  ],
          );
        },
      );
}
