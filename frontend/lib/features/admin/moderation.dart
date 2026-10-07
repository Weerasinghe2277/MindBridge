import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../modules/article/articles.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// M3-32 / M3-58
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  int _seg = 0;
  int? _waiting;
  static const _status = ['waiting', 'published', 'rejected'];

  @override
  Widget build(BuildContext context) {
    final seg = Segmented(items: ['Waiting${_waiting == null ? '' : ' ($_waiting)'}', 'Approved', 'Rejected'], index: _seg, onChanged: (i) => setState(() => _seg = i));
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_seg),
      load: () async {
        final r = await api.get('/admin/articles', query: {'status': _status[_seg]});
        if (mounted && _waiting != (r['waiting'] as num).toInt()) WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _waiting = (r['waiting'] as num).toInt()));
        return r;
      },
      wrap: (c) => MbPage(title: 'Article moderation', children: [seg, c]),
      builder: (context, d, reload) {
        final list = (d['articles'] as List).cast<Map<String, dynamic>>();
        return MbPage(
          title: 'Article moderation',
          onRefresh: reload,
          children: [
            seg,
            if (list.isEmpty)
              StateView(icon: 'task', title: _seg == 0 ? 'Nothing to review' : 'Nothing here', text: _seg == 0 ? 'New articles from counsellors will appear here.' : 'Articles in this state will appear here.', tone: _seg == 0 ? Tone.green : Tone.grey)
            else
              ListCards([
                for (final a in list)
                  () {
                    final (icon, tone) = categoryStyle(a['category'] as String?);
                    final isEdit = a['status'] == 'published' && a['revision']?['submittedAt'] != null;
                    return ListItemData(
                      icon: icon,
                      tone: tone,
                      title: a['title'] as String,
                      sub: '${(a['author'] as Map?)?['name'] ?? ''} · ${Fmt.stamp(a['submittedAt'] ?? a['updatedAt'])}',
                      badge: _seg == 0 ? (isEdit ? 'Edit' : 'Waiting') : (a['status'] == 'removed' ? 'Removed' : (_seg == 1 ? '${a['reads']} reads' : 'Sent back')),
                      badgeTone: _seg == 0 ? Tone.amber : (_seg == 1 ? Tone.green : Tone.red),
                      onTap: () async {
                        await push(context, ArticleReviewScreen(id: a['id'] as String));
                        reload();
                      },
                    );
                  }(),
              ]),
          ],
        );
      },
    );
  }
}

/// M3-33 → M3-36
class ArticleReviewScreen extends StatelessWidget {
  const ArticleReviewScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () async => (await api.get('/admin/articles/$id'))['article'] as Map<String, dynamic>,
        wrap: (c) => MbPage(title: 'Review article', children: [c]),
        builder: (context, a, reload) {
          final status = a['status'] as String;
          final waiting = status == 'in_review' || a['isRevision'] == true;
          Future<void> done(String title, String text) => replace(
                context,
                MbPage(
                  bg: PageBg.white,
                  children: [StateView(icon: 'task_alt', title: title, text: text)],
                  foot: [Builder(builder: (c) => MbButton('Back to moderation', onPressed: () => Navigator.of(c).pop()))],
                ),
              );
          return MbPage(
            title: 'Review article',
            actions: [
              if (status == 'published')
                HeaderAction('delete', danger: true, tooltip: 'Remove article', onTap: () async {
                  final r = await showMbSheet(context, icon: 'delete', tone: Tone.red, title: 'Remove this article?', text: 'It will no longer be visible to students. The author is told why.', areaHint: 'Reason (sent to the author)', actions: [
                    SheetAction('Remove article', kind: BtnKind.danger, run: (t) async {
                      if (t.isEmpty) throw ApiException(400, 'VALIDATION_ERROR', 'Add a reason for the author.');
                      await api.post('/admin/articles/$id/remove', {'reason': t});
                      return true;
                    }),
                    const SheetAction('Keep it', kind: BtnKind.ghost),
                  ]);
                  if (r == 'Remove article' && context.mounted) done('Article removed', 'It’s no longer visible to students. The author has been told why.');
                }),
            ],
            children: [
              if (a['isRevision'] == true) const BannerCard(tone: Tone.blue, icon: 'edit', text: 'This is an edit to a live article. Students see the current version until you approve.'),
              ArticleCover(url: a['coverUrl'] as String?, category: a['category'] as String?, height: 150),
              Txt(a['title'] as String, size: TxtSize.xl),
              Txt('${(a['author'] as Map?)?['name'] ?? ''} · ${a['category']} · ${a['readMinutes']} min', size: TxtSize.xs),
              for (final p in (a['body'] as String).split(RegExp(r'\n\s*\n'))) Txt(p.trim()),
              const ChecksCard(title: 'Guidelines', [(true, 'No diagnosis or medical claims'), (true, 'Points to support services'), (true, 'Plain, respectful language')]),
              if (a['review']?['reason'] != null) BannerCard(tone: Tone.amber, icon: 'feedback', title: 'Last decision: ${a['review']['reason']}', text: a['review']['feedback'] as String?),
            ],
            footRow: true,
            foot: waiting
                ? [
                    MbButton('Reject', kind: BtnKind.dangerSoft, onPressed: () => push(context, RejectArticleScreen(id: id), root: true).then((v) {
                          if (v == true && context.mounted) Navigator.of(context).pop();
                        })),
                    MbButton('Approve', onPressed: () async {
                      final r = await guard(context, () => api.post('/admin/articles/$id/approve'));
                      if (r != null && context.mounted) done('Article approved', 'It’s now live in the Wellness hub and the author has been notified.');
                    }),
                  ]
                : const [],
          );
        },
      );
}

/// M3-35
class RejectArticleScreen extends StatefulWidget {
  const RejectArticleScreen({super.key, required this.id});
  final String id;

  @override
  State<RejectArticleScreen> createState() => _RejectArticleScreenState();
}

class _RejectArticleScreenState extends State<RejectArticleScreen> {
  static const _reasons = ['Contains medical claims', 'Inaccurate information', 'Tone not suitable', 'Other'];
  int _reason = 0;
  final _fb = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _fb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Reject article',
        children: [
          OptionsList(items: [for (final r in _reasons) OptionItem(r)], selected: _reason, onSelect: (i) => setState(() => _reason = i)),
          MbField(label: 'Feedback for author', controller: _fb, type: FieldType.area, rows: 3, hint: 'What should change before resubmitting?', maxLength: 1500),
        ],
        foot: [
          MbButton('Send back to author', kind: BtnKind.danger, loading: _busy, onPressed: () async {
            setState(() => _busy = true);
            final r = await guard(context, () => api.post('/admin/articles/${widget.id}/reject', {'reason': _reasons[_reason], 'feedback': _fb.text.trim()}));
            if (mounted) setState(() => _busy = false);
            if (r != null && context.mounted) {
              Navigator.of(context).pop(true);
              toast(context, 'Sent back to the author.');
            }
          }),
        ],
      );
}
