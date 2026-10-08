import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'features/admin/admin_shell.dart';
import 'features/auth/login.dart';
import 'features/auth/onboarding.dart';
import 'features/counsellor/counsellor_shell.dart';
import 'features/doctor/doctor_shell.dart';
import 'features/student/student_shell.dart';
import 'modules/counsellor_approval/staff_status.dart';
import 'state/auth.dart';
import 'state/notifications.dart';
import 'state/player.dart';
import 'widgets/page.dart';
import 'widgets/ui.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class MindBridgeApp extends StatelessWidget {
  const MindBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState()..init()),
        ChangeNotifierProvider(create: (_) => NotificationsState()),
        ChangeNotifierProvider(create: (_) => PlayerState()),
      ],
      child: MaterialApp(
        title: 'MindBridge',
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigatorKey,
        theme: buildTheme(),
        builder: (context, child) => _InactivityGuard(child: child ?? const SizedBox()),
        home: const RootGate(),
      ),
    );
  }
}

/// Chooses the experience for the signed-in role and resets navigation whenever
/// the session changes (sign in, sign out, automatic sign-out).
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  AuthStatus? _last;
  String? _lastUserId;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final userId = auth.user?['id'] as String?;
    if (auth.offerQuickUnlock && auth.status == AuthStatus.signedIn) {
      auth.offerQuickUnlock = false;
      // After the navigation reset below, so the sheet isn't popped straight away.
      WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.addPostFrameCallback((_) => _offerQuickUnlock()));
    }
    if (_last != auth.status || _lastUserId != userId) {
      final wasSignedIn = _last == AuthStatus.signedIn;
      _last = auth.status;
      _lastUserId = userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
        final notes = context.read<NotificationsState>();
        if (auth.status == AuthStatus.signedIn) {
          notes.start();
        } else {
          notes.stop();
          if (wasSignedIn) context.read<PlayerState>().stop();
        }
      });
    }

    return _screenFor(auth);
  }

  /// Asked once per phone, after the first password sign-in.
  Future<void> _offerQuickUnlock() async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final auth = ctx.read<AuthState>();
    await showMbSheet(
      ctx,
      icon: 'fingerprint',
      title: 'Sign in faster next time?',
      text: 'Turn on quick unlock to open MindBridge with your fingerprint, face, pattern or PIN instead of typing your password. You can change this any time in Privacy & security.',
      actions: [
        SheetAction('Turn on quick unlock', run: (_) async {
          if (await auth.enableQuickUnlock() && ctx.mounted) toast(ctx, 'Quick unlock is on for this phone.');
          return true;
        }),
        const SheetAction('Not now', kind: BtnKind.ghost),
      ],
    );
  }

  Widget _screenFor(AuthState auth) {
    switch (auth.status) {
      case AuthStatus.unknown:
        return const _Splash();
      case AuthStatus.signedOut:
        return auth.onboardingSeen ? const LoginScreen() : const OnboardingScreen();
      case AuthStatus.signedIn:
        if (auth.user == null) return const _Splash();
        if (auth.isStaff && !auth.isVerifiedStaff) return const StaffStatusScreen();
        return switch (auth.role) {
          'student' => const StudentShell(),
          'counsellor' => const CounsellorShell(),
          'doctor' => const DoctorShell(),
          'admin' => const AdminShell(),
          _ => const LoginScreen(),
        };
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MindBridgeMark(size: 76),
            const SizedBox(height: 16),
            Text('MindBridge', style: Ty.lora(size: 26)),
            const SizedBox(height: 18),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.primary)),
          ]),
        ),
      );
}

/// Mirrors the server's 15-minute inactivity sign-out on the device (NFR4),
/// so a phone left unlocked doesn't keep showing private information.
class _InactivityGuard extends StatefulWidget {
  const _InactivityGuard({required this.child});
  final Widget child;

  @override
  State<_InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<_InactivityGuard> with WidgetsBindingObserver {
  DateTime _last = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() {
    final auth = context.read<AuthState>();
    if (auth.status != AuthStatus.signedIn) return;
    // While locked the clock waits, so it starts fresh after unlocking.
    if (auth.locked) {
      _last = DateTime.now();
      return;
    }
    // Music playing counts as activity — the student is using the app.
    if (context.read<PlayerState>().playing) {
      _last = DateTime.now();
      return;
    }
    final minutes = auth.autoSignOutMinutes;
    if (DateTime.now().difference(_last).inMinutes >= minutes) auth.expireForInactivity(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.select<AuthState, bool>((a) => a.locked && a.status == AuthStatus.signedIn);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _last = DateTime.now(),
      child: Stack(children: [
        // The app stays underneath so the user keeps their place, hidden from touch and screen readers.
        Positioned.fill(child: ExcludeSemantics(excluding: locked, child: IgnorePointer(ignoring: locked, child: widget.child))),
        if (locked) const Positioned.fill(child: _LockScreen()),
      ]),
    );
  }
}

/// Covers the app after inactivity for quick-unlock users (NFR4): nothing is readable until they
/// confirm with fingerprint, face, pattern or PIN.
class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().unlock();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Material(
      color: C.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(children: [
            const Spacer(),
            const MindBridgeMark(size: 76),
            const SizedBox(height: 22),
            Text('MindBridge is locked', style: Ty.xl, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              'For your privacy, MindBridge locks after ${auth.autoSignOutMinutes} minutes of inactivity. Unlock with your fingerprint, face, pattern or PIN to carry on where you left off.',
              style: Ty.nunito(size: 14.5, color: C.body, height: 1.45),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[const SizedBox(height: 16), BannerCard(tone: Tone.red, icon: 'error', text: _error)],
            const Spacer(),
            MbButton(auth.firstName.isEmpty ? 'Unlock' : 'Unlock as ${auth.firstName}', icon: 'fingerprint', loading: _busy, onPressed: _unlock),
            const SizedBox(height: 8),
            MbButton('Sign out', kind: BtnKind.ghost, onPressed: _busy ? null : () => auth.logout()),
          ]),
        ),
      ),
    );
  }
}
