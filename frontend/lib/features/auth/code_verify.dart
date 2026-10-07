import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'forgot_password.dart';

enum CodePurpose { verifyEmail, twoFactor, resetPassword }

/// 6-digit code entry used for email verification, staff two-factor and password reset (M1-04).
class CodeVerifyScreen extends StatefulWidget {
  const CodeVerifyScreen({super.key, required this.purpose, required this.email, this.devOtp});
  final CodePurpose purpose;
  final String email;
  final String? devOtp;

  @override
  State<CodeVerifyScreen> createState() => _CodeVerifyScreenState();
}

class _CodeVerifyScreenState extends State<CodeVerifyScreen> {
  final _code = TextEditingController();
  String? _error;
  String? _devOtp;
  bool _busy = false;
  int _resendIn = 45;
  Timer? _timer;

  String get _apiPurpose => switch (widget.purpose) {
        CodePurpose.verifyEmail => 'verify_email',
        CodePurpose.twoFactor => 'login_2fa',
        CodePurpose.resetPassword => 'reset_password',
      };

  @override
  void initState() {
    super.initState();
    _devOtp = widget.devOtp;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      if (mounted) setState(() => _resendIn -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  String get _masked {
    final parts = widget.email.split('@');
    final n = parts[0];
    if (n.length <= 5) return widget.email;
    return '${n.substring(0, 4)}•••${n.substring(n.length - 3)}@${parts[1]}';
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    try {
      switch (widget.purpose) {
        case CodePurpose.verifyEmail:
          await auth.verifyEmail(widget.email, _code.text);
        case CodePurpose.twoFactor:
          await auth.verifyTwoFactor(widget.email, _code.text);
        case CodePurpose.resetPassword:
          await api.post('/auth/reset/check', {'email': widget.email, 'code': _code.text});
          if (mounted) replace(context, NewPasswordScreen(email: widget.email, code: _code.text), root: true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      final r = await api.post('/auth/resend', {'email': widget.email, 'purpose': _apiPurpose});
      if (!mounted) return;
      setState(() => _devOtp = r['devOtp'] as String? ?? _devOtp);
      _startTimer();
      toast(context, 'We sent a new code.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.purpose) {
      CodePurpose.verifyEmail => 'Verify your email',
      CodePurpose.twoFactor => 'Two-step sign in',
      CodePurpose.resetPassword => 'Reset password',
    };
    return MbPage(
      title: title,
      bg: PageBg.white,
      children: [
        StateView(
          icon: widget.purpose == CodePurpose.twoFactor ? 'phonelink_lock' : 'mark_email_read',
          title: 'Check your inbox',
          text: 'We sent a 6-digit code to $_masked',
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
        ),
        OtpInput(controller: _code, onCompleted: (_) => _verify()),
        if (_error != null) Center(child: Text(_error!, textAlign: TextAlign.center, style: Ty.nunito(size: 13, weight: FontWeight.w600, color: C.dangerText))),
        LinksRow([(_resendIn > 0 ? 'Resend in 0:${_resendIn.toString().padLeft(2, '0')}' : 'Resend code', _resendIn > 0 ? null : _resend)], lead: 'Didn’t get it?'),
        if (_devOtp != null) BannerCard(tone: Tone.blue, icon: 'developer_mode', title: 'Development mode', text: 'Email isn’t configured on this server, so here is your code: $_devOtp'),
      ],
      foot: [MbButton('Verify and continue', loading: _busy, onPressed: _verify)],
    );
  }
}
