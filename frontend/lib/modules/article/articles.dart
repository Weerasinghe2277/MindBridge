// MEMBER 4 — Article Management: browse articles by category, view article details.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../features/wellness/breathing.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

const articleCategories = ['Stress', 'Sleep', 'Academic', 'Relationships', 'Mindfulness'];

(String, Tone) categoryStyle(String? c) => switch (c) {
      'Sleep' => ('bedtime', Tone.lilac),
      'Stress' => ('checklist', Tone.blue),
      'Academic' => ('school', Tone.amber),
      'Relationships' => ('diversity_3', Tone.amber),
      'Mindfulness' => ('self_improvement', Tone.green),
      _ => ('article', Tone.green),
    };

/// The article's cover photo (stored in Cloudinary), or the category illustration when there is none.
class ArticleCover extends StatelessWidget {
  const ArticleCover({super.key, required this.url, required this.category, this.height = 180, this.label});
  final String? url;
  final String? category;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = categoryStyle(category);
    final fallback = MediaPlaceholder(height: height, icon: icon, tone: tone, label: label);
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.network(
        url!,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        semanticLabel: 'Article cover image',
        loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

ListItemData articleItem(BuildContext context, Map<String, dynamic> a, {bool saved = false, VoidCallback? after}) {
  final st = categoryStyle(a['category'] as String?);
  return ListItemData(
    icon: st.$1,
    tone: st.$2,
    title: a['title'] as String,
    sub: '${(a['author'] as Map?)?['name'] ?? ''} · ${a['readMinutes']} min',
    badge: saved ? 'Saved' : null,
    onTap: () async {
      await push(context, ArticleDetailScreen(id: a['id'] as String));
      after?.call();
    },
  );
}

/// M4-21 / M4-22 — search and browse by topic.
class ArticleListScreen extends StatefulWidget {
  const ArticleListScreen({super.key, this.initialCategory});
  final String? initialCategory;

  @override
  State<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends State<ArticleListScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  late int _cat = widget.initialCategory == null ? 0 : articleCategories.indexOf(widget.initialCategory!) + 1;
  Map<String, dynamic>? _data;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/articles', query: {'q': _q.text.trim(), 'category': _cat == 0 ? '' : articleCategories[_cat - 1]});
      if (mounted) setState(() {
        _data = r;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = (_data?['articles'] as List?)?.cast<Map<String, dynamic>>();
    final saved = ((_data?['saved'] as List?) ?? []).cast<String>().toSet();
    final counts = (_data?['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    final cat = _cat == 0 ? null : articleCategories[_cat - 1];
    final (icon, tone) = categoryStyle(cat);
    return MbPage(
      title: cat ?? 'Articles',
      subtitle: cat != null && counts[cat] != null ? '${counts[cat]} articles' : null,
      onRefresh: _load,
      actions: [HeaderAction('bookmark', tooltip: 'Saved articles', onTap: () async {
        await push(context, const SavedArticlesScreen());
        _load();
      })],
      children: [
        SearchBox(controller: _q, hint: 'Search articles', onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), _load);
        }),
        Chips(items: ['All', ...articleCategories], selected: {_cat}, onTap: (i) {
          setState(() {
            _cat = i;
            _data = null;
          });
          _load();
        }),
        if (cat != null && _q.text.isEmpty)
          HeroCard(style: tone == Tone.lilac ? HeroStyle.lilac : HeroStyle.soft, eyebrow: 'Topic', title: cat, sub: _topicLine(cat)),
        if (_error != null)
          ErrorBlock(error: _error!, onRetry: _load)
        else if (list == null)
          const LoadingList()
        else if (list.isEmpty)
          StateView(icon: icon, tone: Tone.grey, title: 'No articles found', text: _q.text.isEmpty ? 'New articles from our counsellors will appear here.' : 'Try a different word or topic.')
        else
          ListCards([for (final a in list) articleItem(context, a, saved: saved.contains(a['id']), after: _load)]),
      ],
    );
  }

  String _topicLine(String c) => switch (c) {
        'Sleep' => 'Practical ways to rest better when deadlines pile up.',
        'Stress' => 'Small, practical steps for weeks when everything feels urgent.',
        'Academic' => 'Studying, deadlines and group work without burning out.',
        'Relationships' => 'Friends, family, flatmates and feeling at home on campus.',
        _ => 'Short exercises to bring your attention back to the present.',
      };
}

/// M4-23
class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  bool? _saved;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/articles/${widget.id}'),
        wrap: (c) => MbPage(title: 'Article', children: [c]),
        builder: (context, d, reload) {
          final a = d['article'] as Map<String, dynamic>;
          final saved = _saved ?? d['saved'] == true;
          final related = (d['related'] as List).cast<Map<String, dynamic>>();
          final author = a['author'] as Map<String, dynamic>? ?? {};
          final paras = (a['body'] as String).split(RegExp(r'\n\s*\n'));
          return MbPage(
            title: 'Article',
            actions: [
              HeaderAction(saved ? 'bookmark_added' : 'bookmark_add', tooltip: saved ? 'Remove from saved' : 'Save article', onTap: () async {
                final r = await guard(context, () => api.post('/articles/${widget.id}/save'));
                if (r != null && context.mounted) {
                  setState(() => _saved = r['saved'] == true);
                  toast(context, _saved! ? 'Saved for later.' : 'Removed from saved.');
                }
              }),
              HeaderAction('share', tooltip: 'Copy title', onTap: () async {
                await Clipboard.setData(ClipboardData(text: '${a['title']} — MindBridge Wellness hub'));
                if (context.mounted) toast(context, 'Title copied. Find it in the MindBridge Wellness hub.');
              }),
            ],
            children: [
              ArticleCover(url: a['coverUrl'] as String?, category: a['category'] as String?, height: 190),
              Tags([a['category'] as String, '${a['readMinutes']} min read']),
              Txt(a['title'] as String, size: TxtSize.xl),
              Txt('${author['name'] ?? ''}${author['title'] != null ? ' · ${author['title']}' : ''} · Reviewed by Student Affairs', size: TxtSize.xs),
              for (final p in paras)
                if (p.trim().split('\n').length > 1 && p.trim().split('\n').first.length < 40) ...[
                  SectionHeader(p.trim().split('\n').first),
                  Txt(p.trim().split('\n').skip(1).join('\n')),
                ] else
                  Txt(p.trim()),
              if (a['category'] == 'Sleep' || a['category'] == 'Stress' || a['category'] == 'Mindfulness')
                ListCards([
                  ListItemData(
                    icon: 'air',
                    tone: Tone.lilac,
                    title: a['category'] == 'Sleep' ? '4-7-8 breathing for sleep' : '2-minute box breathing',
                    sub: a['category'] == 'Sleep' ? '3 minutes' : 'Good for exam nerves',
                    onTap: () => push(context, BreathingExerciseScreen(pattern: a['category'] == 'Sleep' ? BreathPattern.sleep : BreathPattern.box), root: true),
                  ),
                ]),
              if (related.isNotEmpty) ...[const SectionHeader('More on this topic'), ListCards([for (final r in related) articleItem(context, r)])],
              Text('Published ${a['publishedAt'] != null ? Fmt.dayYear(a['publishedAt']) : ''}', style: Ty.xs),
            ],
          );
        },
      );
}

/// M4-24
class SavedArticlesScreen extends StatelessWidget {
  const SavedArticlesScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/articles/saved'),
        wrap: (c) => MbPage(title: 'Saved', children: [c]),
        builder: (context, d, reload) {
          final list = (d['articles'] as List).cast<Map<String, dynamic>>();
          return MbPage(
            title: 'Saved',
            onRefresh: reload,
            children: list.isEmpty
                ? [const StateView(icon: 'bookmark', tone: Tone.grey, title: 'Nothing saved yet', text: 'Tap the bookmark on any article to keep it here for later.')]
                : [ListCards([for (final a in list) articleItem(context, a, saved: true, after: reload)])],
          );
        },
      );
}
