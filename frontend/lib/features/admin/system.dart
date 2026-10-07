import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../modules/user/users.dart';
import '../../state/auth.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../common/account.dart';
import 'admin_shell.dart';
import 'music_admin.dart';

/// M3-45
class SystemScreen extends StatelessWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'System',
        root: true,
        children: [
          MenuCard(title: 'Configuration', [
            MenuItemData('event', 'Appointment settings', onTap: () => push(context, const SettingsScreen(section: 'appointments'))),
            MenuItemData('notifications', 'Notification settings', onTap: () => push(context, const SettingsScreen(section: 'notifications'))),
            MenuItemData('shield', 'Privacy settings', onTap: () => push(context, const SettingsScreen(section: 'privacy'))),
            MenuItemData('lock', 'Security settings', onTap: () => push(context, const SettingsScreen(section: 'security'))),
          ]),
          MenuCard(title: 'Oversight', [
            MenuItemData('history', 'System activity log', onTap: () => push(context, const ActivityLogScreen())),
            MenuItemData('admin_panel_settings', 'Roles & permissions', onTap: () => push(context, const RolesScreen())),
          ]),
          MenuCard(title: 'Content', [
            MenuItemData('library_music', 'Relaxing music', sub: 'Upload and manage tracks', onTap: () => push(context, const MusicAdminScreen())),
          ]),
          MenuCard(title: 'Account', [
            MenuItemData('person', 'My profile', onTap: () => push(context, const AdminProfileScreen())),
            MenuItemData('logout', 'Sign out', danger: true, onTap: () => confirmSignOut(context)),
          ]),
        ],
      );
}

/// M3-46 → M3-49 — every change is saved immediately and logged.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.section});
  final String section;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _s;
  ApiException? _error;

  String get _title => switch (widget.section) {
        'appointments' => 'Appointment settings',
        'notifications' => 'Notification settings',
        'privacy' => 'Privacy settings',
        _ => 'Security settings',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/admin/settings');
      if (mounted) setState(() => _s = ((r['settings'] as Map)[widget.section] as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _set(String key, Object value) async {
    final prev = _s![key];
    setState(() => _s![key] = value);
    final r = await guard(context, () => api.patch('/admin/settings/${widget.section}', {key: value}));
    if (!mounted) return;
    if (r == null) {
      setState(() => _s![key] = prev);
    } else {
      toast(context, 'Saved. The change is in the activity log.');
    }
  }

  Widget _toggle(String key, String title, {String? sub, bool locked = false}) => ToggleTile(title: title, sub: sub, value: _s![key] == true, locked: locked, onChanged: (v) => _set(key, v));

  Widget _select(String key, String label, List<int> options, String Function(int) fmt) => MbField(
        label: label,
        type: FieldType.select,
        value: fmt((_s![key] as num).toInt()),
        onTap: () async {
          final v = await pickOption(context, title: label, options: options.map(fmt).toList(), current: fmt((_s![key] as num).toInt()));
          if (v != null) _set(key, options[options.map(fmt).toList().indexOf(v)]);
        },
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return MbPage(title: _title, children: [_error != null ? ErrorBlock(error: _error!, onRetry: _load) : const LoadingList(n: 4)]);
    final children = switch (widget.section) {
      'appointments' => <Widget>[
          const SectionHeader('Default session length'),
          Segmented(items: const ['30 min', '45 min', '60 min'], index: [30, 45, 60].indexOf((s['defaultSessionLength'] as num).toInt()).clamp(0, 2), onChanged: (i) => _set('defaultSessionLength', [30, 45, 60][i])),
          _select('bookingWindowDays', 'Booking window', [7, 14, 21, 28], (d) => 'Up to ${d ~/ 7} week${d > 7 ? 's' : ''} ahead'),
          _select('minCancelNoticeHours', 'Minimum notice to cancel', [1, 2, 6, 24], (h) => '$h hour${h > 1 ? 's' : ''}'),
          _toggle('blockDuplicateBookings', 'Block duplicate active bookings', sub: 'One active booking per student (FR7)'),
          _toggle('allowOnline', 'Allow online sessions'),
          _toggle('allowInPerson', 'Allow in-person sessions'),
          _toggle('autoCancelEnabled', 'Auto-cancel unconfirmed requests', sub: 'After ${s['autoCancelUnconfirmedHours']} hours, so the slot goes back to other students'),
        ],
      'notifications' => <Widget>[
          _toggle('reminderDay', 'Reminder 24 hours before'),
          _toggle('reminderHour', 'Reminder 1 hour before'),
          _toggle('dailyCheckinNudge', 'Daily check-in nudge', sub: 'Sent at 7 PM to students who haven’t checked in. Students can turn this off.'),
          _toggle('counsellorRequestAlerts', 'Counsellor request alerts'),
          _toggle('duplicateAlerts', 'Duplicate booking alerts'),
        ],
      'privacy' => <Widget>[
          ToggleTile(title: 'Hide report groups smaller than ${s['minReportGroupSize']}', sub: 'Required by privacy policy', value: true, locked: true),
          _select('sessionNoteRetentionYears', 'Keep session notes for', [1, 3, 5, 7], (y) => '$y year${y > 1 ? 's' : ''}'),
          _toggle('autoDeleteBridgeChats', 'Auto-delete Bridge chats after ${s['bridgeChatRetentionDays']} days'),
          _toggle('showHelplineEverywhere', 'Show 1926 helpline on every student screen'),
        ],
      _ => <Widget>[
          _toggle('staffTwoFactor', 'Two-factor sign-in for counsellors and doctors', sub: 'Admins always use two-factor sign-in'),
          _select('autoSignOutMinutes', 'Auto sign-out after', [5, 10, 15, 30], (m) => '$m minutes'),
          MbField(label: 'Password policy', type: FieldType.select, value: s['passwordPolicy'] as String, enabled: false, helper: 'Enforced for every account'),
          const SectionHeader('Your active sessions'),
          const ActiveSessionsCard(),
        ],
    };
    return MbPage(title: _title, onRefresh: _load, children: children);
  }
}

/// M3-55
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  int _chip = 0;
  static const _cats = ['', 'users', 'verification', 'articles', 'music', 'settings', 'access'];

  @override
  Widget build(BuildContext context) {
    final chips = Chips(items: const ['All', 'Users', 'Verification', 'Articles', 'Music', 'Settings', 'Record access'], selected: {_chip}, onTap: (i) => setState(() => _chip = i));
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_chip),
      load: () => api.get('/admin/logs', query: {'category': _cats[_chip]}),
      wrap: (c) => MbPage(title: 'Activity log', children: [chips, c]),
      builder: (context, d, reload) {
        final logs = (d['logs'] as List).cast<Map<String, dynamic>>();
        return MbPage(
          title: 'Activity log',
          onRefresh: reload,
          children: [
            chips,
            if (logs.isEmpty) const StateView(icon: 'history', tone: Tone.grey, title: 'No activity', text: 'Actions in this category will appear here.') else ListCards(logs.map(logItem).toList()),
            const Txt('Logs record who did what. They never include session or check-in content.', size: TxtSize.xs, align: TextAlign.center),
          ],
        );
      },
    );
  }
}

/// M3-52 / M3-53
class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AuthState>().user ?? const {};
    final p = (u['professional'] as Map?)?.cast<String, dynamic>() ?? {};
    return MbPage(
      title: 'My profile',
      children: [
        ProfileHeader(initials: u['initials'] as String? ?? '', name: u['name'] as String? ?? '', sub: 'Student Affairs · Administrator'),
        KvCard([('Email', u['email'] as String? ?? ''), ('Role', 'Admin'), ('Office', p['office'] as String? ?? '—'), ('Extension', p['extension'] as String? ?? '—'), ('2FA', 'On')]),
        MenuCard([
          MenuItemData('person', 'Edit profile', onTap: () => push(context, const EditAdminProfileScreen(), root: true)),
          MenuItemData('key', 'Change password', onTap: () => push(context, const ChangePasswordScreen(), root: true)),
        ]),
      ],
    );
  }
}

class EditAdminProfileScreen extends StatefulWidget {
  const EditAdminProfileScreen({super.key});

  @override
  State<EditAdminProfileScreen> createState() => _EditAdminProfileScreenState();
}

class _EditAdminProfileScreenState extends State<EditAdminProfileScreen> {
  late final Map<String, dynamic> u = context.read<AuthState>().user!;
  late final Map<String, dynamic> p = (u['professional'] as Map?)?.cast<String, dynamic>() ?? {};
  late final _name = TextEditingController(text: u['name'] as String? ?? '');
  late final _office = TextEditingController(text: p['office'] as String? ?? '');
  late final _ext = TextEditingController(text: p['extension'] as String? ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _office.dispose();
    _ext.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Edit profile',
        bg: PageBg.white,
        children: [
          MbField(label: 'Name', controller: _name, capitalization: TextCapitalization.words),
          MbField(label: 'Office', controller: _office, hint: 'Student Affairs · Block A'),
          MbField(label: 'Phone extension', controller: _ext, type: FieldType.number, maxLength: 10),
          MbField(label: 'Email', type: FieldType.select, value: u['email'] as String?, enabled: false),
        ],
        foot: [
          MbButton('Save changes', loading: _busy, onPressed: () async {
            setState(() => _busy = true);
            final r = await guard(context, () => api.patch('/me', {'name': _name.text.trim(), 'professional': {'office': _office.text.trim(), 'extension': _ext.text.trim()}}));
            if (mounted) setState(() => _busy = false);
            if (r != null && context.mounted) {
              context.read<AuthState>().setUser(r['user'] as Map<String, dynamic>);
              Navigator.of(context).pop();
              toast(context, 'Profile updated.');
            }
          }),
        ],
      );
}
