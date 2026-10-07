import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import 'ui.dart';

const moods = [
  ('sentiment_very_dissatisfied', 'Awful'),
  ('sentiment_dissatisfied', 'Low'),
  ('sentiment_neutral', 'Okay'),
  ('sentiment_satisfied', 'Good'),
  ('sentiment_very_satisfied', 'Great'),
];

Color moodColor(int m) => m <= 0 ? C.danger : (m == 1 ? C.markLow : C.markGood);

class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key, this.title, this.link, this.onLink, required this.selected, required this.onSelect, this.card = true});
  final String? title;
  final String? link;
  final VoidCallback? onLink;
  final int? selected;
  final ValueChanged<int> onSelect;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final row = Row(children: [
      for (var i = 0; i < moods.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            button: true,
            selected: selected == i,
            label: moods[i].$2,
            child: Material(
              color: selected == i ? C.softGreen : const Color(0xFFF7F4EC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: selected == i ? C.primary : Colors.transparent, width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelect(i),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
                  child: Column(children: [
                    MbIcon(moods[i].$1, size: 30, color: selected == i ? C.dark : C.muted, fill: selected == i),
                    const SizedBox(height: 6),
                    Text(moods[i].$2, style: Ty.nunito(size: 11.5, weight: FontWeight.w700, color: selected == i ? C.dark : C.muted)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ],
    ]);
    if (!card) return row;
    return MbCard(
      radius: 20,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Row(children: [
            Expanded(child: Text(title!, style: Ty.nunito(size: 16, weight: FontWeight.w700))),
            if (link != null) TextLink(link!, onTap: onLink),
          ]),
          const SizedBox(height: 14),
        ],
        row,
      ]),
    );
  }
}

class BarDatum {
  const BarDatum(this.label, this.value, {this.text});
  final String label;
  final double? value;
  final String? text;
}

class BarsChart extends StatelessWidget {
  const BarsChart({super.key, required this.title, this.sub, required this.items, this.max, this.highlight});
  final String title;
  final String? sub;
  final List<BarDatum> items;
  final double? max;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final values = items.map((e) => e.value ?? 0).toList();
    final mx = max ?? (values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b));
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Ty.nunito(size: 15, weight: FontWeight.w700)),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: Ty.nunito(size: 12.5, color: C.muted))),
        const SizedBox(height: 14),
        Semantics(
          label: '$title: ${items.map((e) => '${e.label} ${e.text ?? e.value?.toStringAsFixed(1) ?? 'no data'}').join(', ')}',
          child: SizedBox(
            height: 140,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(children: [
                    SizedBox(height: 13, child: Text(items[i].text ?? '', style: Ty.nunito(size: 11, weight: FontWeight.w700, color: C.muted))),
                    const SizedBox(height: 6),
                    Expanded(
                      child: LayoutBuilder(builder: (_, c) {
                        final v = items[i].value;
                        final h = v == null ? 4.0 : (mx <= 0 ? 4.0 : (v / mx * c.maxHeight).clamp(4.0, c.maxHeight));
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: h),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            builder: (_, hh, _) => Container(
                              height: hh,
                              constraints: const BoxConstraints(maxWidth: 30),
                              decoration: BoxDecoration(
                                color: v == null ? C.barBg : (i == highlight ? C.primary : C.barLight),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(items[i].label, style: Ty.nunito(size: 11.5, weight: FontWeight.w700, color: C.muted2)),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class HBarsChart extends StatelessWidget {
  const HBarsChart({super.key, required this.title, this.sub, required this.items, this.max});
  final String title;
  final String? sub;
  final List<BarDatum> items;
  final double? max;

  static const _pal = [Color(0xFF4A7C59), Color(0xFF6B9168), Color(0xFF8DA878), Color(0xFFB0BF8C), Color(0xFFC9CFA6), Color(0xFFDCDFC2)];

  @override
  Widget build(BuildContext context) {
    final values = items.map((e) => e.value ?? 0).toList();
    final mx = max ?? (values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b));
    return MbCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Ty.nunito(size: 15, weight: FontWeight.w700)),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: Ty.nunito(size: 12.5, color: C.muted))),
        const SizedBox(height: 14),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(items[i].label, style: Ty.nunito(size: 13.5, weight: FontWeight.w600, color: C.ink2))),
                Text(items[i].text ?? (items[i].value == null ? 'Hidden' : items[i].value!.round().toString()), style: Ty.nunito(size: 13.5, weight: FontWeight.w700, color: items[i].value == null ? C.muted3 : C.ink)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  color: C.barBg,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (items[i].value == null || mx <= 0) ? 0 : (items[i].value! / mx).clamp(0, 1),
                    child: Container(decoration: BoxDecoration(color: _pal[i % _pal.length], borderRadius: BorderRadius.circular(4))),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Month calendar. `available` limits which days can be picked (null = all days).
class CalendarCard extends StatelessWidget {
  const CalendarCard({super.key, required this.year, required this.month, this.selected, this.available, this.marks = const {}, this.onSelect, this.onPrev, this.onNext, this.legend = const [], this.loading = false});
  final int year;
  final int month;
  final int? selected;
  final Set<int>? available;
  final Map<int, Color> marks;
  final ValueChanged<int>? onSelect;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final List<(Color, String)> legend;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final first = DateTime.utc(year, month, 1);
    final days = DateTime.utc(year, month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final today = Fmt.nowSl();
    final isThisMonth = today.year == year && today.month == month;
    final cells = <Widget>[
      for (final l in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(l, style: Ty.nunito(size: 11.5, weight: FontWeight.w700, color: C.muted4)))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++) _day(d, isThisMonth && today.day == d),
    ];
    return MbCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(children: [
            _nav('chevron_left', onPrev, 'Previous month'),
            Expanded(child: Center(child: Text(Fmt.monthTitle(year, month), style: Ty.nunito(size: 15, weight: FontWeight.w700)))),
            _nav('chevron_right', onNext, 'Next month'),
          ]),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: loading ? .45 : 1,
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 1.05,
            children: cells,
          ),
        ),
        if (legend.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(alignment: WrapAlignment.center, spacing: 14, children: [
              for (final l in legend)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: l.$1, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(l.$2, style: Ty.nunito(size: 11.5, color: C.muted)),
                ]),
            ]),
          ),
      ]),
    );
  }

  Widget _nav(String icon, VoidCallback? onTap, String label) => IconButton(
        tooltip: label,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: MbIcon(icon, size: 22, color: onTap == null ? C.track : C.muted3),
      );

  Widget _day(int d, bool isToday) {
    final av = available == null || available!.contains(d);
    final on = selected == d;
    final mark = marks[d];
    final dot = on ? Colors.white : (mark ?? (available != null && av ? C.primary : Colors.transparent));
    return Semantics(
      button: av,
      selected: on,
      label: '$d ${Fmt.monthTitle(year, month)}${av ? '' : ', unavailable'}',
      child: GestureDetector(
        onTap: av && onSelect != null ? () => onSelect!(d) : null,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: on ? C.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isToday && !on ? C.primary : Colors.transparent, width: 1.5),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$d', style: Ty.nunito(size: 14, weight: av ? FontWeight.w700 : FontWeight.w400, color: on ? Colors.white : (av ? C.ink : C.disabled))),
              const SizedBox(height: 1),
              Container(width: 4, height: 4, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }
}

class ChatMsg {
  const ChatMsg(this.fromMe, this.text);
  final bool fromMe;
  final String text;
}

class ChatBubbles extends StatelessWidget {
  const ChatBubbles(this.msgs, {super.key, this.typing = false});
  final List<ChatMsg> msgs;
  final bool typing;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final m in msgs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .74),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: m.fromMe ? C.primary : Colors.white,
                    border: Border.all(color: m.fromMe ? C.primary : C.line),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(m.fromMe ? 18 : 6),
                      bottomRight: Radius.circular(m.fromMe ? 6 : 18),
                    ),
                  ),
                  child: Text(m.text, style: Ty.nunito(size: 14.5, height: 1.45, color: m.fromMe ? Colors.white : C.ink)),
                ),
              ),
            ),
          ),
        if (typing) const Align(alignment: Alignment.centerLeft, child: _Typing()),
      ]);
}

class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Bridge is typing',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: C.card, border: Border.all(color: C.line), borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(6))),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Opacity(
                  opacity: () {
                    final t = (_c.value - i * .16) % 1.0;
                    return t < .4 ? .25 + (t / .4) * .75 : (t < .8 ? 1.0 - ((t - .4) / .4) * .75 : .25);
                  }(),
                  child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: C.muted3, shape: BoxShape.circle)),
                ),
              ],
            ]),
          ),
        ),
      );
}
