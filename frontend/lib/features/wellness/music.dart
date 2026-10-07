import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/player.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// M4-31
class MusicListScreen extends StatefulWidget {
  const MusicListScreen({super.key});

  @override
  State<MusicListScreen> createState() => _MusicListScreenState();
}

class _MusicListScreenState extends State<MusicListScreen> {
  int _cat = 0;

  @override
  void initState() {
    super.initState();
    // Tracks live on the server; refresh them each time the list opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlayerState>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final cats = ['All', ...player.categories];
    if (_cat >= cats.length) _cat = 0;
    final tracks = [
      for (var i = 0; i < player.tracks.length; i++)
        if (_cat == 0 || player.tracks[i].category == cats[_cat]) i,
    ];
    return MbPage(
      title: 'Relaxing music',
      onRefresh: player.load,
      children: [
        Chips(items: cats, selected: {_cat}, onTap: (i) => setState(() => _cat = i)),
        SectionHeader(_cat == 0 ? 'Popular now' : cats[_cat]),
        if (player.tracks.isEmpty && player.loading)
          const LoadingList()
        else if (player.tracks.isEmpty && player.error != null)
          ErrorBlock(error: player.error!, onRetry: player.load)
        else if (tracks.isEmpty)
          const StateView(icon: 'music_off', tone: Tone.grey, title: 'No tracks yet', text: 'Student Affairs adds new music regularly. Check back soon.')
        else
        ListCards([
          for (final i in tracks)
            () {
              final t = player.tracks[i];
              final current = player.index == i;
              return ListItemData(
                icon: current && player.playing ? 'equalizer' : t.icon,
                tone: Tone.of(t.tone),
                title: t.title,
                sub: '${t.artist} · ${Fmt.mmss(t.seconds)}',
                meta: current ? (player.playing ? 'Playing' : 'Paused') : null,
                onTap: () {
                  if (!current) player.play(i);
                  push(context, const MusicPlayerScreen(), root: true);
                },
              );
            }(),
        ]),
        const BannerCard(tone: Tone.blue, icon: 'headphones', text: 'Music keeps playing while you browse MindBridge. Use the mini player above the tabs to pause.'),
      ],
    );
  }
}

/// M4-32
class MusicPlayerScreen extends StatelessWidget {
  const MusicPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerState>();
    final t = p.current;
    if (t == null) {
      return const MbPage(title: 'Now playing', bg: PageBg.white, children: [StateView(icon: 'music_off', tone: Tone.grey, title: 'Nothing playing', text: 'Choose a track from Relaxing music.')]);
    }
    final tone = Tone.of(t.tone);
    return MbPage(
      title: 'Now playing',
      bg: PageBg.white,
      actions: [HeaderAction('stop_circle', tooltip: 'Stop music', onTap: () {
        p.stop();
        Navigator.of(context).pop();
      })],
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tone.bg, const Color(0xFFD8E2C6)]),
              border: Border.all(color: const Color(0xFFD6DEC6)),
            ),
            alignment: Alignment.center,
            child: AnimatedScale(scale: p.playing ? 1 : .9, duration: const Duration(milliseconds: 400), child: MbIcon(t.icon, size: 110, color: tone.fg.withValues(alpha: .7))),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.title, style: Ty.lora(size: 23)),
          const SizedBox(height: 3),
          Text('${t.artist} · ${t.category}', style: Ty.nunito(size: 14.5, color: C.muted)),
        ]),
        Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 6, activeTrackColor: C.primary, inactiveTrackColor: const Color(0xFFE8E1D3), thumbColor: C.primary, overlayShape: SliderComponentShape.noOverlay, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
            child: Slider(value: p.position.toDouble().clamp(0, p.duration.toDouble()), max: p.duration < 1 ? 1 : p.duration.toDouble(), onChanged: (v) => p.seek(v.round()), semanticFormatterCallback: (v) => Fmt.mmss(v.round())),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(Fmt.mmss(p.position), style: Ty.nunito(size: 12, weight: FontWeight.w600, color: C.muted2)),
            const Spacer(),
            Text(Fmt.mmss(p.duration), style: Ty.nunito(size: 12, weight: FontWeight.w600, color: C.muted2)),
          ]),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(tooltip: 'Restart', onPressed: () => p.seek(0), icon: const MbIcon('replay', size: 24, color: C.muted3)),
            IconButton(tooltip: 'Previous', onPressed: p.previous, icon: const MbIcon('skip_previous', size: 34)),
            Semantics(
              button: true,
              label: p.playing ? 'Pause' : 'Play',
              child: Material(
                color: C.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: p.toggle,
                  child: SizedBox(width: 72, height: 72, child: Center(child: MbIcon(p.playing ? 'pause' : 'play_arrow', size: 40, color: Colors.white, fill: true))),
                ),
              ),
            ),
            IconButton(tooltip: 'Next', onPressed: p.next, icon: const MbIcon('skip_next', size: 34)),
            IconButton(tooltip: 'Stop', onPressed: () {
              p.stop();
              Navigator.of(context).pop();
            }, icon: const MbIcon('bedtime', size: 24, color: C.muted3)),
          ]),
        ),
        if (!t.hasAudio) const Txt('Demo track: no audio file has been uploaded for it yet, so playback is simulated.', size: TxtSize.xs, align: TextAlign.center),
      ],
    );
  }
}

/// M4-33 — mini player above the tab bar.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerState>();
    final t = p.current;
    if (t == null) return const SizedBox.shrink();
    final pct = p.duration == 0 ? 0.0 : (p.position / p.duration).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: C.dark,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => rootNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const MusicPlayerScreen())),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF5C8A63), borderRadius: BorderRadius.circular(12)), child: MbIcon(t.icon, size: 22, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.nunito(size: 14, weight: FontWeight.w700, color: Colors.white)),
                    Text('${t.artist} · ${t.category}', style: Ty.nunito(size: 12, color: Colors.white.withValues(alpha: .75))),
                  ]),
                ),
                Semantics(
                  button: true,
                  label: p.playing ? 'Pause' : 'Play',
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(customBorder: const CircleBorder(), onTap: p.toggle, child: SizedBox(width: 40, height: 40, child: Center(child: MbIcon(p.playing ? 'pause' : 'play_arrow', size: 24, color: C.dark, fill: true)))),
                  ),
                ),
              ]),
            ),
            Positioned(left: 0, bottom: 0, child: LayoutBuilder(builder: (context, _) => Container(height: 3, width: MediaQuery.sizeOf(context).width * pct, color: C.leaf))),
          ]),
        ),
      ),
    );
  }
}
