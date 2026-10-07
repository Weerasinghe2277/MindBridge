// MEMBER 2 — User Management: view users, edit user (role), deactivate user.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../counsellor_approval/verification.dart';
import 'register.dart';

class UserFilter {
  Set<String> roles = {};
  String status = '';
  String joined = '';
  String faculty = '';

  bool get active => roles.isNotEmpty || status.isNotEmpty || joined.isNotEmpty || faculty.isNotEmpty;
  UserFilter copy() => UserFilter()
    ..roles = {...roles}
    ..status = status
    ..joined = joined
    ..faculty = faculty;
}

/// M3-05 / M3-56 / M3-60
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  int _chip = 0;
  var _filter = UserFilter();
  Map<String, dynamic>? _data;
  ApiException? _error;
  int _req = 0;

  static const _chipRoles = ['', 'student', 'counsellor', 'doctor', 'admin'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_req;
    final roles = _chip == 0 ? _filter.roles : {_chipRoles[_chip]};
    try {
      final r = await api.get('/admin/users', query: {'q': _q.text.trim(), 'role': roles.join(','), 'status': _filter.status, 'joined': _filter.joined, 'faculty': _filter.faculty});
      if (mounted && id == _req) setState(() {
        _data = r;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && id == _req) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = (_data?['users'] as List?)?.cast<Map<String, dynamic>>();
    return MbPage(
      title: 'Users',
      root: true,
      onRefresh: _load,
      children: [
        SearchBox(
          controller: _q,
          hint: 'Search by name, ID or email',
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), _load);
          },
          filterActive: _filter.active,
          onFilter: () async {
            final f = await push<UserFilter>(context, UserFilterScreen(initial: _filter), root: true);
            if (f != null) {
              setState(() {
                _filter = f;
                _chip = 0;
                _data = null;
              });
              _load();
            }
          },
        ),
        Chips(items: const ['All', 'Students', 'Counsellors', 'Doctors', 'Admins'], selected: {_chip}, onTap: (i) {
          setState(() {
            _chip = i;
            _data = null;
          });
          _load();
        }),
        if (_error != null)
          ErrorBlock(error: _error!, onRetry: _load)
        else if (list == null)
          const LoadingList(n: 5)
        else if (list.isEmpty)
          const StateView(icon: 'person_off', tone: Tone.grey, title: 'No users found', text: 'Check the ID or try searching by name or email.')
        else ...[
          Txt('${_data!['total']} user${_data!['total'] == 1 ? '' : 's'}${(_data!['total'] as num) > list.length ? ' · showing ${list.length}' : ''}', size: TxtSize.sm),
          ListCards([
            for (final u in list)
              ListItemData(
                avatar: u['initials'] as String,
                title: u['name'] as String,
                sub: [u['roleLabel'], u['studentId'] ?? (u['verification'] != null && u['verification'] != 'approved' && u['verification'] != 'not_required' ? 'awaiting verification' : null)].whereType<String>().join(' · '),
                badge: u['badge'] as String,
                badgeTone: Tone.of(u['badgeTone'] as String?),
                onTap: () async {
                  final pending = (u['role'] == 'counsellor' || u['role'] == 'doctor') && u['verification'] != 'approved';
                  await push(context, pending ? ApplicationScreen(id: u['id'] as String) : UserDetailScreen(id: u['id'] as String));
                  _load();
                },
              ),
          ]),
        ],
      ],
    );
  }
}

/// M3-06
class UserFilterScreen extends StatefulWidget {
  const UserFilterScreen({super.key, required this.initial});
  final UserFilter initial;

  @override
  State<UserFilterScreen> createState() => _UserFilterScreenState();
}

class _UserFilterScreenState extends State<UserFilterScreen> {
  late var f = widget.initial.copy();
  static const _roles = ['student', 'counsellor', 'doctor', 'admin'];
  static const _status = ['', 'active', 'pending', 'deactivated'];
  static const _joined = ['', 'month', 'year'];

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Filter users',
        bg: PageBg.white,
        children: [
          const SectionHeader('Role'),
          Chips(wrap: true, items: const ['Student', 'Counsellor', 'Doctor', 'Admin'], selected: {for (var i = 0; i < 4; i++) if (f.roles.contains(_roles[i])) i}, onTap: (i) => setState(() => f.roles.contains(_roles[i]) ? f.roles.remove(_roles[i]) : f.roles.add(_roles[i]))),
          const SectionHeader('Status'),
          Chips(wrap: true, items: const ['Any', 'Active', 'Pending', 'Deactivated'], selected: {_status.indexOf(f.status)}, onTap: (i) => setState(() => f.status = _status[i])),
          MbField(label: 'Faculty', type: FieldType.select, value: f.faculty.isEmpty ? 'All faculties' : f.faculty, onTap: () async {
            final v = await pickOption(context, title: 'Faculty', options: ['All faculties', ...faculties], current: f.faculty.isEmpty ? 'All faculties' : f.faculty);
            if (v != null) setState(() => f.faculty = v == 'All faculties' ? '' : v);
          }),
          const SectionHeader('Joined'),
          Segmented(items: const ['Any time', 'This month', 'This year'], index: _joined.indexOf(f.joined), onChanged: (i) => setState(() => f.joined = _joined[i])),
        ],
        footRow: true,
        foot: [
          MbButton('Reset', kind: BtnKind.secondary, onPressed: () => setState(() => f = UserFilter())),
          MbButton('Show results', onPressed: () => Navigator.of(context).pop(f)),
        ],
      );
}

/// M3-07
class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () async => (await api.get('/admin/users/$id'))['user'] as Map<String, dynamic>,
        wrap: (c) => MbPage(title: 'User', children: [c]),
        builder: (context, u, reload) {
          final active = u['status'] == 'active';
          Future<void> open(Widget page) async {
            await push(context, page, root: true);
            reload();
          }

          return MbPage(
            title: 'User',
            onRefresh: reload,
            children: [
              ProfileHeader(initials: u['initials'] as String, name: u['name'] as String, sub: u['email'] as String),
              KvCard([
                ('Role', u['roleLabel'] as String),
                if (u['studentId'] != null) ('Student ID', u['studentId'] as String),
                if (u['faculty'] != null) ('Faculty', (u['faculty'] as String).replaceFirst('Faculty of ', '')),
                ('Joined', Fmt.dayYear(u['createdAt'])),
                ('Last active', u['lastActiveAt'] == null ? 'Never' : Fmt.ago(u['lastActiveAt'])),
                ('Status', active ? 'Active' : 'Deactivated${(u['statusReason'] as String?)?.isNotEmpty == true ? ' · ${u['statusReason']}' : ''}'),
              ]),
              const BannerCard(icon: 'visibility_off', text: 'Admins can’t view bookings, session notes or check-ins.'),
              MenuCard([
                MenuItemData('manage_accounts', 'Change role', onTap: () => open(EditRoleScreen(user: u))),
                MenuItemData('lock_reset', 'Send password reset', onTap: () async {
                  final r = await showMbSheet(context, icon: 'lock_reset', tone: Tone.blue, title: 'Send a password reset code?', text: '${u['name']} will get a 6-digit code at ${u['email']}.', actions: [
                    SheetAction('Send code', run: (_) async {
                      await api.post('/admin/users/$id/password-reset');
                      return true;
                    }),
                    const SheetAction('Cancel', kind: BtnKind.ghost),
                  ]);
                  if (r == 'Send code' && context.mounted) toast(context, 'Reset code sent.');
                }),
                MenuItemData(active ? 'block' : 'check_circle', active ? 'Deactivate account' : 'Reactivate account', danger: active, onTap: () => open(AccountStatusScreen(user: u))),
              ]),
            ],
          );
        },
      );
}

const _roleOpts = [
  ('student', 'Student', 'Book sessions, wellness tools', 'school'),
  ('counsellor', 'Counsellor', 'Requires verification', 'psychology'),
  ('doctor', 'Doctor', 'Requires verification', 'stethoscope'),
  ('admin', 'Admin', 'Full system management', 'admin_panel_settings'),
];

/// M3-08 / M3-09 / M3-11
class EditRoleScreen extends StatefulWidget {
  const EditRoleScreen({super.key, required this.user});
  final Map<String, dynamic> user;

  @override
  State<EditRoleScreen> createState() => _EditRoleScreenState();
}

class _EditRoleScreenState extends State<EditRoleScreen> {
  late int _sel = _roleOpts.indexWhere((r) => r.$1 == widget.user['role']);

  Future<void> _review() async {
    final to = _roleOpts[_sel];
    if (to.$1 == widget.user['role']) {
      toast(context, '${widget.user['name']} is already a ${to.$2}.');
      return;
    }
    Map<String, dynamic>? done;
    await showMbSheet(
      context,
      icon: 'manage_accounts',
      tone: Tone.amber,
      title: 'Change role to ${to.$2}?',
      text: '${widget.user['name']} will be signed out and see the ${to.$2.toLowerCase()} experience next time.${to.$1 == 'counsellor' || to.$1 == 'doctor' ? ' The role stays inactive until credentials are verified.' : ''}',
      rows: [('From', widget.user['roleLabel'] as String), ('To', to.$2)],
      actions: [
        SheetAction('Confirm change', run: (_) async {
          done = await api.patch('/admin/users/${widget.user['id']}/role', {'role': to.$1});
          return true;
        }),
        const SheetAction('Cancel', kind: BtnKind.ghost),
      ],
    );
    if (done != null && mounted) replace(context, AccountUpdatedScreen(name: widget.user['name'] as String, change: 'Role → ${done!['to']}'), root: true);
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Assign role',
        subtitle: widget.user['name'] as String,
        children: [
          OptionsList(items: [for (final r in _roleOpts) OptionItem(r.$2, sub: r.$3, icon: r.$4)], selected: _sel, onSelect: (i) => setState(() => _sel = i)),
          const BannerCard(tone: Tone.amber, icon: 'info', text: 'Counsellor and doctor roles stay inactive until credentials are verified. People with active bookings must resolve them first.'),
        ],
        foot: [MbButton('Review change', onPressed: _review)],
      );
}

/// M3-10
class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({super.key, required this.user});
  final Map<String, dynamic> user;

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  late int _sel = widget.user['status'] == 'active' ? 1 : 0;
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final status = _sel == 0 ? 'active' : 'deactivated';
    if (status == 'deactivated' && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Add a reason. It’s recorded in the activity log.');
      return;
    }
    setState(() => _busy = true);
    try {
      await api.patch('/admin/users/${widget.user['id']}/status', {'status': status, 'reason': _reason.text.trim()});
      if (mounted) replace(context, AccountUpdatedScreen(name: widget.user['name'] as String, change: status == 'active' ? 'Account reactivated' : 'Account deactivated'), root: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Account status',
        subtitle: widget.user['name'] as String,
        children: [
          OptionsList(
            items: const [OptionItem('Active', sub: 'Can sign in and use MindBridge', icon: 'check_circle'), OptionItem('Deactivated', sub: 'Can’t sign in. Active bookings are cancelled.', icon: 'block')],
            selected: _sel,
            onSelect: (i) => setState(() => _sel = i),
          ),
          MbField(label: 'Reason (logged)', controller: _reason, type: FieldType.area, rows: 3, hint: 'e.g. Graduated, duplicate account', error: _error, maxLength: 300),
        ],
        foot: [MbButton('Update account', kind: _sel == 1 ? BtnKind.danger : BtnKind.primary, loading: _busy, onPressed: _save)],
      );
}

/// M3-11
class AccountUpdatedScreen extends StatelessWidget {
  const AccountUpdatedScreen({super.key, required this.name, required this.change});
  final String name;
  final String change;

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: [
          const StateView(icon: 'check_circle', title: 'Account updated', text: 'The change is recorded in the system activity log.'),
          KvCard([('User', name), ('Change', change), ('When', 'Just now')]),
        ],
        foot: [MbButton('Back to users', onPressed: () => Navigator.of(context).pop())],
      );
}

/// M3-26 → M3-31 — role-based access, shown in plain language (NFR1, NFR4).
class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/admin/roles'),
        wrap: (c) => MbPage(title: 'Roles & permissions', children: [c]),
        builder: (context, d, reload) {
          final c = (d['counts'] as Map).cast<String, dynamic>();
          return MbPage(
            title: 'Roles & permissions',
            children: [
              const BannerCard(icon: 'shield', text: 'Role-based access keeps notes and check-ins visible only to the people who need them. Permissions are enforced by the server.'),
              ListCards([
                for (final r in _roleOpts)
                  ListItemData(icon: r.$4, tone: switch (r.$1) { 'counsellor' => Tone.blue, 'doctor' => Tone.lilac, 'admin' => Tone.amber, _ => Tone.green }, title: r.$2, sub: '${c[r.$1]} users · ${_perms[r.$1]!.$1.length + _perms[r.$1]!.$2.length} rules', onTap: () => push(context, RolePermissionsScreen(role: r.$1, label: r.$2))),
              ]),
            ],
          );
        },
      );
}

const _perms = {
  'student': (
    ['Book, reschedule and cancel own appointments', 'Log private mood check-ins and journal', 'Use Bridge and wellness content', 'Choose to share mood trends'],
    ['See other students', 'Read counsellor or doctor notes'],
  ),
  'counsellor': (
    ['Manage own requests and calendar', 'Write encrypted session notes', 'See booking info for own students', 'Publish articles (after review)', 'Refer students to the Medical Centre'],
    ['Read other counsellors’ notes', 'See mood data unless shared'],
  ),
  'doctor': (
    ['Receive and respond to referrals', 'See information the counsellor shared', 'Write medical notes'],
    ['Read full counselling notes', 'See mood check-ins, journals or AI chats'],
  ),
  'admin': (
    ['Manage users and roles', 'Verify counsellors and doctors', 'Moderate articles', 'View anonymized reports'],
    ['Read session or medical notes', 'Read check-ins, journals or AI chats', 'Identify students in reports'],
  ),
};

class RolePermissionsScreen extends StatelessWidget {
  const RolePermissionsScreen({super.key, required this.role, required this.label});
  final String role;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = _perms[role]!;
    return MbPage(
      title: '$label role',
      children: [
        ChecksCard(title: 'Can', [for (final x in p.$1) (true, x)]),
        ChecksCard(title: 'Cannot', [for (final x in p.$2) (false, x)]),
        MenuCard([MenuItemData('info', 'How sensitive data is protected', onTap: () => push(context, const PermissionDetailScreen()))]),
      ],
    );
  }
}

/// M3-31
class PermissionDetailScreen extends StatelessWidget {
  const PermissionDetailScreen({super.key});

  @override
  Widget build(BuildContext context) => const MbPage(
        title: 'View session notes',
        subtitle: 'Permission',
        children: [
          Txt('Session notes are written by a counsellor during or after a session. They hold the most sensitive information in MindBridge.'),
          KvCard([('Who can view', 'Authoring counsellor only'), ('Encryption', 'AES-256 at rest, HTTPS in transit'), ('Audit', 'Access to records is logged')]),
          ToggleTile(title: 'Allow admins to view', sub: 'Locked by privacy policy', value: false, locked: true),
          BannerCard(tone: Tone.amber, icon: 'lock', text: 'This permission can’t be changed from the app.'),
        ],
      );
}
