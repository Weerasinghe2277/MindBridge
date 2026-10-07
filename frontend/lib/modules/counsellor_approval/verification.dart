// MEMBER 2 — Counsellor Approval: view pending counsellors, approve, reject, request changes.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// Opens an admin-only file through a one-time, two-minute link (no session token in the URL).
Future<void> openDownload(BuildContext context, Map<String, dynamic> body) async {
  final r = await guard(context, () => api.post('/download', body));
  if (r == null) return;
  final ok = await launchUrl(Uri.parse('${AppConfig.apiOrigin}${r['path']}'), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'Couldn’t open the file. Please try again.');
}

ListItemData applicationItem(BuildContext context, Map<String, dynamic> a, VoidCallback after) => ListItemData(
      avatar: a['initials'] as String,
      title: a['name'] as String,
      sub: '${a['title'] ?? a['roleLabel']} · applied ${a['submittedAt'] == null ? '' : Fmt.stamp(a['submittedAt'])}',
      badge: a['badge'] as String,
      badgeTone: Tone.of(a['badgeTone'] as String?),
      onTap: () async {
        await push(context, ApplicationScreen(id: a['id'] as String));
        after();
      },
    );

/// M3-12 / M3-57 (FR11)
class VerificationCenterScreen extends StatelessWidget {
  const VerificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<List<Map<String, dynamic>>>(
        load: () => Future.wait([api.get('/admin/verifications', query: {'role': 'counsellor', 'status': 'pending'}), api.get('/admin/verifications', query: {'role': 'doctor', 'status': 'pending'})]),
        wrap: (c) => MbPage(title: 'Verification', root: true, children: [c]),
        builder: (context, r, reload) {
          final cs = (r[0]['applications'] as List).cast<Map<String, dynamic>>();
          final ds = (r[1]['applications'] as List).cast<Map<String, dynamic>>();
          return MbPage(
            title: 'Verification',
            root: true,
            onRefresh: reload,
            children: [
              StatsGrid([
                StatItem('${cs.length}', 'Counsellors waiting', tone: cs.isEmpty ? null : Tone.amber, onTap: () => push(context, const ApplicationListScreen(role: 'counsellor')).then((_) => reload())),
                StatItem('${ds.length}', 'Doctors waiting', tone: ds.isEmpty ? null : Tone.amber, onTap: () => push(context, const ApplicationListScreen(role: 'doctor')).then((_) => reload())),
              ]),
              if (cs.isEmpty && ds.isEmpty) const StateView(icon: 'verified', title: 'All caught up', text: 'No counsellor or doctor applications are waiting.'),
              if (cs.isNotEmpty) ...[
                SectionHeader('Counsellors', link: 'See all', onLink: () => push(context, const ApplicationListScreen(role: 'counsellor')).then((_) => reload())),
                ListCards([for (final a in cs.take(3)) applicationItem(context, a, reload)]),
              ],
              if (ds.isNotEmpty) ...[
                SectionHeader('Doctors', link: 'See all', onLink: () => push(context, const ApplicationListScreen(role: 'doctor')).then((_) => reload())),
                ListCards([for (final a in ds.take(3)) applicationItem(context, a, reload)]),
              ],
            ],
          );
        },
      );
}

/// M3-13 / M3-20
class ApplicationListScreen extends StatefulWidget {
  const ApplicationListScreen({super.key, required this.role});
  final String role;

  @override
  State<ApplicationListScreen> createState() => _ApplicationListScreenState();
}

class _ApplicationListScreenState extends State<ApplicationListScreen> {
  int _chip = 0;
  static const _status = ['pending', 'changes_requested', 'approved', 'rejected'];

  @override
  Widget build(BuildContext context) {
    final chips = Chips(items: const ['Pending', 'Changes asked', 'Approved', 'Rejected'], selected: {_chip}, onTap: (i) => setState(() => _chip = i));
    final title = widget.role == 'doctor' ? 'Doctor applications' : 'Counsellor applications';
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_chip),
      load: () => api.get('/admin/verifications', query: {'role': widget.role, 'status': _status[_chip]}),
      wrap: (c) => MbPage(title: title, children: [chips, c]),
      builder: (context, d, reload) {
        final list = (d['applications'] as List).cast<Map<String, dynamic>>();
        return MbPage(
          title: title,
          onRefresh: reload,
          children: [
            chips,
            if (list.isEmpty) const StateView(icon: 'inbox', tone: Tone.grey, title: 'Nothing here', text: 'Applications in this state will appear here.') else ListCards([for (final a in list) applicationItem(context, a, reload)]),
          ],
        );
      },
    );
  }
}

/// M3-14 / M3-21 — credentials, documents and a checklist before deciding.
class ApplicationScreen extends StatefulWidget {
  const ApplicationScreen({super.key, required this.id});
  final String id;

  @override
  State<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends State<ApplicationScreen> {
  final _key = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _approve(Map<String, dynamic> a) async {
    final isDoc = a['role'] == 'doctor';
    final r = await showMbSheet(
      context,
      icon: 'verified',
      title: 'Approve ${a['name']}?',
      text: isDoc ? 'They’ll be able to receive referrals from counsellors.' : 'They’ll become visible to students and can set availability straight away.',
      actions: [
        SheetAction(isDoc ? 'Approve doctor' : 'Approve counsellor', run: (_) async {
          await api.post('/admin/verifications/${a['id']}/approve');
          return true;
        }),
        const SheetAction('Cancel', kind: BtnKind.ghost),
      ],
    );
    if (r != null && r != 'Cancel' && mounted) {
      replace(
        context,
        MbPage(
          bg: PageBg.white,
          children: [StateView(icon: 'verified', title: isDoc ? 'Doctor approved' : 'Counsellor approved', text: '${a['name']} has been notified and can now ${isDoc ? 'receive counsellor referrals' : 'accept bookings'}.')],
          foot: [Builder(builder: (c) => MbButton('Back to verification', onPressed: () => Navigator.of(c).pop()))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        key: _key,
        load: () async => (await api.get('/admin/verifications/${widget.id}'))['application'] as Map<String, dynamic>,
        wrap: (c) => MbPage(title: 'Application', children: [c]),
        builder: (context, a, reload) {
          final p = (a['professional'] as Map?)?.cast<String, dynamic>() ?? {};
          final v = (a['verification'] as Map).cast<String, dynamic>();
          final docs = ((v['documents'] as List?) ?? []).cast<Map<String, dynamic>>();
          final status = v['status'] as String;
          final open = status == 'pending' || status == 'changes_requested';
          final isDoc = a['role'] == 'doctor';
          return MbPage(
            title: isDoc ? 'Doctor application' : 'Application',
            onRefresh: reload,
            children: [
              ProfileHeader(initials: a['initials'] as String, name: a['name'] as String, sub: '${p['title'] ?? a['roleLabel']} · applied ${v['submittedAt'] == null ? '' : Fmt.dayYear(v['submittedAt'])}'),
              if (!open) BannerCard(tone: Tone.of(a['badgeTone'] as String?), icon: status == 'approved' ? 'verified' : 'gpp_bad', title: a['badge'] as String, text: (v['note'] as String?)?.isNotEmpty == true ? v['note'] as String : null),
              if (status == 'changes_requested') BannerCard(tone: Tone.blue, icon: 'feedback', title: 'Changes requested', text: v['note'] as String?),
              KvCard([
                ('Qualification', (p['qualifications'] as String?)?.isNotEmpty == true ? p['qualifications'] as String : '—'),
                (isDoc ? 'SLMC registration' : 'Registration', p['registrationNo'] as String? ?? '—'),
                if (p['experienceYears'] != null) ('Experience', '${p['experienceYears']} years'),
                ('Email', a['email'] as String),
              ]),
              const SectionHeader('Documents'),
              if (docs.isEmpty)
                const BannerCard(tone: Tone.amber, icon: 'upload_file', text: 'No documents uploaded yet. The applicant can upload them from their account.')
              else
                ListCards([
                  for (final d in docs)
                    ListItemData(
                      icon: d['label'] == 'National ID' ? 'badge' : 'description',
                      tone: d['checked'] == true ? Tone.green : Tone.grey,
                      title: '${d['label']}',
                      sub: '${d['fileName']} · ${Fmt.fileSize(d['size'] as num?)}',
                      badge: d['checked'] == true ? 'Checked' : null,
                      onTap: () async {
                        await push(context, DocumentViewScreen(ownerId: a['id'] as String, doc: d, ownerName: a['name'] as String));
                        reload();
                      },
                    ),
                ]),
              ChecksCard(title: 'Checklist', [
                (docs.isNotEmpty && docs.every((d) => d['checked'] == true), 'Every document opened and checked'),
                ((p['registrationNo'] as String?)?.isNotEmpty == true, isDoc ? 'SLMC number provided' : 'Registration number provided'),
                (a['email'].toString().endsWith('sliit.lk'), 'University staff email'),
              ]),
              if (open) LinksRow([('Request changes', () => push(context, RequestChangesScreen(application: a), root: true).then((_) => reload()))]),
            ],
            footRow: true,
            foot: open
                ? [
                    MbButton('Reject', kind: BtnKind.dangerSoft, onPressed: () => push(context, RejectApplicationScreen(application: a), root: true).then((_) => reload())),
                    MbButton('Approve', onPressed: () => _approve(a)),
                  ]
                : const [],
          );
        },
      );
}

/// M3-15 / M3-22
class DocumentViewScreen extends StatefulWidget {
  const DocumentViewScreen({super.key, required this.ownerId, required this.doc, required this.ownerName});
  final String ownerId;
  final Map<String, dynamic> doc;
  final String ownerName;

  @override
  State<DocumentViewScreen> createState() => _DocumentViewScreenState();
}

class _DocumentViewScreenState extends State<DocumentViewScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final isPdf = (d['mimeType'] as String? ?? '').contains('pdf');
    return MbPage(
      title: '${d['label']}',
      subtitle: widget.ownerName,
      actions: [HeaderAction('open_in_new', tooltip: 'Open document', onTap: () => openDownload(context, {'target': 'document', 'ownerId': widget.ownerId, 'docId': d['id']}))],
      children: [
        MbCard(
          onTap: () => openDownload(context, {'target': 'document', 'ownerId': widget.ownerId, 'docId': d['id']}),
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          child: Column(children: [
            MbIcon(isPdf ? 'picture_as_pdf' : 'image', size: 56, color: C.primary),
            const SizedBox(height: 12),
            Text('${d['fileName']}', textAlign: TextAlign.center, style: Ty.nunito(size: 15, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Tap to open in your browser', style: Ty.sm),
          ]),
        ),
        KvCard([('Uploaded', d['uploadedAt'] == null ? '—' : Fmt.dayYear(d['uploadedAt'])), ('Size', Fmt.fileSize(d['size'] as num?)), ('Status', d['checked'] == true ? 'Checked' : 'Not checked yet')]),
        const BannerCard(icon: 'lock', text: 'Opening a credential is recorded in the activity log. The link works once and expires after 2 minutes.'),
      ],
      foot: [
        MbButton(d['checked'] == true ? 'Mark as not checked' : 'Mark document checked', kind: d['checked'] == true ? BtnKind.secondary : BtnKind.primary, loading: _busy, onPressed: () async {
          setState(() => _busy = true);
          final r = await guard(context, () => api.patch('/admin/verifications/${widget.ownerId}/documents/${d['id']}', {'checked': d['checked'] != true}));
          if (mounted) setState(() => _busy = false);
          if (r != null && context.mounted) Navigator.of(context).pop();
        }),
      ],
    );
  }
}

/// M3-18 / M3-25
class RejectApplicationScreen extends StatefulWidget {
  const RejectApplicationScreen({super.key, required this.application});
  final Map<String, dynamic> application;

  @override
  State<RejectApplicationScreen> createState() => _RejectApplicationScreenState();
}

class _RejectApplicationScreenState extends State<RejectApplicationScreen> {
  late final List<String> _reasons = widget.application['role'] == 'doctor'
      ? const ['SLMC registration not found', 'Not a university staff member', 'Documents incomplete', 'Other']
      : const ['Registration can’t be verified', 'Qualification doesn’t meet requirements', 'Documents incomplete', 'Other'];
  int _reason = 0;
  final _msg = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Reject application',
        subtitle: widget.application['name'] as String,
        children: [
          OptionsList(items: [for (final r in _reasons) OptionItem(r)], selected: _reason, onSelect: (i) => setState(() => _reason = i)),
          MbField(label: 'Message to applicant', controller: _msg, type: FieldType.area, rows: 3, hint: 'Explain what happened and any next steps', maxLength: 1000),
        ],
        foot: [
          MbButton('Reject application', kind: BtnKind.danger, loading: _busy, onPressed: () async {
            setState(() => _busy = true);
            final r = await guard(context, () => api.post('/admin/verifications/${widget.application['id']}/reject', {'reason': _reasons[_reason], 'message': _msg.text.trim()}));
            if (mounted) setState(() => _busy = false);
            if (r != null && context.mounted) {
              Navigator.of(context).pop();
              toast(context, 'Application rejected. The applicant has been told why.');
            }
          }),
        ],
      );
}

/// M3-19
class RequestChangesScreen extends StatefulWidget {
  const RequestChangesScreen({super.key, required this.application});
  final Map<String, dynamic> application;

  @override
  State<RequestChangesScreen> createState() => _RequestChangesScreenState();
}

class _RequestChangesScreenState extends State<RequestChangesScreen> {
  late final List<String> _items = <String>{
    ...(((widget.application['verification'] as Map)['documents'] as List?) ?? []).map((d) => (d as Map)['label'] as String),
    if (widget.application['role'] == 'doctor') ...['SLMC certificate', 'National ID'] else ...['Degree certificate', 'Registration certificate', 'National ID'],
    'Profile details',
  }.toList();
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
        title: 'Request changes',
        subtitle: widget.application['name'] as String,
        children: [
          const SectionHeader('What needs updating?'),
          Chips(wrap: true, items: _items, selected: _sel, onTap: (i) => setState(() => _sel.contains(i) ? _sel.remove(i) : _sel.add(i))),
          MbField(label: 'Message', controller: _msg, type: FieldType.area, rows: 3, hint: 'e.g. The registration scan is blurry. Please upload a clearer copy.', maxLength: 1000),
          const Txt('The application stays pending and the applicant can re-upload from their account.', size: TxtSize.sm),
        ],
        foot: [
          MbButton('Send request', loading: _busy, onPressed: () async {
            if (_sel.isEmpty || _msg.text.trim().isEmpty) {
              toast(context, 'Choose what needs updating and add a message.');
              return;
            }
            setState(() => _busy = true);
            final r = await guard(context, () => api.post('/admin/verifications/${widget.application['id']}/request-changes', {'items': [for (final i in _sel) _items[i]], 'message': _msg.text.trim()}));
            if (mounted) setState(() => _busy = false);
            if (r != null && context.mounted) {
              Navigator.of(context).pop();
              toast(context, 'Request sent.');
            }
          }),
        ],
      );
}
