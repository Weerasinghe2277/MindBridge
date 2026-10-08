import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/quick_unlock.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../auth/forgot_password.dart';

/// M1-32 / M2-47 / M3-54 — change password (signs out other devices).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _cur = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final Map<String, String> _err = {};
  bool _busy = false;

  @override
  void dispose() {
    _cur.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _err.clear();
    if (_cur.text.isEmpty) _err['current'] = 'Enter your current password';
    if (!PasswordRules.valid(_next.text)) _err['next'] = 'Use 8+ characters with a number';
    if (_next.text != _confirm.text) _err['confirm'] = 'Passwords don’t match';
    setState(() {});
    if (_err.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await api.post('/me/password', {'current': _cur.text, 'next': _next.text});
      if (!mounted) return;
      // The server turns quick unlock off everywhere; set it up again for this phone if it was on.
      try {
        await context.read<AuthState>().renewQuickUnlock();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'Password updated. Other devices have been signed out.');
    } on ApiException catch (e) {
      setState(() => _err[e.field ?? 'current'] = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Change password',
        bg: PageBg.white,
        children: [
          MbField(label: 'Current password', controller: _cur, type: FieldType.password, error: _err['current'], autofill: const [AutofillHints.password]),
          MbField(label: 'New password', controller: _next, type: FieldType.password, error: _err['next'], onChanged: (_) => setState(() {}), autofill: const [AutofillHints.newPassword]),
          MbField(label: 'Confirm new password', controller: _confirm, type: FieldType.password, error: _err['confirm']),
          PasswordRules(_next.text),
        ],
        foot: [MbButton('Update password', loading: _busy, onPressed: _save)],
      );
}

/// Signed-in devices for this account, with sign-out per device (NFR4).
class ActiveSessionsCard extends StatefulWidget {
  const ActiveSessionsCard({super.key});

  @override
  State<ActiveSessionsCard> createState() => _ActiveSessionsCardState();
}

class _ActiveSessionsCardState extends State<ActiveSessionsCard> {
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/me/sessions');
      if (mounted) setState(() => _list = (r['sessions'] as List).cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _list = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_list == null) return const LoadingList(n: 2);
    return ListCards([
      for (final s in _list!)
        ListItemData(
          icon: (s['device'] as String? ?? '').contains('Web') ? 'laptop_mac' : 'smartphone',
          tone: Tone.grey,
          title: s['device'] as String? ?? 'Device',
          sub: s['current'] == true ? 'This device' : 'Last active ${Fmt.ago(s['lastSeenAt'])}',
          badge: s['current'] == true ? 'Now' : null,
          trailing: s['current'] == true
              ? null
              : TextLink('Sign out', color: C.dangerText, onTap: () async {
                  await guard(context, () => api.delete('/me/sessions/${s['id']}'));
                  _load();
                }),
        ),
    ]);
  }
}

Future<void> confirmSignOut(BuildContext context) async {
  final auth = context.read<AuthState>();
  await showMbSheet(context, icon: 'logout', tone: Tone.grey, title: 'Sign out of MindBridge?', text: 'You’ll need your password to sign in again.', actions: [
    SheetAction('Sign out', kind: BtnKind.danger, run: (_) async {
      await auth.logout();
      return true;
    }),
    const SheetAction('Cancel', kind: BtnKind.ghost),
  ]);
}

/// Quick unlock switch for this phone: sign in again with fingerprint, face, pattern or PIN.
class QuickUnlockTile extends StatefulWidget {
  const QuickUnlockTile({super.key});

  @override
  State<QuickUnlockTile> createState() => _QuickUnlockTileState();
}

class _QuickUnlockTileState extends State<QuickUnlockTile> {
  late final Future<bool> _available = QuickUnlock.isAvailable();
  bool _busy = false;

  Future<void> _set(bool on) async {
    if (_busy) return;
    final auth = context.read<AuthState>();
    setState(() => _busy = true);
    try {
      if (on) {
        if (await auth.enableQuickUnlock() && mounted) toast(context, 'Quick unlock is on for this phone.');
      } else {
        await auth.disableQuickUnlock();
        if (mounted) toast(context, 'Quick unlock is off. Sign in with your password next time.');
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = context.watch<AuthState>().quickUnlockForMe;
    return FutureBuilder<bool>(
      future: _available,
      builder: (context, snap) {
        final available = snap.data ?? false;
        return ToggleTile(
          title: 'Quick unlock',
          sub: available
              ? 'Sign in with your fingerprint, face, pattern or PIN on this phone instead of your password. After inactivity the app locks instead of signing you out.'
              : 'Set a screen lock (fingerprint, face, pattern or PIN) on this phone to use quick unlock',
          value: on,
          locked: !available && !on,
          onChanged: _busy ? null : _set,
        );
      },
    );
  }
}
