import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    // Music playing counts as activity — the student is using the app.
    if (context.read<PlayerState>().playing) {
      _last = DateTime.now();
      return;
    }
    final minutes = auth.autoSignOutMinutes;
    if (DateTime.now().difference(_last).inMinutes >= minutes) auth.expireForInactivity(minutes);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _last = DateTime.now(),
        child: widget.child,
      );
}
