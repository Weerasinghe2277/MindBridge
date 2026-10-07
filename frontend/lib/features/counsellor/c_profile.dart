import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../modules/availability/availability.dart';
import '../../modules/referral/counsellor_referrals.dart';
import '../../state/auth.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../common/account.dart';
import '../common/notifications.dart';
import 'counsellor_shell.dart';

/// M2-36 — also used by doctors (with their own menu items).
class CounsellorAccountScreen extends StatelessWidget {
  const CounsellorAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final u = auth.user ?? const {};
    final p = (u['professional'] as Map?)?.cast<String, dynamic>() ?? {};
    return Loader<Map<String, dynamic>>(
      load: () async {
        final r = await Future.wait([api.get('/counsellors/${u['id']}'), api.get('/articles/mine')]);
        return {'sessions': (r[0]['counsellor'] as Map)['sessionsCompleted'], 'articles': (r[1]['stats'] as Map)['published']};
      },
      wrap: (c) => MbPage(title: 'Profile', root: true, children: [c]),
      builder: (context, d, reload) {
        const abbrev = {'English': 'EN', 'Sinhala': 'SI', 'Tamil': 'TA'};
        return MbPage(
          title: 'Profile',
          root: true,
          onRefresh: () async {
            await auth.refreshUser();
            await reload();
          },
          children: [
            ProfileHeader(initials: u['initials'] as String? ?? '', name: u['name'] as String? ?? '', sub: [p['title'], if (p['experienceYears'] != null) '${p['experienceYears']} years'].whereType<String>().join(' · '), badge: 'Verified counsellor'),
            StatsGrid(cols: 3, [
              StatItem('${d['sessions']}', 'Sessions'),
              StatItem('${d['articles']}', 'Articles'),
              StatItem(((p['languages'] as List?) ?? ['English']).map((l) => abbrev[l] ?? l).join(' · '), 'Languages'),
            ]),
            MenuCard([
              MenuItemData('person', 'Edit profile', onTap: () => push(context, const EditStaffProfileScreen(), root: true)),
              MenuItemData('verified', 'Verification', value: 'Verified', onTap: () => push(context, const VerificationInfoScreen())),
              MenuItemData('schedule', 'Availability', onTap: () => push(context, const AvailabilityScreen())),
              MenuItemData('local_hospital', 'My referrals', onTap: () => push(context, const CounsellorReferralsScreen())),
              MenuItemData('notifications', 'Notifications', onTap: () => push(context, const NotificationsScreen(onOpen: openCounsellorLink))),
              MenuItemData('settings', 'Settings', onTap: () => push(context, const StaffSettingsScreen())),
            ]),
            MenuCard([MenuItemData('logout', 'Sign out', danger: true, onTap: () => confirmSignOut(context))]),
          ],
        );
      },
    );
  }
}

const focusOptions = ['Stress', 'Anxiety', 'Exam pressure', 'Sleep', 'Relationships', 'Low mood', 'Homesickness', 'First-year adjustment', 'Academic pressure', 'Mindfulness', 'Motivation'];

/// M2-37 / M4-16 — staff profile editing. Registration numbers are verified and read-only.
class EditStaffProfileScreen extends StatefulWidget {
  const EditStaffProfileScreen({super.key});

  @override
  State<EditStaffProfileScreen> createState() => _EditStaffProfileScreenState();
}

class _EditStaffProfileScreenState extends State<EditStaffProfileScreen> {
  late final Map<String, dynamic> u = context.read<AuthState>().user!;
  late final Map<String, dynamic> p = (u['professional'] as Map?)?.cast<String, dynamic>() ?? {};
  late final bool _doctor = u['role'] == 'doctor';
  late final _name = TextEditingController(text: u['name'] as String? ?? '');
  late final _title = TextEditingController(text: p['title'] as String? ?? '');
  late final _qual = TextEditingController(text: p['qualifications'] as String? ?? '');
  late final _about = TextEditingController(text: p['about'] as String? ?? '');
  late final _room = TextEditingController(text: (p['room'] ?? '') as String);
  late final _phone = TextEditingController(text: u['phone'] as String? ?? '');
  late final Set<String> _focus = {...((p['focusAreas'] as List?) ?? []).cast<String>()};
  late final Set<String> _langs = {...((p['languages'] as List?) ?? ['English']).cast<String>()};
  late final Set<String> _modes = {...((p['modes'] as List?) ?? ['online', 'in_person']).cast<String>()};
  late String _gender = u['gender'] as String? ?? '';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _title, _qual, _about, _room, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_langs.isEmpty || _modes.isEmpty) {
      toast(context, 'Choose at least one language and meeting type.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await api.patch('/me', {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'gender': _gender,
        'professional': {
          'title': _title.text.trim(),
          'qualifications': _qual.text.trim(),
          'room': _room.text.trim(),
          if (!_doctor) ...{'about': _about.text.trim(), 'focusAreas': _focus.toList(), 'languages': _langs.toList(), 'modes': _modes.toList()},
        },
      });
      if (!mounted) return;
      context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
      Navigator.of(context).pop();
      toast(context, 'Profile updated.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final focusAll = {...focusOptions, ..._focus}.toList();
    return MbPage(
      title: 'Edit profile',
      bg: PageBg.white,
      children: [
        MbField(label: 'Display name', controller: _name, capitalization: TextCapitalization.words),
        MbField(label: 'Title', controller: _title),
        MbField(label: _doctor ? 'SLMC registration' : 'Professional registration', type: FieldType.select, value: p['registrationNo'] as String?, enabled: false, helper: 'Verified by Student Affairs'),
        MbField(label: 'Qualifications', controller: _qual, type: FieldType.area, rows: 2),
        MbField(label: _doctor ? 'Consultation room' : 'Room for in-person sessions', controller: _room, hint: _doctor ? 'Medical Centre · Room 4' : 'Wellbeing Centre, Room 2.14'),
        MbField(label: 'Work phone (optional)', controller: _phone, type: FieldType.phone),
        if (!_doctor) ...[
          const SectionHeader('Focus areas'),
          Chips(wrap: true, items: focusAll, selected: {for (var i = 0; i < focusAll.length; i++) if (_focus.contains(focusAll[i])) i}, onTap: (i) => setState(() => _focus.contains(focusAll[i]) ? _focus.remove(focusAll[i]) : _focus.add(focusAll[i]))),
          const SectionHeader('Languages'),
          Chips(wrap: true, items: const ['English', 'Sinhala', 'Tamil'], selected: {for (var i = 0; i < 3; i++) if (_langs.contains(['English', 'Sinhala', 'Tamil'][i])) i}, onTap: (i) {
            final l = ['English', 'Sinhala', 'Tamil'][i];
            setState(() => _langs.contains(l) ? _langs.remove(l) : _langs.add(l));
          }),
          const SectionHeader('Meeting types'),
          Chips(wrap: true, items: const ['Online', 'In person'], selected: {if (_modes.contains('online')) 0, if (_modes.contains('in_person')) 1}, onTap: (i) {
            final m = ['online', 'in_person'][i];
            setState(() => _modes.contains(m) ? _modes.remove(m) : _modes.add(m));
          }),
          const SectionHeader('Gender (helps students who have a preference)'),
          Chips(wrap: true, items: const ['Prefer not to say', 'Female', 'Male'], selected: {['', 'female', 'male'].indexOf(_gender).clamp(0, 2)}, onTap: (i) => setState(() => _gender = ['', 'female', 'male'][i])),
          MbField(label: 'About', controller: _about, type: FieldType.area, rows: 3, hint: 'How you work with students', maxLength: 1500),
        ],
      ],
      foot: [MbButton('Save changes', loading: _busy, onPressed: _save)],
    );
  }
}

/// M2-38
class VerificationInfoScreen extends StatelessWidget {
  const VerificationInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthState>().user ?? const {};
    final v = (u['verification'] as Map?)?.cast<String, dynamic>() ?? {};
    final p = (u['professional'] as Map?)?.cast<String, dynamic>() ?? {};
    final docs = ((v['documents'] as List?) ?? []).cast<Map<String, dynamic>>();
    return MbPage(
      title: 'Verification',
      children: [
        HeroCard(style: HeroStyle.soft, eyebrow: 'Status', badge: 'Verified', title: u['role'] == 'doctor' ? 'Verified doctor' : 'Verified counsellor', sub: v['reviewedAt'] != null ? 'Approved by Student Affairs on ${Fmt.dayYear(v['reviewedAt'])}' : 'Approved by Student Affairs'),
        KvCard([('Registration', p['registrationNo'] as String? ?? '—'), if (p['renewalDue'] != null) ('Renewal due', p['renewalDue'] as String)]),
        const SectionHeader('Documents'),
        if (docs.isEmpty)
          const BannerCard(tone: Tone.grey, icon: 'description', text: 'Verified in person by Student Affairs.')
        else
          ListCards([for (final d in docs) ListItemData(icon: d['label'] == 'National ID' ? 'badge' : 'description', title: '${d['label']}', sub: d['fileName'] as String?, badge: 'Verified')]),
      ],
    );
  }
}

/// M2-46 / M4-17 — settings and notification preferences (M2-48).
class StaffSettingsScreen extends StatelessWidget {
  const StaffSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final privacy = (auth.user?['privacy'] as Map?)?.cast<String, dynamic>() ?? {};
    return MbPage(
      title: 'Settings',
      children: [
        MenuCard([
          MenuItemData('notifications', 'Notification preferences', onTap: () => push(context, const NotificationPrefsScreen())),
          MenuItemData('key', 'Change password', onTap: () => push(context, const ChangePasswordScreen(), root: true)),
          if (auth.role == 'counsellor') MenuItemData('schedule', 'Availability', onTap: () => push(context, const AvailabilityScreen())),
        ]),
        ToggleTile(title: 'Biometric unlock', value: privacy['biometricUnlock'] == true, onChanged: (v) async {
          final r = await guard(context, () => api.patch('/me/privacy', {'biometricUnlock': v}));
          if (r != null && context.mounted) context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
        }),
        const ToggleTile(title: 'Auto sign-out after 15 minutes', sub: 'Set by Student Affairs to protect session notes', value: true, locked: true),
        const SectionHeader('Signed-in devices'),
        const ActiveSessionsCard(),
        MenuCard([MenuItemData('logout', 'Sign out', danger: true, onTap: () => confirmSignOut(context))]),
      ],
    );
  }
}

class NotificationPrefsScreen extends StatelessWidget {
  const NotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final prefs = (auth.user?['notificationPrefs'] as Map?)?.cast<String, dynamic>() ?? {};
    final doctor = auth.role == 'doctor';
    final items = doctor
        ? const [('referralUpdates', 'New and updated referrals', 'Urgent referrals always come through'), ('reminders', 'Consultation reminders', null)]
        : const [
            ('newRequests', 'New booking requests', null),
            ('duplicateAlerts', 'Duplicate booking alerts', null),
            ('reschedules', 'Reschedules & cancellations', null),
            ('reminders', 'Session reminders', '24 hours and 1 hour before'),
            ('articleUpdates', 'Article review updates', null),
            ('referralUpdates', 'Referral updates', null),
          ];
    return MbPage(
      title: 'Notification preferences',
      children: [
        for (final (key, title, sub) in items)
          ToggleTile(title: title, sub: sub, value: prefs[key] != false, onChanged: (v) async {
            final r = await guard(context, () => api.patch('/me/notification-prefs', {key: v}));
            if (r != null && context.mounted) context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
          }),
        const BannerCard(tone: Tone.blue, icon: 'info', text: 'Safety-related messages from Student Affairs are always delivered.'),
      ],
    );
  }
}
