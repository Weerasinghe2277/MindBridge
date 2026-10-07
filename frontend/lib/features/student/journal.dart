import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

const journalTags = ['Academic', 'Social', 'Health', 'Family', 'Gratitude'];

/// X-05 — encrypted, private journal.
class JournalListScreen extends StatefulWidget {
  const JournalListScreen({super.key});

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>>? _list;
  int _total = 0;
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
      final r = await api.get('/mood/journal', query: {'q': _q.text.trim()});
      if (!mounted) return;
      setState(() {
        _list = (r['entries'] as List).cast<Map<String, dynamic>>();
        _total = (r['total'] as num).toInt();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(Widget page) async {
    await push(context, page, root: true);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return MbPage(
      title: 'My journal',
      onRefresh: _load,
      actions: [HeaderAction('add', tooltip: 'New entry', onTap: () => _open(const JournalEditScreen()))],
      children: [
        if (_total > 0 || _q.text.isNotEmpty)
          SearchBox(controller: _q, hint: 'Search entries', onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), _load);
          }),
        if (_error != null)
          ErrorBlock(error: _error!, onRetry: _load)
        else if (list == null)
          const LoadingList(n: 3)
        else if (list.isEmpty)
          _q.text.isEmpty
              ? const StateView(icon: 'edit_note', tone: Tone.lilac, title: 'Start your journal', text: 'Writing a few lines can help you make sense of a busy week. Entries are private to you.')
              : const StateView(icon: 'search_off', tone: Tone.grey, title: 'No matching entries', text: 'Try another word.')
        else
          ListCards([
            for (final j in list)
              ListItemData(
                icon: 'edit_note',
                tone: Tone.lilac,
                title: j['title'] as String,
                sub: j['excerpt'] as String,
                meta: Fmt.stamp(j['createdAt']),
                onTap: () => _open(JournalEntryScreen(id: j['id'] as String)),
              ),
          ]),
        const BannerCard(icon: 'lock', text: 'Journal entries are encrypted and visible only to you.'),
      ],
      foot: list != null && list.isEmpty && _q.text.isEmpty ? [MbButton('Write your first entry', onPressed: () => _open(const JournalEditScreen()))] : const [],
    );
  }
}

/// X-06 — new or edit entry.
class JournalEditScreen extends StatefulWidget {
  const JournalEditScreen({super.key, this.entry});
  final Map<String, dynamic>? entry;

  @override
  State<JournalEditScreen> createState() => _JournalEditScreenState();
}

class _JournalEditScreenState extends State<JournalEditScreen> {
  late final _title = TextEditingController(text: widget.entry?['title'] as String? ?? '');
  late final _body = TextEditingController(text: widget.entry?['body'] as String? ?? '');
  late int? _mood = widget.entry?['mood'] as int?;
  late final Set<int> _tags = {for (final t in (widget.entry?['tags'] as List? ?? [])) if (journalTags.contains(t)) journalTags.indexOf(t as String)};
  final Map<String, String> _err = {};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _err.clear();
    if (_title.text.trim().isEmpty) _err['title'] = 'Give it a name';
    if (_body.text.trim().isEmpty) _err['body'] = 'Write a few words';
    setState(() {});
    if (_err.isNotEmpty) return;
    setState(() => _busy = true);
    final body = {'title': _title.text.trim(), 'body': _body.text.trim(), 'mood': _mood, 'tags': [for (final i in _tags) journalTags[i]]};
    try {
      final id = widget.entry?['id'];
      final r = id == null ? await api.post('/mood/journal', body) : await api.put('/mood/journal/$id', body);
      if (!mounted) return;
      if (id == null) {
        replace(context, JournalEntryScreen(id: (r['entry'] as Map)['id'] as String), root: true);
      } else {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: widget.entry == null ? 'New entry' : 'Edit entry',
        bg: PageBg.white,
        children: [
          MbField(label: 'Title', controller: _title, hint: 'Give it a name', error: _err['title'], capitalization: TextCapitalization.sentences),
          const SectionHeader('Mood'),
          MoodPicker(selected: _mood, onSelect: (m) => setState(() => _mood = _mood == m ? null : m)),
          const SectionHeader('Tags'),
          Chips(wrap: true, items: journalTags, selected: _tags, onTap: (i) => setState(() => _tags.contains(i) ? _tags.remove(i) : _tags.add(i))),
          MbField(label: 'Your thoughts', controller: _body, type: FieldType.area, rows: 6, hint: 'Write freely. No one else will see this.', maxLength: 10000),
          if (_err['body'] != null) Text(_err['body']!, style: Ty.nunito(size: 12.5, weight: FontWeight.w600, color: C.dangerText)),
          const ToggleTile(title: 'Private entry', sub: 'Never shared, even with your counsellor', value: true, locked: true),
        ],
        foot: [MbButton('Save entry', loading: _busy, onPressed: _save)],
      );
}

/// X-07 — read an entry.
class JournalEntryScreen extends StatefulWidget {
  const JournalEntryScreen({super.key, required this.id});
  final String id;

  @override
  State<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends State<JournalEntryScreen> {
  final _key = GlobalKey<LoaderState<Map<String, dynamic>>>();

  Future<void> _delete() async {
    final r = await showMbSheet(context, icon: 'delete', tone: Tone.red, title: 'Delete this entry?', text: 'It will be permanently removed. This can’t be undone.', actions: [
      SheetAction('Delete entry', kind: BtnKind.danger, run: (_) async {
        await api.delete('/mood/journal/${widget.id}');
        return true;
      }),
      const SheetAction('Keep it', kind: BtnKind.ghost),
    ]);
    if (r == 'Delete entry' && mounted) {
      Navigator.of(context).pop();
      toast(context, 'Entry deleted.');
    }
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        key: _key,
        load: () async => (await api.get('/mood/journal/${widget.id}'))['entry'] as Map<String, dynamic>,
        wrap: (c) => MbPage(title: 'Journal entry', children: [c]),
        builder: (context, j, reload) => MbPage(
          title: 'Journal entry',
          actions: [
            HeaderAction('edit', tooltip: 'Edit', onTap: () async {
              final changed = await push<bool>(context, JournalEditScreen(entry: j), root: true);
              if (changed == true) reload();
            }),
          ],
          children: [
            Tags([...(j['tags'] as List).cast<String>(), if (j['moodLabel'] != null) j['moodLabel'] as String]),
            Txt(j['title'] as String, size: TxtSize.xl),
            Txt('${Fmt.longDateStr(Fmt.dateStr(Fmt.sl(Fmt.parse(j['createdAt']))))} · ${Fmt.time(j['createdAt'])}', size: TxtSize.xs),
            for (final p in (j['body'] as String).split(RegExp(r'\n\s*\n'))) Txt(p.trim()),
            MbButton('Delete entry', kind: BtnKind.dangerSoft, icon: 'delete', onPressed: _delete),
          ],
        ),
      );
}
