import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../student/counsellors.dart';
import 'bridge.dart';

/// Confirms, logs (anonymously) and opens the phone dialler (M4-43 / M4-44).
Future<void> callHelpline(BuildContext context, {String number = AppConfig.helplineNumber}) async {
  final is1926 = number == AppConfig.helplineNumber;
  await showMbSheet(
    context,
    icon: 'call',
    tone: Tone.red,
    title: 'Call $number${is1926 ? ' now' : ''}?',
    text: is1926
        ? 'National Mental Health Helpline. Free and confidential, 24 hours. Your phone will open the dialler.'
        : 'Child & Women Helpline, run by the National Child Protection Authority. Free and confidential.',
    actions: [
      SheetAction('Call $number', kind: BtnKind.danger, run: (_) async {
        api.post('/wellness/events', {'kind': 'helpline_tap', 'detail': number}).catchError((_) => <String, dynamic>{});
        final ok = await launchUrl(Uri(scheme: 'tel', path: number));
        if (!ok && context.mounted) toast(context, 'Couldn’t open the dialler. Please dial $number on your phone.');
        return true;
      }),
      const SheetAction('Cancel', kind: BtnKind.ghost),
    ],
  );
}

/// M4-40 / M4-41 — press and hold for 5 seconds, so a pocket tap can't start a call (FR8).
class EmergencyHoldScreen extends StatefulWidget {
  const EmergencyHoldScreen({super.key});

  @override
  State<EmergencyHoldScreen> createState() => _EmergencyHoldScreenState();
}

class _EmergencyHoldScreenState extends State<EmergencyHoldScreen> {
  double _p = 0; // 0..1
  Timer? _timer;

  void _down() {
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      setState(() => _p = (_p + 0.02).clamp(0, 1));
      if (_p >= 1) {
        t.cancel();
        HapticFeedback.heavyImpact();
        replace(context, const SupportOptionsScreen(), root: true);
      }
    });
  }

  void _up() {
    if (_p >= 1) return;
    _timer?.cancel();
    setState(() => _p = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = (5 - _p * 5).ceil();
    return MbPage(
      title: 'Emergency support',
      bg: PageBg.alert,
      children: [
        const Txt('If you’re in danger or thinking about harming yourself, get help now.', size: TxtSize.lg, align: TextAlign.center),
        Center(
          child: Semantics(
            button: true,
            label: 'Hold for help. Press and hold for 5 seconds.',
            onLongPress: () => replace(context, const SupportOptionsScreen(), root: true),
            child: Listener(
              onPointerDown: (_) => _down(),
              onPointerUp: (_) => _up(),
              onPointerCancel: (_) => _up(),
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: _p, strokeWidth: 18, color: C.danger, backgroundColor: const Color(0xFFF3D9D2))),
                  Container(
                    width: 204,
                    height: 204,
                    decoration: const BoxDecoration(color: C.danger, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x99C2382E), blurRadius: 40, offset: Offset(0, 16), spreadRadius: -10)]),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const MbIcon('sos', size: 46, color: Colors.white),
                      const SizedBox(height: 6),
                      Text('Hold for help', style: Ty.nunito(size: 15, weight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Center(child: Text(_p > 0 ? 'Keep holding… ${secs}s' : 'Press and hold for 5 seconds', style: Ty.nunito(size: 15, weight: FontWeight.w700, color: const Color(0xFFA52B22)))),
        const Txt('Holding prevents accidental calls. Let go to cancel.', size: TxtSize.sm, align: TextAlign.center),
        LinksRow([
          ('Talk to Bridge', () => replace(context, const BridgeChatScreen(), root: true)),
          ('Book a counsellor', () => replace(context, const CounsellorListScreen(), root: true)),
        ], lead: 'Not urgent?'),
        Center(child: TextLink('Skip to helplines', color: C.dangerText, onTap: () => replace(context, const SupportOptionsScreen(), root: true))),
      ],
    );
  }
}

/// M4-42
class SupportOptionsScreen extends StatelessWidget {
  const SupportOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Choose support',
        bg: PageBg.alert,
        children: [
          HeroCard(
            style: HeroStyle.alert,
            eyebrow: 'Recommended',
            title: '1926 · Mental Health Helpline',
            sub: 'National Institute of Mental Health · 24/7 · free',
            actions: [MbButton('Call 1926', kind: BtnKind.danger, icon: 'call', onPressed: () => callHelpline(context))],
          ),
          ListCards([
            ListItemData(icon: 'call', tone: Tone.red, title: '1929 · Child & Women Helpline', sub: 'For under-18s and women facing abuse', onTap: () => callHelpline(context, number: AppConfig.childWomenHelpline)),
            const ListItemData(icon: 'local_hospital', tone: Tone.red, title: 'University Medical Centre', sub: 'Mon–Fri · 8:00 AM – 4:30 PM'),
            ListItemData(icon: 'info', tone: Tone.grey, title: 'What happens when I call?', onTap: () => push(context, const EmergencyInfoScreen(), root: true)),
          ]),
        ],
        foot: [MbButton('I’m safe, cancel', kind: BtnKind.ghost, onPressed: () => replace(context, const EmergencyCancelledScreen(), root: true))],
      );
}

/// M4-45
class EmergencyInfoScreen extends StatelessWidget {
  const EmergencyInfoScreen({super.key});

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'About emergency support',
        children: [
          const Txt('Trained people answer these lines. You don’t need to explain everything, just say you need support.'),
          const KvCard([('1926', 'Mental health helpline · 24/7'), ('1929', 'Child & women helpline'), ('1990', 'Suwa Seriya ambulance'), ('119', 'Police emergency')], title: 'Helplines'),
          const BannerCard(icon: 'lock', title: 'You stay in control', text: 'MindBridge never alerts anyone automatically, including your university or family.'),
        ],
        foot: [MbButton('Call 1926', kind: BtnKind.danger, icon: 'call', onPressed: () => callHelpline(context))],
      );
}

/// M4-46
class EmergencyCancelledScreen extends StatelessWidget {
  const EmergencyCancelledScreen({super.key});

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: const [StateView(icon: 'verified_user', title: 'Okay, nothing was dialled', text: 'If you’d like to talk, support is still here whenever you need it.')],
        foot: [
          MbButton('Talk to Bridge', onPressed: () => replace(context, const BridgeChatScreen(), root: true)),
          MbButton('Book a counsellor', kind: BtnKind.secondary, onPressed: () => replace(context, const CounsellorListScreen(), root: true)),
          MbButton('Back to home', kind: BtnKind.ghost, onPressed: () => popToFirst(context, root: true)),
        ],
      );
}
