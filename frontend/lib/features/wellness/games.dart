import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'breathing.dart';

void _logGame(String name, int seconds) =>
    api.post('/wellness/events', {'kind': 'game', 'detail': name, 'durationSec': seconds}).catchError((_) => <String, dynamic>{});

/// M4-25
class GamesHomeScreen extends StatelessWidget {
  const GamesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Calming games',
        children: [
          const Txt('Short, gentle activities to give your mind a break. No scores are saved.', size: TxtSize.sm),
          ListCards([
            ListItemData(icon: 'bubble_chart', title: 'Breathing bubble', sub: 'Follow the bubble · 2 min', onTap: () => push(context, const BreathingExerciseScreen(pattern: BreathPattern.bubble, fromGame: true), root: true)),
            ListItemData(icon: 'grid_view', tone: Tone.blue, title: 'Memory match', sub: 'Find the pairs · 2 min', onTap: () => push(context, const MemoryIntroScreen())),
            ListItemData(icon: 'ads_click', tone: Tone.amber, title: 'Focus tap', sub: 'Tap the green tile · 1 min', onTap: () => push(context, const FocusGameScreen(), root: true)),
          ]),
        ],
      );
}

/// M4-26
class MemoryIntroScreen extends StatelessWidget {
  const MemoryIntroScreen({super.key});

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Memory match',
        children: const [
          MediaPlaceholder(height: 200, icon: 'grid_view', tone: Tone.blue),
          Txt('Flip two cards at a time and find all six pairs. There is no timer. Go at whatever pace feels calm.'),
          StatsGrid(cols: 3, [StatItem('~2 min', 'Average'), StatItem('Easy', 'Level'), StatItem('12', 'Cards')]),
        ],
        foot: [MbButton('Start game', onPressed: () => push(context, const MemoryGameScreen(), root: true))],
      );
}

/// M4-28
class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({super.key});

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen> {
  static const _icons = ['spa', 'water_drop', 'eco', 'wb_sunny', 'nightlight', 'favorite'];
  late final List<String> _deck = [..._icons, ..._icons]..shuffle(Random());
  final List<int> _open = [];
  final Set<int> _done = {};
  int _moves = 0;
  final _started = DateTime.now();

  void _flip(int i) {
    if (_open.length >= 2 || _open.contains(i) || _done.contains(i)) return;
    HapticFeedback.selectionClick();
    setState(() => _open.add(i));
    if (_open.length < 2) return;
    _moves++;
    final match = _deck[_open[0]] == _deck[_open[1]];
    Timer(Duration(milliseconds: match ? 350 : 800), () {
      if (!mounted) return;
      setState(() {
        if (match) _done.addAll(_open);
        _open.clear();
      });
      if (_done.length == _deck.length) {
        _logGame('memory', DateTime.now().difference(_started).inSeconds);
        Timer(const Duration(milliseconds: 700), () {
          if (mounted) replace(context, const GameCompleteScreen(), root: true);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Memory match',
        children: [
          Row(children: [
            Text('Pairs ${_done.length ~/ 2} / 6', style: Ty.nunito(size: 14, weight: FontWeight.w700)),
            const Spacer(),
            Text('Moves $_moves', style: Ty.nunito(size: 14, weight: FontWeight.w700, color: C.muted)),
          ]),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3 / 4,
            children: [
              for (var i = 0; i < _deck.length; i++)
                Builder(builder: (_) {
                  final shown = _open.contains(i) || _done.contains(i);
                  final done = _done.contains(i);
                  return Semantics(
                    button: true,
                    label: shown ? _deck[i].replaceAll('_', ' ') : 'Hidden card',
                    child: GestureDetector(
                      onTap: () => _flip(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: done ? C.softGreen : (shown ? Colors.white : C.primary),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: done ? C.barLight : (shown ? const Color(0xFFD8CFBE) : C.primary), width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: MbIcon(shown ? _deck[i] : 'spa', size: 32, color: shown ? C.dark : Colors.white.withValues(alpha: .25)),
                      ),
                    ),
                  );
                }),
            ],
          ),
          const Txt('Tap two cards to flip them.', size: TxtSize.sm, align: TextAlign.center),
        ],
        foot: [MbButton('End game', kind: BtnKind.secondary, onPressed: () => replace(context, const GameCompleteScreen(), root: true))],
      );
}

/// M4-29
class FocusGameScreen extends StatefulWidget {
  const FocusGameScreen({super.key});

  @override
  State<FocusGameScreen> createState() => _FocusGameScreenState();
}

class _FocusGameScreenState extends State<FocusGameScreen> {
  static const goal = 10;
  final _rng = Random();
  late int _cell = _rng.nextInt(16);
  int _score = 0;
  final _started = DateTime.now();

  void _hit(int i) {
    if (i != _cell) return;
    HapticFeedback.lightImpact();
    int n;
    do {
      n = _rng.nextInt(16);
    } while (n == _cell);
    setState(() {
      _score++;
      _cell = n;
    });
    if (_score >= goal) {
      _logGame('focus', DateTime.now().difference(_started).inSeconds);
      Timer(const Duration(milliseconds: 300), () {
        if (mounted) replace(context, const GameCompleteScreen(), root: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Focus tap',
        children: [
          Row(children: [
            Text('Score $_score / $goal', style: Ty.nunito(size: 14, weight: FontWeight.w700)),
            const Spacer(),
            Text('Tap the green tile', style: Ty.nunito(size: 14, weight: FontWeight.w700, color: C.muted)),
          ]),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: _score / goal, minHeight: 6, backgroundColor: const Color(0xFFE8E1D3), color: C.primary),
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (var i = 0; i < 16; i++)
                Semantics(
                  button: true,
                  label: i == _cell ? 'Green tile' : 'Tile',
                  child: GestureDetector(
                    onTap: () => _hit(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: i == _cell ? C.primary : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: i == _cell ? C.primary : const Color(0xFFE8E1D3), width: 1.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        foot: [MbButton('End game', kind: BtnKind.secondary, onPressed: () => replace(context, const GameCompleteScreen(), root: true))],
      );
}
