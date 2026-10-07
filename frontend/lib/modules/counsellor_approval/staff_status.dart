// MEMBER 2 — Counsellor Approval: the applicant’s verification status and documents.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// What a counsellor or doctor sees until Student Affairs verifies them (M2-02 / M2-04, FR11).
class StaffStatusScreen extends StatefulWidget {
  const StaffStatusScreen({super.key});

  @override
  State<StaffStatusScreen> createState() => _StaffStatusScreenState();
}

class _StaffStatusScreenState extends State<StaffStatusScreen> {
  String? _uploading;
  bool _refreshing = false;
  bool _resubmitting = false;

  List<String> _required(String role) => role == 'doctor' ? const ['SLMC certificate', 'National ID'] : const ['Degree certificate', 'Registration certificate', 'National ID'];

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await context.read<AuthState>().refreshUser();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _upload(String label) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png']);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) toast(context, 'Files must be 5 MB or smaller.');
      return;
    }
    setState(() => _uploading = label);
    try {
      final r = await api.upload('/me/documents', bytes: bytes, filename: f.name, fields: {'label': label});
      if (mounted) context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _resubmit() async {
    setState(() => _resubmitting = true);
    try {
      final r = await api.post('/me/verification/resubmit');
      if (!mounted) return;
      context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
      toast(context, 'Sent to Student Affairs for review.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _resubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user!;
    final v = (u['verification'] as Map?)?.cast<String, dynamic>() ?? {};
    final status = v['status'] as String? ?? 'pending';
    final docs = ((v['documents'] as List?) ?? []).cast<Map<String, dynamic>>();
    final requested = ((v['requestedItems'] as List?) ?? []).cast<String>();
    final history = ((v['history'] as List?) ?? []).cast<Map<String, dynamic>>();
    final required = _required(auth.role);
    final missing = required.where((r) => !docs.any((d) => d['label'] == r)).toList();
    final submitted = v['submittedAt'];

    final header = switch (status) {
      'rejected' => const StateView(icon: 'gpp_bad', tone: Tone.red, title: 'Verification not approved', text: 'You can fix the issue below and resubmit.'),
      'changes_requested' => const StateView(icon: 'feedback', tone: Tone.amber, title: 'Changes requested', text: 'Student Affairs needs a little more from you before approving your account.'),
      _ => const StateView(icon: 'hourglass_top', tone: Tone.amber, title: 'Verification in progress', text: 'Student Affairs is reviewing your credentials. This usually takes 2–3 working days.'),
    };

    return MbPage(
      bg: PageBg.white,
      onRefresh: _refresh,
      children: [
        header,
        if (status == 'pending')
          TimelineCard([
            TimelineStep('Application submitted', sub: submitted != null ? Fmt.dayYear(submitted) : '', state: 'done'),
            TimelineStep('Documents uploaded', sub: missing.isEmpty ? '${docs.length} files' : '${missing.length} still needed', state: missing.isEmpty ? 'done' : 'now'),
            TimelineStep('Admin review', sub: missing.isEmpty ? 'In progress' : '', state: missing.isEmpty ? 'now' : 'todo'),
            const TimelineStep('Account active'),
          ]),
        if ((status == 'changes_requested' || status == 'rejected') && (v['note'] as String?)?.isNotEmpty == true)
          BannerCard(tone: Tone.amber, icon: 'feedback', title: 'Note from Student Affairs', text: v['note'] as String),
        const SectionHeader('Your documents'),
        for (final label in {...required, ...docs.map((d) => d['label'] as String)})
          Builder(builder: (_) {
            final d = docs.where((x) => x['label'] == label).firstOrNull;
            final flagged = requested.contains(label);
            return ListTileCard(ListItemData(
              icon: d == null ? 'upload_file' : 'description',
              tone: flagged ? Tone.amber : (d == null ? Tone.grey : Tone.green),
              title: label,
              sub: d == null ? 'PDF, JPG or PNG · up to 5 MB' : '${d['fileName']} · ${Fmt.fileSize(d['size'] as num?)}',
              trailing: _uploading == label
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.primary))
                  : TextLink(d == null ? 'Upload' : (flagged ? 'Replace' : 'Change'), onTap: status == 'approved' ? null : () => _upload(label)),
            ));
          }),
        if (history.isNotEmpty) KvCard([for (final h in history.reversed.take(4)) (h['label'] as String, Fmt.stamp(h['at']))], title: 'History'),
        const BannerCard(icon: 'verified_user', text: 'Students can only find and book verified staff. You’ll get a notification as soon as a decision is made.'),
      ],
      foot: [
        if (status == 'changes_requested' || status == 'rejected') MbButton('Update and resubmit', loading: _resubmitting, onPressed: missing.isEmpty ? _resubmit : null),
        MbButton('Check status', kind: status == 'pending' ? BtnKind.primary : BtnKind.secondary, icon: 'refresh', loading: _refreshing, onPressed: _refresh),
        MbButton('Sign out', kind: BtnKind.ghost, onPressed: () => auth.logout()),
      ],
    );
  }
}
