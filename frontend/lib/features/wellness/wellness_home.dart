import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../modules/article/articles.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'breathing.dart';
import 'bridge.dart';
import 'emergency.dart';
import 'games.dart';
import 'music.dart';

/// M4-20 — professional help, self-care and crisis support kept visually separate.
class WellnessHome extends StatelessWidget {
  const WellnessHome({super.key});

  @override
  Widget build(BuildContext context) {
    const greet = Greet(eyebrow: 'Wellness hub', title: 'Take a moment');
    Widget greetWithSos(BuildContext context) => Greet(eyebrow: 'Wellness hub', title: 'Take a moment', actions: [
          HeaderAction('emergency', label: 'SOS', danger: true, tooltip: 'Emergency support', onTap: () => push(context, const EmergencyHoldScreen(), root: true)),
        ]);
    return Loader<Map<String, dynamic>>(
      load: () => api.get('/articles'),
      wrap: (c) => MbPage(children: [greet, c]),
      builder: (context, d, reload) {
        final articles = (d['articles'] as List).cast<Map<String, dynamic>>();
        return MbPage(
          onRefresh: reload,
          children: [
            greetWithSos(context),
            HeroCard(
              style: HeroStyle.lilac,
              eyebrow: 'AI wellness assistant',
              title: 'Talk it through with Bridge',
              sub: 'Supportive chat at any hour. Bridge is not a counsellor and will point you to one when it matters.',
              actions: [MbButton('Start a chat', icon: 'forum', onPressed: () => push(context, const BridgeIntroScreen()))],
            ),
            ActionGrid([
              GridItem('menu_book', 'Articles', sub: 'From our counsellors', tone: Tone.amber, onTap: () => push(context, const ArticleListScreen())),
              GridItem('air', 'Guided breathing', sub: '1–3 minutes', onTap: () => push(context, const BreathingHomeScreen())),
              GridItem('extension', 'Calming games', sub: '3 activities', tone: Tone.blue, onTap: () => push(context, const GamesHomeScreen())),
              GridItem('music_note', 'Relaxing music', sub: 'Sleep, focus, rain', tone: Tone.lilac, onTap: () => push(context, const MusicListScreen())),
            ]),
            if (articles.isNotEmpty) ...[
              SectionHeader('Recommended for you', link: 'All articles', onLink: () => push(context, const ArticleListScreen())),
              ListCards([for (final a in articles.take(2)) articleItem(context, a)]),
            ],
            BannerCard(
              tone: Tone.red,
              icon: 'call',
              title: 'In crisis?',
              text: 'Call the National Mental Health Helpline, free and open 24/7.',
              link: 'Call 1926',
              onLink: () => push(context, const SupportOptionsScreen(), root: true),
            ),
          ],
        );
      },
    );
  }
}
