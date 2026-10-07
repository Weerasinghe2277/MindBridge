import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/player.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// Relaxing music library for the Wellness hub. Audio files are stored in Cloudinary.
class MusicAdminScreen extends StatelessWidget {
  const MusicAdminScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<List<Track>>(
        load: () async => [for (final t in (await api.get('/music'))['tracks'] as List) Track.fromJson((t as Map).cast<String, dynamic>())],
        wrap: (c) => MbPage(title: 'Relaxing music', children: [c]),
        builder: (context, tracks, reload) {
          Future<void> open(Track? t) async {
            final changed = await push<bool>(context, TrackFormScreen(track: t));
            if (changed == true) await reload();
          }

          return MbPage(
            title: 'Relaxing music',
            onRefresh: reload,
            actions: [HeaderAction('add', tooltip: 'Add track', onTap: () => open(null))],
            children: [
              const BannerCard(tone: Tone.blue, icon: 'headphones', text: 'Students stream these tracks in the Wellness hub. Upload MP3 or M4A files up to 20 MB.'),
              if (tracks.isEmpty)
                const StateView(icon: 'music_off', tone: Tone.grey, title: 'No tracks yet', text: 'Add the first track for students.')
              else
                ListCards([
                  for (final t in tracks)
                    ListItemData(
                      icon: t.icon,
                      tone: Tone.of(t.tone),
                      title: t.title,
                      sub: '${t.artist.isEmpty ? 'Unknown artist' : t.artist} · ${t.category} · ${Fmt.mmss(t.seconds)}',
                      badge: t.hasAudio ? null : 'Demo',
                      badgeTone: Tone.grey,
                      onTap: () => open(t),
                    ),
                ]),
              MbButton('Add track', icon: 'upload', onPressed: () => open(null)),
            ],
          );
        },
      );
}

/// Add a track (with its audio file) or edit / remove an existing one.
class TrackFormScreen extends StatefulWidget {
  const TrackFormScreen({super.key, this.track});
  final Track? track;

  @override
  State<TrackFormScreen> createState() => _TrackFormScreenState();
}

class _TrackFormScreenState extends State<TrackFormScreen> {
  static const _categories = ['Sleep', 'Focus', 'Rain', 'Nature', 'Lo-fi'];
  late final _title = TextEditingController(text: widget.track?.title ?? '');
  late final _artist = TextEditingController(text: widget.track?.artist ?? '');
  late String? _category = widget.track?.category;
  String? _fileName;
  Uint8List? _bytes;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.track == null;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['mp3', 'm4a']);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) {
      if (mounted) toast(context, 'Audio files must be 20 MB or smaller.');
      return;
    }
    setState(() {
      _bytes = bytes;
      _fileName = f.name;
      if (_title.text.trim().isEmpty) _title.text = f.name.replaceAll(RegExp(r'\.(mp3|m4a)$', caseSensitive: false), '');
    });
  }

  Future<void> _save() async {
    if (_isNew && _bytes == null) return setState(() => _error = 'Choose an audio file.');
    if (_title.text.trim().length < 2) return setState(() => _error = 'Add a title.');
    if (_category == null) return setState(() => _error = 'Choose a category.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final fields = {'title': _title.text.trim(), 'artist': _artist.text.trim(), 'category': _category!};
    try {
      if (_isNew) {
        await api.upload('/music', bytes: _bytes!, filename: _fileName!, fields: fields);
      } else {
        await api.patch('/music/${widget.track!.id}', fields);
      }
      if (!mounted) return;
      toast(context, _isNew ? 'Track added.' : 'Track updated.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final t = widget.track!;
    final r = await showMbSheet(context, icon: 'delete', tone: Tone.red, title: 'Remove “${t.title}”?', text: 'Students will no longer see it, and the audio file is deleted.', actions: [
      SheetAction('Remove track', kind: BtnKind.danger, run: (_) async {
        await api.delete('/music/${t.id}');
        return true;
      }),
      const SheetAction('Keep it', kind: BtnKind.ghost),
    ]);
    if (r == 'Remove track' && mounted) {
      toast(context, 'Track removed.');
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: _isNew ? 'Add track' : 'Edit track',
        children: [
          if (_isNew)
            MbCard(
              onTap: _saving ? null : _pick,
              child: Row(children: [
                const IconChip('audio_file', tone: Tone.blue),
                const SizedBox(width: 12),
                Expanded(child: Text(_fileName ?? 'Choose an MP3 or M4A file', style: Ty.nunito(size: 15, weight: FontWeight.w700))),
                const MbIcon('upload', size: 20, color: C.chevron),
              ]),
            )
          else if (!widget.track!.hasAudio)
            const BannerCard(tone: Tone.amber, icon: 'info', text: 'This demo track has no audio file. To add one, remove it and add it again with an MP3.'),
          MbField(label: 'Title', controller: _title, maxLength: 80),
          MbField(label: 'Artist (optional)', controller: _artist, maxLength: 60),
          MbField(label: 'Category', type: FieldType.select, value: _category ?? 'Choose a category', onTap: () async {
            final v = await pickOption(context, title: 'Category', options: _categories, current: _category);
            if (v != null) setState(() => _category = v);
          }),
          if (_error != null) BannerCard(tone: Tone.red, icon: 'error', text: _error!),
          MbButton(_isNew ? 'Upload track' : 'Save changes', icon: _isNew ? 'upload' : 'check', loading: _saving, onPressed: _save),
          if (!_isNew) MbButton('Remove track', kind: BtnKind.dangerSoft, icon: 'delete', onPressed: _saving ? null : _delete),
        ],
      );
}
