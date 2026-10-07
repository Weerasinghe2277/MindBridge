import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'code_verify.dart';

/// M1-03 — request a reset code.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final e = _email.text.trim();
    if (!e.contains('@')) {
      setState(() => _error = 'Enter your university email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await api.post('/auth/forgot', {'email': e});
      if (mounted) replace(context, CodeVerifyScreen(purpose: CodePurpose.resetPassword, email: e, devOtp: r['devOtp'] as String?), root: true);
    } on ApiException catch (x) {
      setState(() => _error = x.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Reset password',
        bg: PageBg.white,
        children: [
          const StateView(icon: 'lock_reset', title: 'Forgot your password?', text: 'Enter your university email and we’ll send a 6-digit reset code.', padding: EdgeInsets.fromLTRB(8, 10, 8, 6)),
          MbField(label: 'University email', controller: _email, icon: 'mail', type: FieldType.email, error: _error, textInputAction: TextInputAction.done, onSubmitted: (_) => _send()),
        ],
        foot: [MbButton('Send reset code', loading: _busy, onPressed: _send)],
      );
}

/// Password rules shown live (M1-32): 8+ characters, a number, a symbol recommended.
class PasswordRules extends StatelessWidget {
  const PasswordRules(this.value, {super.key});
  final String value;

  static bool valid(String v) => v.length >= 8 && RegExp(r'\d').hasMatch(v);

  @override
  Widget build(BuildContext context) => ChecksCard([
        (value.length >= 8, 'At least 8 characters'),
        (RegExp(r'\d').hasMatch(value), 'Contains a number'),
        (RegExp(r'[^A-Za-z0-9]').hasMatch(value), 'Contains a symbol (recommended)'),
      ]);
}

class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key, required this.email, required this.code});
  final String email;
  final String code;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!PasswordRules.valid(_pw.text)) {
      setState(() => _error = 'Use 8+ characters with a number');
      return;
    }
    if (_pw.text != _confirm.text) {
      setState(() => _error = 'Passwords don’t match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.post('/auth/reset', {'email': widget.email, 'code': widget.code, 'password': _pw.text});
      if (!mounted) return;
      popToFirst(context, root: true);
      toast(context, 'Password updated. Sign in with your new password.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'New password',
        bg: PageBg.white,
        children: [
          MbField(label: 'New password', controller: _pw, type: FieldType.password, onChanged: (_) => setState(() {}), autofill: const [AutofillHints.newPassword]),
          MbField(label: 'Confirm new password', controller: _confirm, type: FieldType.password, error: _error),
          PasswordRules(_pw.text),
          const BannerCard(tone: Tone.blue, icon: 'devices', text: 'For your security, you’ll be signed out on all other devices.'),
        ],
        foot: [MbButton('Update password', loading: _busy, onPressed: _save)],
      );
}
