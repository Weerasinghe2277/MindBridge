import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../modules/user/register.dart';
import '../../state/auth.dart';
import '../../widgets/ui.dart';
import 'login.dart';

/// Three short pages: what MindBridge is, how booking works, how privacy is protected (O-01…O-03).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  static const _pages = [
    ('spa', Tone.green, 'Welcome', 'A calmer way to get support', 'MindBridge connects you with your university’s counsellors and gives you simple tools to look after your wellbeing between classes.', <(bool, String)>[]),
    ('event_available', Tone.blue, 'Booking', 'Book in four clear steps', null, [(true, 'Choose a counsellor, date, time and meeting type'), (true, 'See your status at every stage: pending, confirmed, rescheduled'), (true, 'Reschedule or cancel any time, without booking twice')]),
    ('shield_lock', Tone.lilac, 'Privacy', 'Private by default, help when you need it', null, [(true, 'Mood check-ins and journal are visible only to you'), (true, 'Counsellors see your booking, never your check-ins'), (true, 'The 1926 helpline is one tap away on every screen')]),
  ];

  Future<void> _finish(Widget next) async {
    final auth = context.read<AuthState>();
    final nav = Navigator.of(context, rootNavigator: true);
    await auth.markOnboardingSeen();
    // RootGate now shows the login screen underneath; open the chosen next step on top.
    if (next is! LoginScreen) nav.push(MaterialPageRoute(builder: (_) => next));
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: last ? const SizedBox() : Padding(padding: const EdgeInsets.only(right: 18), child: TextLink('Skip', size: 14, onTap: () => _finish(const LoginScreen()))),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final p = _pages[i];
                return ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 18), children: [
                  MediaPlaceholder(height: i == 0 ? 280 : 230, icon: p.$1, tone: p.$2),
                  const SizedBox(height: 18),
                  StepsBar(n: i + 1, of: 3, label: p.$3),
                  const SizedBox(height: 14),
                  Text(p.$4, style: Ty.xl),
                  const SizedBox(height: 14),
                  if (p.$5 != null) Txt(p.$5!),
                  if (p.$6.isNotEmpty) ChecksCard(p.$6),
                ]);
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 14 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
            child: last
                ? ButtonGroup([
                    MbButton('Create an account', onPressed: () => _finish(const RegisterScreen())),
                    MbButton('I already have an account', kind: BtnKind.secondary, onPressed: () => _finish(const LoginScreen())),
                  ])
                : ButtonGroup([
                    MbButton('Next', onPressed: () => _pc.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)),
                    if (_page > 0) MbButton('Back', kind: BtnKind.ghost, onPressed: () => _pc.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)),
                  ]),
          ),
        ]),
      ),
    );
  }
}
