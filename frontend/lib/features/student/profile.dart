import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../modules/mood/mood.dart';
import '../../state/auth.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../common/account.dart';
import '../common/notifications.dart';
import '../wellness/emergency.dart';
import 'student_shell.dart';

/// M1-29
class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user ?? const {};
    final faculty = (u['faculty'] as String? ?? '');
    return MbPage(
      title: 'Profile',
      root: true,
      onRefresh: auth.refreshUser,
      children: [
        ProfileHeader(
          initials: u['initials'] as String? ?? '',
          name: u['name'] as String? ?? '',
          sub: [u['studentId'], faculty, if (u['year'] != null) 'Year ${u['year']}'].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
        ),
        MenuCard(title: 'Account', [
          MenuItemData('person', 'Edit profile', onTap: () => push(context, const EditStudentProfileScreen(), root: true)),
          MenuItemData('shield_lock', 'Privacy & security', onTap: () => push(context, const PrivacySecurityScreen())),
          MenuItemData('key', 'Change password', onTap: () => push(context, const ChangePasswordScreen(), root: true)),
          MenuItemData('notifications', 'Notifications', onTap: () => push(context, const NotificationsScreen(onOpen: openStudentLink))),
          MenuItemData('insights', 'Mood history', onTap: () => push(context, const MoodHistoryScreen())),
        ]),
        MenuCard([
          MenuItemData('call', 'Emergency contacts', value: '1926', onTap: () => push(context, const EmergencyInfoScreen(), root: true)),
          MenuItemData('logout', 'Sign out', danger: true, onTap: () => confirmSignOut(context)),
        ]),
        Center(child: Text('MindBridge · SLIIT Student Affairs', style: Ty.xs)),
      ],
    );
  }
}

/// M1-30
class EditStudentProfileScreen extends StatefulWidget {
  const EditStudentProfileScreen({super.key});

  @override
  State<EditStudentProfileScreen> createState() => _EditStudentProfileScreenState();
}

class _EditStudentProfileScreenState extends State<EditStudentProfileScreen> {
  late final Map<String, dynamic> u = context.read<AuthState>().user!;
  late final _preferred = TextEditingController(text: u['preferredName'] as String? ?? '');
  late final _name = TextEditingController(text: u['name'] as String? ?? '');
  late final _phone = TextEditingController(text: u['phone'] as String? ?? '');
  late String _lang = u['language'] as String? ?? 'English';
  late int? _year = u['year'] as int?;
  final Map<String, String> _err = {};
  bool _busy = false;

  @override
  void dispose() {
    _preferred.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _err.clear();
    if (_name.text.trim().length < 2) _err['name'] = 'Enter your full name';
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^\+?[\d\s-]{7,20}$').hasMatch(phone)) _err['phone'] = 'Enter a valid phone number';
    setState(() {});
    if (_err.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await api.patch('/me', {
        'name': _name.text.trim(),
        'preferredName': _preferred.text.trim(),
        'phone': phone,
        'language': _lang,
        if (_year != null) 'year': _year,
      });
      if (!mounted) return;
      context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
      Navigator.of(context).pop();
      toast(context, 'Profile updated.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _err[e.field ?? 'name'] = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Edit profile',
        bg: PageBg.white,
        children: [
          ProfileHeader(initials: u['initials'] as String? ?? '', name: _name.text.isEmpty ? (u['name'] as String) : _name.text),
          MbField(label: 'Preferred name', controller: _preferred, helper: 'What Bridge and your counsellor will call you', capitalization: TextCapitalization.words),
          MbField(label: 'Full name', controller: _name, error: _err['name'], capitalization: TextCapitalization.words, onChanged: (_) => setState(() {})),
          MbField(label: 'University email', type: FieldType.select, value: u['email'] as String?, enabled: false, helper: 'Managed by the university'),
          MbField(label: 'Student ID', type: FieldType.select, value: u['studentId'] as String?, enabled: false),
          MbField(label: 'Phone', controller: _phone, type: FieldType.phone, hint: '+94 77 123 4567', error: _err['phone'], helper: 'Only shared with a doctor if your counsellor refers you and you agree'),
          MbField(label: 'Year of study', type: FieldType.select, value: _year == null ? null : 'Year $_year', onTap: () async {
            final v = await pickOption(context, title: 'Year of study', options: const ['Year 1', 'Year 2', 'Year 3', 'Year 4'], current: _year == null ? null : 'Year $_year');
            if (v != null) setState(() => _year = int.parse(v.split(' ').last));
          }),
          MbField(label: 'Preferred language', type: FieldType.select, value: _lang, onTap: () async {
            final v = await pickOption(context, title: 'Preferred language', options: const ['English', 'Sinhala', 'Tamil'], current: _lang);
            if (v != null) setState(() => _lang = v);
          }),
        ],
        foot: [MbButton('Save changes', loading: _busy, onPressed: _save)],
      );
}

/// M1-31 — who can see what, in plain words (NFR1, NFR2, NFR4).
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  Future<void> _set(String key, bool v) async {
    final r = await guard(context, () => api.patch('/me/privacy', {key: v}));
    if (r != null && mounted) context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final p = (context.watch<AuthState>().user?['privacy'] as Map?)?.cast<String, dynamic>() ?? {};
    return MbPage(
      title: 'Privacy & security',
      children: [
        ChecksCard(title: 'Your counsellor can see', [
          (true, 'Your name and student ID'),
          (true, 'Booking date, time and note'),
          (p['shareMoodTrends'] == true, p['shareMoodTrends'] == true ? 'Your weekly mood trend (you turned this on)' : 'Your mood check-ins and journal'),
          (false, 'Your chats with Bridge'),
        ]),
        const ChecksCard(title: 'Administrators can see', [(true, 'Anonymous usage totals'), (false, 'Any booking or session details')]),
        ToggleTile(title: 'Share mood trends with my counsellor', sub: 'Off by default. Shares weekly averages only — never notes or your journal.', value: p['shareMoodTrends'] == true, onChanged: (v) => _set('shareMoodTrends', v)),
        const QuickUnlockTile(),
        ToggleTile(title: 'Hide notification previews', sub: 'Shows “MindBridge update” on the lock screen', value: p['hidePreviews'] != false, onChanged: (v) => _set('hidePreviews', v)),
        const SectionHeader('Signed-in devices'),
        const ActiveSessionsCard(),
        MenuCard([
          MenuItemData('download', 'Download my data', onTap: () => push(context, const DataExportScreen())),
          MenuItemData('delete', 'Delete account', danger: true, onTap: () => push(context, const DeleteAccountScreen(), root: true)),
        ]),
      ],
    );
  }
}

/// Everything MindBridge holds about the student, readable and copyable (NFR1).
class DataExportScreen extends StatelessWidget {
  const DataExportScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/me/export'),
        wrap: (c) => MbPage(title: 'Download my data', children: [c]),
        builder: (context, d, reload) {
          final json = const JsonEncoder.withIndent('  ').convert(d);
          return MbPage(
            title: 'Download my data',
            children: [
              const BannerCard(tone: Tone.blue, icon: 'info', text: 'This is everything MindBridge stores about you. Copy it to keep a record or share it with Student Affairs.'),
              KvCard([
                ('Bookings', '${(d['appointments'] as List).length}'),
                ('Mood check-ins', '${(d['moodCheckins'] as List).length}'),
                ('Journal entries', '${(d['journal'] as List).length}'),
                ('Bridge messages', '${(d['bridgeChats'] as List).length}'),
              ], title: 'Summary'),
              MbCard(
                padding: const EdgeInsets.all(14),
                child: SelectableText(json.length > 4000 ? '${json.substring(0, 4000)}\n…' : json, style: Ty.nunito(size: 11.5, color: C.body).copyWith(fontFamily: 'monospace')),
              ),
            ],
            foot: [
              MbButton('Copy all as JSON', icon: 'content_copy', onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (context.mounted) toast(context, 'Copied to clipboard.');
              }),
            ],
          );
        },
      );
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _pw = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_pw.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm');
      return;
    }
    setState(() => _busy = true);
    final auth = context.read<AuthState>();
    try {
      await api.delete('/me', {'password': _pw.text});
      await auth.logout();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Delete account',
        bg: PageBg.white,
        children: [
          const StateView(icon: 'delete', tone: Tone.red, title: 'Delete your account?', text: 'Your check-ins, journal and Bridge chats are deleted straight away. Active bookings are cancelled and your counsellor is told.', padding: EdgeInsets.fromLTRB(8, 10, 8, 6)),
          MbField(label: 'Password', controller: _pw, type: FieldType.password, error: _error),
          const BannerCard(tone: Tone.amber, icon: 'warning', text: 'This can’t be undone. Consider downloading your data first.'),
        ],
        foot: [
          MbButton('Delete my account', kind: BtnKind.danger, loading: _busy, onPressed: _delete),
          MbButton('Keep my account', kind: BtnKind.ghost, onPressed: () => Navigator.of(context).pop()),
        ],
      );
}
