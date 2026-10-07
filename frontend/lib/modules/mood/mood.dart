// MEMBER 3 — Mood Check-in Management: submit mood, view history and insights, delete entry.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../features/student/counsellors.dart';
import '../../features/student/journal.dart';
import '../../features/wellness/breathing.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../article/articles.dart';

const moodFactors = ['Exams', 'Assignments', 'Sleep', 'Friends', 'Family', 'Money', 'Health', 'Nothing specific'];

/// M1-26 — optional, about 30 seconds (FR9, NFR6).
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key, this.initialMood});
  final int? initialMood;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  late int? _mood = widget.initialMood;
  final Set<int> _factors = {};
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_mood == null) {
      toast(context, 'Choose how you’re feeling first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await api.post('/mood', {
        'mood': _mood,
        'factors': [for (final i in _factors) moodFactors[i]],
        'note': _note.text.trim(),
      });
      if (mounted) replace(context, CheckInSavedScreen(result: r), root: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Daily check-in',
        subtitle: 'Optional · about 30 seconds',
        children: [
          const Txt('How are you feeling right now?', size: TxtSize.lg),
          MoodPicker(selected: _mood, onSelect: (m) => setState(() => _mood = m)),
          const SectionHeader('What’s affecting you? (optional)'),
          Chips(
            wrap: true,
            items: moodFactors,
            selected: _factors,
            onTap: (i) => setState(() {
              if (moodFactors[i] == 'Nothing specific') {
                _factors
                  ..clear()
                  ..add(i);
              } else {
                _factors.remove(moodFactors.indexOf('Nothing specific'));
                _factors.contains(i) ? _factors.remove(i) : _factors.add(i);
              }
            }),
          ),
          MbField(label: 'Add a note', controller: _note, type: FieldType.area, rows: 3, hint: 'Only you can see this', maxLength: 1000),
          const BannerCard(icon: 'lock', title: 'Check-ins are private', text: 'Counsellors can’t see these unless you choose to share trends.'),
        ],
        foot: [MbButton('Save check-in', loading: _busy, onPressed: _mood == null ? null : _save)],
      );
}

/// M1-27 — saved, with a gentle next step.
class CheckInSavedScreen extends StatelessWidget {
  const CheckInSavedScreen({super.key, required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final streak = (result['streak'] as num?)?.toInt() ?? 1;
    final s = result['suggestion'] as Map<String, dynamic>?;
    final kind = s?['kind'] as String?;
    return MbPage(
      bg: PageBg.white,
      children: [
        StateView(
          icon: 'favorite',
          title: 'Check-in saved',
          text: streak > 1 ? 'That’s $streak days in a row. Small habits like this help you notice patterns.' : 'Nice start. Small habits like this help you notice patterns over the semester.',
        ),
        if (s != null) ...[
          const SectionHeader('Something that might help'),
          ListCards([
            ListItemData(
              icon: switch (kind) { 'article' => 'bedtime', 'counsellor' => 'person_search', _ => 'air' },
              tone: kind == 'counsellor' ? Tone.green : Tone.lilac,
              title: s['title'] as String,
              sub: s['sub'] as String?,
              onTap: () => replace(
                context,
                switch (kind) {
                  'article' => const ArticleListScreen(initialCategory: 'Sleep'),
                  'counsellor' => const CounsellorListScreen(),
                  _ => const BreathingExerciseScreen(pattern: BreathPattern.box),
                },
                root: true,
              ),
            ),
          ]),
        ],
      ],
      foot: [
        MbButton('View mood history', onPressed: () => replace(context, const MoodHistoryScreen(), root: true)),
        MbButton('Done', kind: BtnKind.secondary, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// M1-28 — week / month bars and recent entries.
class MoodHistoryScreen extends StatefulWidget {
  const MoodHistoryScreen({super.key});

  @override
  State<MoodHistoryScreen> createState() => _MoodHistoryScreenState();
}

class _MoodHistoryScreenState extends State<MoodHistoryScreen> {
  int _seg = 0;

  @override
  Widget build(BuildContext context) {
    final seg = Segmented(items: const ['Week', 'Month'], index: _seg, onChanged: (i) => setState(() => _seg = i));
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_seg),
      load: () => api.get('/mood/history', query: {'range': _seg == 0 ? 'week' : 'month'}),
      wrap: (c) => MbPage(title: 'Mood history', children: [seg, c]),
      builder: (context, d, reload) {
        final bars = (d['bars'] as List).cast<Map<String, dynamic>>();
        final entries = (d['entries'] as List).cast<Map<String, dynamic>>();
        final todayIdx = bars.indexWhere((b) => b['date'] == Fmt.todayStr());
        return MbPage(
          title: 'Mood history',
          onRefresh: reload,
          children: [
            seg,
            BarsChart(
              title: _seg == 0 ? 'This week' : 'Last 4 weeks',
              sub: d['summary'] as String?,
              max: 5,
              highlight: _seg == 0 ? todayIdx : bars.length - 1,
              items: [for (final b in bars) BarDatum(b['label'] as String, (b['value'] as num?)?.toDouble())],
            ),
            const SectionHeader('Recent entries'),
            if (entries.isEmpty)
              const StateView(icon: 'mood', tone: Tone.grey, title: 'No check-ins yet', text: 'Your check-ins will appear here. Only you can see them.', padding: EdgeInsets.fromLTRB(8, 10, 8, 6))
            else
              ListCards([
                for (final e in entries.take(12))
                  ListItemData(
                    icon: moods[e['mood'] as int].$1,
                    tone: (e['mood'] as int) <= 1 ? Tone.amber : Tone.green,
                    title: e['label'] as String,
                    sub: [
                      if ((e['factors'] as List).isNotEmpty) (e['factors'] as List).join(' · '),
                      if ((e['note'] as String).isNotEmpty) '“${e['note']}”',
                    ].join(' — '),
                    meta: Fmt.stamp(e['createdAt']),
                  ),
              ]),
          ],
        );
      },
    );
  }
}

/// X-03 — Mood tab: calendar of check-ins, links to insights and journal.
class MoodTrackerScreen extends StatefulWidget {
  const MoodTrackerScreen({super.key});

  @override
  State<MoodTrackerScreen> createState() => _MoodTrackerScreenState();
}

class _MoodTrackerScreenState extends State<MoodTrackerScreen> {
  late int _y = Fmt.nowSl().year;
  late int _m = Fmt.nowSl().month;

  String get _month => '$_y-${_m.toString().padLeft(2, '0')}';

  void _shift(int d) {
    setState(() {
      _m += d;
      if (_m == 0) {
        _m = 12;
        _y--;
      } else if (_m == 13) {
        _m = 1;
        _y++;
      }
    });
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Future.wait([api.get('/mood/calendar', query: {'month': _month}), api.get('/mood/journal'), api.get('/mood/today')]);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final now = Fmt.nowSl();
    final isCurrent = _y == now.year && _m == now.month;
    return Loader<List<Map<String, dynamic>>>(
      key: ValueKey(_month),
      load: _load,
      wrap: (c) => MbPage(title: 'Mood tracker', root: true, children: [c]),
      builder: (context, r, reload) {
        final days = (r[0]['days'] as Map).cast<String, dynamic>();
        final streak = (r[0]['streak'] as num).toInt();
        final journalCount = (r[1]['total'] as num).toInt();
        final today = r[2]['entry'] as Map<String, dynamic>?;
        final marks = {for (final e in days.entries) int.parse(e.key.substring(8)): moodColor((e.value as num).toInt())};
        Future<void> checkIn() async {
          await push(context, const CheckInScreen(), root: true);
          reload();
        }

        return MbPage(
          title: 'Mood tracker',
          root: true,
          onRefresh: reload,
          children: [
            HeroCard(
              style: HeroStyle.soft,
              eyebrow: 'Today',
              badge: streak > 1 ? '$streak-day streak' : null,
              title: today == null ? 'How are you feeling?' : 'You felt “${moods[today['mood'] as int].$2}” today',
              sub: today == null ? 'A quick check-in helps you spot patterns over the semester.' : 'You can check in again any time your mood changes.',
              actions: [MbButton(today == null ? 'Check in now' : 'Check in again', onPressed: checkIn)],
            ),
            CalendarCard(
              year: _y,
              month: _m,
              marks: marks,
              available: const {},
              onPrev: () => _shift(-1),
              onNext: isCurrent ? null : () => _shift(1),
              legend: const [(C.markGood, 'Good'), (C.markLow, 'Low'), (C.danger, 'Awful')],
            ),
            ActionGrid([
              GridItem('insights', 'Mood insights', sub: 'Triggers & trends', onTap: () => push(context, const MoodInsightsScreen())),
              GridItem('edit_note', 'My journal', sub: journalCount == 1 ? '1 entry' : '$journalCount entries', tone: Tone.lilac, onTap: () async {
                await push(context, const JournalListScreen());
                reload();
              }),
            ]),
            ListCards([ListItemData(icon: 'history', tone: Tone.blue, title: 'Mood history', sub: 'Week and month view', onTap: () => push(context, const MoodHistoryScreen()))]),
          ],
        );
      },
    );
  }
}

/// X-04 — averages and most common triggers.
class MoodInsightsScreen extends StatefulWidget {
  const MoodInsightsScreen({super.key});

  @override
  State<MoodInsightsScreen> createState() => _MoodInsightsScreenState();
}

class _MoodInsightsScreenState extends State<MoodInsightsScreen> {
  int _seg = 0;
  static const _ranges = ['week', 'month', 'semester'];

  @override
  Widget build(BuildContext context) {
    final seg = Segmented(items: const ['Week', 'Month', 'Semester'], index: _seg, onChanged: (i) => setState(() => _seg = i));
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_seg),
      load: () => api.get('/mood/insights', query: {'range': _ranges[_seg]}),
      wrap: (c) => MbPage(title: 'Mood insights', children: [seg, c]),
      builder: (context, d, reload) {
        final bars = (d['bars'] as List).cast<Map<String, dynamic>>();
        final triggers = (d['triggers'] as List).cast<Map<String, dynamic>>();
        final pattern = d['pattern'] as String?;
        return MbPage(
          title: 'Mood insights',
          onRefresh: reload,
          children: [
            seg,
            if ((d['total'] as num) == 0)
              const StateView(icon: 'insights', tone: Tone.grey, title: 'Not enough check-ins yet', text: 'Check in a few times and your trends will appear here.')
            else ...[
              BarsChart(
                title: 'Average mood',
                sub: _seg == 0 ? 'Last 6 weeks · 1 = Awful, 5 = Great' : (_seg == 1 ? 'Last 4 months' : 'Last 5 months'),
                max: 5,
                highlight: bars.length - 1,
                items: [for (final b in bars) BarDatum(b['label'] as String, (b['value'] as num?)?.toDouble())],
              ),
              if (triggers.isNotEmpty) HBarsChart(title: 'Most common triggers', items: [for (final t in triggers) BarDatum(t['label'] as String, (t['value'] as num).toDouble())]),
              if (pattern != null) BannerCard(tone: Tone.lilac, icon: 'lightbulb', title: 'Pattern noticed', text: pattern, link: 'Find a counsellor', onLink: () => push(context, const CounsellorListScreen())),
            ],
            const BannerCard(icon: 'lock', text: 'Insights are calculated from your private check-ins and are never shared.'),
          ],
        );
      },
    );
  }
}
