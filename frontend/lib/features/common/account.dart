import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/quick_unlock.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../widgets/image_adjust.dart';
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

// ─────────────────────────── Profile photo (counsellors and doctors) ───────────────────────────

/// Upload, adjust or remove the signed-in staff member's profile photo.
Future<void> changeProfilePhoto(BuildContext context) async {
  final auth = context.read<AuthState>();
  final current = auth.user?['photoUrl'] as String?;
  final who = auth.role == 'doctor' ? 'Students and counsellors see it on referrals and consultations.' : 'Students see it when they choose a counsellor and on your articles.';
  final choice = await showMbSheet(
    context,
    icon: 'photo_camera',
    title: 'Profile photo',
    text: '$who Use a clear, friendly photo of your face.',
    actions: [
      const SheetAction('Upload a new photo', value: 'upload'),
      if (current != null) const SheetAction('Adjust current photo', kind: BtnKind.secondary, value: 'adjust'),
      if (current != null) const SheetAction('Remove photo', kind: BtnKind.dangerSoft, value: 'remove'),
      const SheetAction('Cancel', kind: BtnKind.ghost, value: 'cancel'),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'upload':
      final bytes = await pickImageBytes(context);
      if (bytes != null && context.mounted) await _adjustAndUpload(context, bytes);
    case 'adjust':
      final bytes = await _withProgress(context, 'Opening your photo…', () => downloadImage(current!));
      if (!context.mounted) return;
      if (bytes == null) return toast(context, 'Couldn’t open your current photo. Check your connection.');
      await _adjustAndUpload(context, bytes);
    case 'remove':
      final r = await guard(context, () => api.delete('/me/photo'));
      if (r != null && context.mounted) {
        auth.setUser(r['user'] as Map<String, dynamic>);
        toast(context, 'Photo removed. Your initials are shown instead.');
      }
  }
}

Future<void> _adjustAndUpload(BuildContext context, Uint8List bytes) async {
  final auth = context.read<AuthState>();
  final edited = await adjustImage(context, bytes: bytes, shape: CropShape.circle, title: 'Adjust profile photo');
  if (edited == null || !context.mounted) return;
  final r = await _withProgress(context, 'Saving your photo…', () => guard(context, () => api.upload('/me/photo', bytes: edited, filename: 'profile.png', method: 'PUT')));
  if (r != null && context.mounted) {
    auth.setUser(r['user'] as Map<String, dynamic>);
    toast(context, 'Profile photo updated.');
  }
}

/// Runs [work] behind a small "please wait" dialog.
Future<T?> _withProgress<T>(BuildContext context, String message, Future<T?> Function() work) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 18), Expanded(child: Text(message))])),
    ),
  );
  try {
    return await work();
  } finally {
    nav.pop();
  }
}
