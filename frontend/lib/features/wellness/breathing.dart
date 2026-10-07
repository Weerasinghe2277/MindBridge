import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

class BreathPhase {
  const BreathPhase(this.label, this.seconds, this.scale);
  final String label;
  final int seconds;
  final double scale;
}

enum BreathPattern {
  box('Box breathing', '4 · 4 · 4', 120, [BreathPhase('Breathe in', 4, 1), BreathPhase('Hold', 4, 1), BreathPhase('Breathe out', 4, .7)]),
  sleep('4-7-8 for sleep', '4 · 7 · 8', 180, [BreathPhase('Breathe in', 4, 1), BreathPhase('Hold', 7, 1), BreathPhase('Breathe out', 8, .7)]),
  quick('Quick reset', '3 · 3', 60, [BreathPhase('Breathe in', 3, 1), BreathPhase('Breathe out', 3, .7)]),
  bubble('Breathing bubble', 'Follow the bubble', 120, [BreathPhase('Breathe in', 4, 1), BreathPhase('Breathe out', 4, .7)]);

  const BreathPattern(this.title, this.rhythm, this.seconds, this.phases);
  final String title;
  final String rhythm;
  final int seconds;
  final List<BreathPhase> phases;

  int get cycle => phases.fold(0, (a, p) => a + p.seconds);
}

/// M4-34
class BreathingHomeScreen extends StatelessWidget {
  const BreathingHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/wellness/stats'),
        wrap: (c) => MbPage(title: 'Guided breathing', children: [c]),
        builder: (context, s, reload) {
          Future<void> go(BreathPattern p) async {
            await push(context, BreathingExerciseScreen(pattern: p), root: true);
            reload();
          }

          return MbPage(
            title: 'Guided breathing',
            onRefresh: reload,
            children: [
              StatsGrid([StatItem('${s['breathingSessions']}', 'Sessions this week'), StatItem('${s['breathingMinutes']} min', 'Total time')]),
              ListCards([
                ListItemData(icon: 'crop_square', title: 'Box breathing', sub: '4 · 4 · 4 · 2 min · calms exam nerves', onTap: () => go(BreathPattern.box)),
                ListItemData(icon: 'bedtime', tone: Tone.lilac, title: '4-7-8 for sleep', sub: '3 min · slows your heart rate', onTap: () => go(BreathPattern.sleep)),
                ListItemData(icon: 'bolt', tone: Tone.amber, title: 'Quick reset', sub: '1 min · between lectures', onTap: () => go(BreathPattern.quick)),
              ]),
              const BannerCard(tone: Tone.blue, icon: 'info', text: 'If you feel light-headed, stop and breathe normally. Breathing exercises support you but don’t replace professional help.'),
            ],
          );
        },
      );
}

/// M4-35 / M4-27 — animated breathing guide.
class BreathingExerciseScreen extends StatefulWidget {
  const BreathingExerciseScreen({super.key, required this.pattern, this.fromGame = false});
  final BreathPattern pattern;
  final bool fromGame;

  @override
  State<BreathingExerciseScreen> createState() => _BreathingExerciseScreenState();
}

class _BreathingExerciseScreenState extends State<BreathingExerciseScreen> {
  int _t = 0;
  Timer? _timer;
  bool _paused = false;

  BreathPattern get p => widget.pattern;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      setState(() => _t++);
      if (_phaseStart()) HapticFeedback.selectionClick();
      if (_t >= p.seconds) _finish();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  (BreathPhase, int) get _phase {
    var r = _t % p.cycle;
    for (final ph in p.phases) {
      if (r < ph.seconds) return (ph, ph.seconds - r);
      r -= ph.seconds;
    }
    return (p.phases.first, p.phases.first.seconds);
  }

  bool _phaseStart() {
    var r = _t % p.cycle;
    for (final ph in p.phases) {
      if (r == 0) return true;
      r -= ph.seconds;
      if (r < 0) return false;
    }
    return false;
  }

  void _finish() {
    _timer?.cancel();
    final secs = _t;
    if (secs >= 15) api.post('/wellness/events', {'kind': widget.fromGame ? 'game' : 'breathing', 'detail': p.name, 'durationSec': secs}).catchError((_) => <String, dynamic>{});
    if (widget.fromGame) {
      replace(context, const GameCompleteScreen(), root: true);
    } else {
      replace(context, BreathingCompleteScreen(pattern: p, seconds: secs), root: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (ph, left) = _phase;
    final round = _t ~/ p.cycle + 1;
    return MbPage(
      title: p.title,
      bg: PageBg.calm,
      actions: [HeaderAction(_paused ? 'play_arrow' : 'pause', tooltip: _paused ? 'Resume' : 'Pause', onTap: () => setState(() => _paused = !_paused))],
      children: [
        const SizedBox(height: 8),
        Center(
          child: Semantics(
            liveRegion: true,
            label: '${ph.label}, $left',
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFFD6E3C8), Color(0xFFD6E3C8), Color(0xFFE6EEDA)], stops: [0, .4, .41])),
              alignment: Alignment.center,
              child: AnimatedScale(
                scale: _paused ? .85 : ph.scale,
                duration: Duration(seconds: ph.seconds),
                curve: Curves.easeInOut,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: const BoxDecoration(color: C.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x731D5A40), blurRadius: 40, offset: Offset(0, 20), spreadRadius: -10)]),
                  alignment: Alignment.center,
                  child: Text(_paused ? '‖' : '$left', style: Ty.nunito(size: 44, weight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text(_paused ? 'Paused' : ph.label, style: Ty.lora(size: 26))),
        Center(child: Text('Round $round · ${p.rhythm} · ${Fmt.mmss((p.seconds - _t).clamp(0, p.seconds))} left', style: Ty.nunito(size: 14, color: C.muted))),
        if (p == BreathPattern.bubble) const Txt('Breathe in as the bubble grows, out as it shrinks.', size: TxtSize.sm, align: TextAlign.center),
      ],
      foot: [MbButton(widget.fromGame ? 'Finish' : 'End session', kind: widget.fromGame ? BtnKind.primary : BtnKind.secondary, onPressed: _finish)],
    );
  }
}

/// M4-36
class BreathingCompleteScreen extends StatelessWidget {
  const BreathingCompleteScreen({super.key, required this.pattern, required this.seconds});
  final BreathPattern pattern;
  final int seconds;

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: [
          StateView(icon: 'spa', title: 'Session complete', text: '${seconds >= 60 ? '${seconds ~/ 60} minute${seconds >= 120 ? 's' : ''}' : '$seconds seconds'} of steady breathing. Notice how your shoulders feel now.'),
          StatsGrid([StatItem(Fmt.mmss(seconds), 'Duration'), StatItem('${(seconds / pattern.cycle).floor()}', 'Breaths')]),
        ],
        foot: [
          MbButton('Done', onPressed: () => Navigator.of(context).pop()),
          MbButton('Breathe again', kind: BtnKind.secondary, onPressed: () => replace(context, BreathingExerciseScreen(pattern: pattern), root: true)),
        ],
      );
}

/// M4-30 — shared completion page for the calming games.
class GameCompleteScreen extends StatefulWidget {
  const GameCompleteScreen({super.key});

  @override
  State<GameCompleteScreen> createState() => _GameCompleteScreenState();
}

class _GameCompleteScreenState extends State<GameCompleteScreen> {
  int? _mood;
  bool _saved = false;

  Future<void> _pick(int m) async {
    setState(() => _mood = m);
    final r = await guard(context, () => api.post('/mood', {'mood': m, 'factors': <String>[], 'source': 'game'}));
    if (r != null && mounted) setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) => MbPage(
        bg: PageBg.white,
        children: [
          const StateView(icon: 'emoji_events', title: 'Nicely done', text: 'You gave yourself a few minutes. How do you feel now?'),
          MoodPicker(selected: _mood, onSelect: _pick),
          if (_saved) const Txt('Saved to your private mood history.', size: TxtSize.sm, align: TextAlign.center),
        ],
        foot: [
          MbButton('Play another', onPressed: () => Navigator.of(context).pop()),
          MbButton('Back to wellness', kind: BtnKind.secondary, onPressed: () => popToFirst(context, root: true)),
        ],
      );
}
