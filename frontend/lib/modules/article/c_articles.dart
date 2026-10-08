// MEMBER 4 — Article Management: counsellor creates, updates, submits and deletes articles,
// and adds a cover image (uploaded to Cloudinary through the API).
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/image_adjust.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import 'articles.dart';

(String, Tone) _statusOf(Map<String, dynamic> a) {
  if (a['hasRevision'] == true && (a['revision']?['submittedAt']) != null) return ('Edit in review', Tone.amber);
  return switch (a['status']) {
    'published' => ('Live', Tone.green),
    'in_review' => ('In review', Tone.amber),
    'rejected' => ('Changes needed', Tone.red),
    _ => ('Draft', Tone.grey),
  };
}

/// M2-39 / M2-52
class MyArticlesScreen extends StatefulWidget {
  const MyArticlesScreen({super.key});

  @override
  State<MyArticlesScreen> createState() => _MyArticlesScreenState();
}

class _MyArticlesScreenState extends State<MyArticlesScreen> {
  int _seg = 0;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/articles/mine'),
        wrap: (c) => MbPage(title: 'My articles', root: true, children: [c]),
        builder: (context, d, reload) {
          final all = (d['articles'] as List).cast<Map<String, dynamic>>();
          final st = d['stats'] as Map<String, dynamic>;
          final list = all.where((a) {
            final s = a['status'];
            final inReview = s == 'in_review' || (a['revision']?['submittedAt'] != null);
            return switch (_seg) { 0 => s == 'published', 1 => inReview, _ => s == 'draft' || s == 'rejected' };
          }).toList();
          Future<void> open(Widget page) async {
            await push(context, page, root: true);
            reload();
          }

          if (all.isEmpty) {
            return MbPage(
              title: 'My articles',
              root: true,
              onRefresh: reload,
              children: const [StateView(icon: 'edit_note', tone: Tone.grey, title: 'No articles yet', text: 'Share practical guidance students can read any time. Student Affairs reviews every article first.')],
              foot: [MbButton('Write your first article', onPressed: () => open(const ArticleEditScreen()))],
            );
          }
          return MbPage(
            title: 'My articles',
            root: true,
            onRefresh: reload,
            children: [
              StatsGrid(cols: 3, [StatItem('${st['published']}', 'Published'), StatItem('${st['in_review']}', 'In review'), StatItem('${st['draft']}', 'Drafts')]),
              MbButton('Write a new article', icon: 'add', onPressed: () => open(const ArticleEditScreen())),
              Segmented(items: const ['Published', 'In review', 'Drafts'], index: _seg, onChanged: (i) => setState(() => _seg = i)),
              if (list.isEmpty)
                StateView(icon: 'article', tone: Tone.grey, title: 'Nothing here', text: ['No live articles yet.', 'Nothing is waiting for review.', 'No drafts. Start a new article any time.'][_seg], padding: const EdgeInsets.fromLTRB(8, 10, 8, 6))
              else
                ListCards([
                  for (final a in list)
                    () {
                      final s = _statusOf(a);
                      final (icon, tone) = categoryStyle(a['category'] as String?);
                      return ListItemData(
                        icon: icon,
                        tone: tone,
                        title: a['title'] as String,
                        sub: a['status'] == 'published' ? 'Published ${Fmt.stamp(a['publishedAt'])} · ${a['reads']} reads' : '${a['category']} · edited ${Fmt.stamp(a['updatedAt'])}',
                        badge: s.$1,
                        badgeTone: s.$2,
                        onTap: () => open(ArticlePreviewScreen(id: a['id'] as String)),
                      );
                    }(),
                ]),
            ],
          );
        },
      );
}

/// M2-40 / M2-42
class ArticleEditScreen extends StatefulWidget {
  const ArticleEditScreen({super.key, this.article});
  final Map<String, dynamic>? article;

  @override
  State<ArticleEditScreen> createState() => _ArticleEditScreenState();
}

class _ArticleEditScreenState extends State<ArticleEditScreen> {
  late final Map<String, dynamic>? _rev = widget.article?['revision'] as Map<String, dynamic>?;
  late final _title = TextEditingController(text: (_rev?['title'] ?? widget.article?['title'] ?? '') as String);
  late final _body = TextEditingController(text: (_rev?['body'] ?? widget.article?['body'] ?? '') as String);
  late String _cat = (_rev?['category'] ?? widget.article?['category'] ?? 'Stress') as String;
  final Map<String, String> _err = {};
  bool _busy = false;

  bool get _live => widget.article?['status'] == 'published';

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<String?> _save() async {
    _err.clear();
    if (_title.text.trim().length < 5) _err['title'] = 'Use a clear, practical title (5+ characters)';
    if (_body.text.trim().length < 50) _err['body'] = 'Write at least a short paragraph (50+ characters)';
    setState(() {});
    if (_err.isNotEmpty) return null;
    setState(() => _busy = true);
    try {
      final body = {'title': _title.text.trim(), 'category': _cat, 'body': _body.text.trim()};
      final id = widget.article?['id'];
      final r = id == null ? await api.post('/articles', body) : await api.put('/articles/$id', body);
      return (r['article'] as Map)['id'] as String;
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: widget.article == null ? 'New article' : 'Edit article',
        bg: PageBg.white,
        children: [
          MbField(label: 'Title', controller: _title, hint: 'A clear, practical title', error: _err['title'], capitalization: TextCapitalization.sentences, maxLength: 120),
          MbField(label: 'Category', type: FieldType.select, value: _cat, onTap: () async {
            final v = await pickOption(context, title: 'Category', options: articleCategories, current: _cat);
            if (v != null) setState(() => _cat = v);
          }),
          ArticleCover(
            url: widget.article?['coverUrl'] as String?,
            category: _cat,
            height: 120,
            label: _live ? null : 'Add a cover photo from Preview, or keep this one',
          ),
          MbField(label: 'Body', controller: _body, type: FieldType.area, rows: 10, hint: 'Write in plain language. Avoid medical claims. Leave a blank line between paragraphs.', error: _err['body'], maxLength: 20000),
          if (_live) const Txt('Edits to a live article go back to review before they appear. Students keep seeing the current version meanwhile.', size: TxtSize.xs),
        ],
        footRow: true,
        foot: [
          MbButton('Save draft', kind: BtnKind.secondary, loading: _busy, onPressed: () async {
            final id = await _save();
            if (id != null && context.mounted) {
              Navigator.of(context).pop();
              toast(context, 'Saved.');
            }
          }),
          MbButton('Preview', onPressed: _busy
              ? null
              : () async {
                  final id = await _save();
                  if (id != null && context.mounted) replace(context, ArticlePreviewScreen(id: id), root: true);
                }),
        ],
      );
}

/// M2-41 / M2-43 — preview, submit for review, and see reviewer feedback.
class ArticlePreviewScreen extends StatelessWidget {
  const ArticlePreviewScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/articles/$id'),
        wrap: (c) => MbPage(title: 'Preview', children: [c]),
        builder: (context, d, reload) {
          final a = d['article'] as Map<String, dynamic>;
          final rev = a['revision'] as Map<String, dynamic>?;
          final review = a['review'] as Map<String, dynamic>?;
          final status = a['status'] as String;
          final pendingEdit = rev != null && rev['submittedAt'] == null;
          final shown = rev ?? a;
          final canSubmit = status == 'draft' || status == 'rejected' || pendingEdit;
          final coverUrl = a['coverUrl'] as String?;
          final canChangeCover = status == 'draft' || status == 'rejected';

          // Every cover goes through the editor, so it's framed the way it shows in the Wellness hub.
          Future<void> uploadCover(Uint8List bytes) async {
            final edited = await adjustImage(context, bytes: bytes, shape: CropShape.wide, title: 'Adjust cover');
            if (edited == null || !context.mounted) return;
            final r = await guard(context, () => api.upload('/articles/$id/cover', bytes: edited, filename: 'cover.png', method: 'PUT'));
            if (r != null && context.mounted) {
              toast(context, 'Cover updated.');
              await reload();
            }
          }

          Future<void> pickCover() async {
            final bytes = await pickImageBytes(context);
            if (bytes != null && context.mounted) await uploadCover(bytes);
          }

          Future<void> adjustCover() async {
            final bytes = await downloadImage(coverUrl!);
            if (!context.mounted) return;
            if (bytes == null) return toast(context, 'Couldn’t open the cover. Check your connection.');
            await uploadCover(bytes);
          }

          Future<void> removeCover() async {
            final r = await guard(context, () => api.delete('/articles/$id/cover'));
            if (r != null && context.mounted) {
              toast(context, 'Cover removed. The category picture is shown instead.');
              await reload();
            }
          }

          return MbPage(
            title: 'Preview',
            onRefresh: reload,
            actions: [
              if (status != 'published' && status != 'in_review')
                HeaderAction('delete', tooltip: 'Delete draft', danger: true, onTap: () async {
                  final r = await showMbSheet(context, icon: 'delete', tone: Tone.red, title: 'Delete this draft?', text: 'It will be removed permanently.', actions: [
                    SheetAction('Delete draft', kind: BtnKind.danger, run: (_) async {
                      await api.delete('/articles/$id');
                      return true;
                    }),
                    const SheetAction('Keep it', kind: BtnKind.ghost),
                  ]);
                  if (r == 'Delete draft' && context.mounted) Navigator.of(context).pop();
                }),
            ],
            children: [
              if (status == 'rejected' && review != null)
                BannerCard(tone: Tone.red, icon: 'feedback', title: 'Sent back: ${review['reason']}', text: (review['feedback'] as String?)?.isNotEmpty == true ? review['feedback'] as String : 'Edit the article and submit it again.')
              else if (status == 'in_review' || rev?['submittedAt'] != null)
                const BannerCard(tone: Tone.amber, icon: 'hourglass_top', title: 'Waiting for Student Affairs', text: 'You’ll be notified when it’s reviewed.')
              else if (status == 'published' && !pendingEdit)
                BannerCard(icon: 'publish', title: 'Live in the Wellness hub', text: '${a['reads']} reads so far.')
              else
                const BannerCard(tone: Tone.blue, icon: 'info', text: 'Student Affairs reviews every article before students can see it.'),
              ArticleCover(url: coverUrl, category: shown['category'] as String?, height: 160),
              if (canChangeCover)
                ButtonGroup([
                  MbButton(coverUrl == null ? 'Add cover photo' : 'Change cover', kind: BtnKind.soft, icon: 'add_photo_alternate', onPressed: pickCover),
                  if (coverUrl != null) MbButton('Adjust cover', kind: BtnKind.secondary, icon: 'crop', onPressed: adjustCover),
                  if (coverUrl != null) MbButton('Remove cover', kind: BtnKind.ghost, icon: 'hide_image', onPressed: removeCover),
                ]),
              Txt(shown['title'] as String, size: TxtSize.xl),
              Txt('${(a['author'] as Map?)?['name'] ?? ''} · ${shown['category']} · ${a['readMinutes']} min read', size: TxtSize.xs),
              for (final p in (shown['body'] as String).split(RegExp(r'\n\s*\n'))) Txt(p.trim()),
            ],
            footRow: true,
            foot: [
              MbButton('Edit', kind: BtnKind.secondary, onPressed: status == 'in_review' || rev?['submittedAt'] != null ? null : () => replace(context, ArticleEditScreen(article: a), root: true)),
              if (canSubmit)
                MbButton('Submit for review', onPressed: () async {
                  final r = await guard(context, () => api.post('/articles/$id/submit'));
                  if (r != null && context.mounted) {
                    replace(
                      context,
                      MbPage(
                        bg: PageBg.white,
                        children: const [StateView(icon: 'outgoing_mail', title: 'Submitted for review', text: 'Student Affairs will check it against the article guidelines. You’ll be notified when it’s published.')],
                        foot: [Builder(builder: (c) => MbButton('Back to articles', onPressed: () => Navigator.of(c).pop()))],
                      ),
                      root: true,
                    );
                  }
                }),
            ],
          );
        },
      );
}
