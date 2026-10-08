import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../modules/user/register.dart';
import '../../state/auth.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'code_verify.dart';
import 'forgot_password.dart';

/// One secure login for every role (M1-01, M2-01, X-08, M3-01). Staff links
/// switch the header copy; the account's role decides where the user lands.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.staff});
  final String? staff; // counsellor | doctor | admin

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _busy = false;
  bool _unlocking = false;

  /// The fingerprint / face prompt opens by itself once per app launch.
  static bool _autoPrompted = false;

  static const _demo = {
    null: 'it23714052@my.sliit.lk',
    'counsellor': 'hasini.k@sliit.lk',
    'doctor': 'ruwan.d@sliit.lk',
    'admin': 'mindbrige.support@gmail.com',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_showExpired()) _autoUnlock();
    });
  }

  void _autoUnlock() {
    if (_autoPrompted || widget.staff != null || !context.read<AuthState>().quickUnlockOn) return;
    _autoPrompted = true;
    _unlock();
  }

  Future<void> _unlock() async {
    if (_unlocking) return;
    setState(() {
      _unlocking = true;
      _formError = null;
    });
    try {
      await context.read<AuthState>().unlockWithDevice();
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  /// Shows the "you've been signed out" sheet if there is one; returns whether it did.
  bool _showExpired() {
    final auth = context.read<AuthState>();
    final msg = auth.expiredMessage;
    if (msg == null || widget.staff != null) return false;
    auth.expiredMessage = null;
    showMbSheet(context, icon: 'lock_clock', tone: Tone.amber, title: 'You’ve been signed out', text: msg, actions: const [SheetAction('Sign in again')]);
    return true;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _emailError = email.isEmpty ? 'Enter your university email' : (!email.contains('@') ? 'Enter a valid email address' : null);
      _passwordError = _password.text.isEmpty ? 'Enter your password' : null;
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) return;
    setState(() => _busy = true);
    try {
      final step = await context.read<AuthState>().login(email, _password.text);
      if (!mounted) return;
      if (step.kind == 'verify') {
        push(context, CodeVerifyScreen(purpose: CodePurpose.verifyEmail, email: step.email, devOtp: step.devOtp), root: true);
      } else if (step.kind == '2fa') {
        push(context, CodeVerifyScreen(purpose: CodePurpose.twoFactor, email: step.email, devOtp: step.devOtp), root: true);
      }
    } on ApiException catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.staff;
    final auth = context.watch<AuthState>();
    final title = staff == null ? 'Welcome back' : (staff == 'admin' ? 'MindBridge Admin' : 'MindBridge Staff');
    final sub = switch (staff) {
      'counsellor' => 'Counsellor sign in',
      'doctor' => 'Medical Centre sign in',
      'admin' => 'Student Affairs',
      _ => 'Sign in with your university account',
    };
    return MbPage(
      title: staff == null ? null : ' ',
      bg: PageBg.white,
      children: [
        LogoBlock(title: title, sub: sub),
        if (auth.quickUnlockOn) ...[
          MbButton(auth.quickUnlockName == null ? 'Quick unlock' : 'Unlock as ${auth.quickUnlockName}', icon: 'fingerprint', loading: _unlocking, onPressed: _unlock),
          Center(child: Text('Use your fingerprint, face, pattern or PIN', style: Ty.nunito(size: 12.5, color: C.muted))),
          const DividerText('or sign in with your password'),
        ],
        AutofillGroup(
          child: Column(children: [
            MbField(label: staff == null ? 'University email' : 'Staff email', controller: _email, icon: 'mail', type: FieldType.email, hint: staff == null ? 'it12345678@my.sliit.lk' : 'name@sliit.lk', error: _emailError, autofill: const [AutofillHints.email, AutofillHints.username], textInputAction: TextInputAction.next),
            const SizedBox(height: 14),
            MbField(label: 'Password', controller: _password, icon: 'lock', type: FieldType.password, error: _passwordError, autofill: const [AutofillHints.password], textInputAction: TextInputAction.done, onSubmitted: (_) => _submit()),
          ]),
        ),
        Align(alignment: Alignment.centerRight, child: TextLink('Forgot password?', size: 14, onTap: () => push(context, ForgotPasswordScreen(initialEmail: _email.text.trim()), root: true))),
        if (_formError != null) BannerCard(tone: Tone.red, icon: 'error', text: _formError),
        MbButton('Sign in', loading: _busy, onPressed: _submit),
        if (staff == null) ...[
          const DividerText('New to MindBridge?'),
          MbButton('Create an account', kind: BtnKind.secondary, onPressed: () => push(context, const RegisterScreen(), root: true)),
          const BannerCard(icon: 'lock', title: 'Your privacy comes first', text: 'Only your counsellor sees your booking. Mood check-ins stay with you.'),
          LinksRow([
            ('Counsellor', () => push(context, const LoginScreen(staff: 'counsellor'), root: true)),
            ('Doctor', () => push(context, const LoginScreen(staff: 'doctor'), root: true)),
            ('Admin', () => push(context, const LoginScreen(staff: 'admin'), root: true)),
          ], lead: 'Staff:'),
        ] else if (staff == 'counsellor') ...[
          const DividerText('New counsellor?'),
          MbButton('Apply for verification', kind: BtnKind.secondary, onPressed: () => push(context, const RegisterScreen(initialRole: 1), root: true)),
          const BannerCard(icon: 'verified_user', text: 'Counsellor accounts are verified by Student Affairs before students can book you.'),
        ] else if (staff == 'doctor') ...[
          const DividerText('New to the Medical Centre?'),
          MbButton('Apply for verification', kind: BtnKind.secondary, onPressed: () => push(context, const RegisterScreen(initialRole: 2), root: true)),
          const BannerCard(icon: 'verified_user', text: 'Doctor accounts are verified by Student Affairs. You only see information counsellors choose to share.'),
        ] else
          const BannerCard(tone: Tone.blue, icon: 'phonelink_lock', text: 'Two-factor authentication is required for admin accounts.'),
        if (kDebugMode)
          Center(
            child: TextLink('Fill demo account (debug builds only)', size: 12.5, color: C.muted3, onTap: () {
              _email.text = _demo[staff] ?? '';
              _password.text = 'password123';
            }),
          ),
      ],
    );
  }
}
