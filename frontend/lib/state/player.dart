import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/api.dart';

class Track {
  const Track({required this.id, required this.title, required this.artist, required this.category, required this.seconds, required this.icon, required this.tone, this.url});

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String,
        artist: (j['artist'] as String?) ?? '',
        category: j['category'] as String,
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        icon: (j['icon'] as String?) ?? 'music_note',
        tone: (j['tone'] as String?) ?? 'green',
        url: j['url'] as String?,
      );

  final String id;
  final String title;
  final String artist;
  final String category;
  final int seconds;
  final String icon;
  final String tone;

  /// Cloudinary audio link. Tracks without one play as a timed demo.
  final String? url;
  bool get hasAudio => url != null;
}

/// Relaxing-music player state. Playback keeps going while the student browses,
/// and the mini player above the tab bar reflects it.
///
/// Tracks come from the API (`/music`). Tracks with an uploaded audio file stream
/// from Cloudinary through just_audio; demo tracks without audio only track time.
class PlayerState extends ChangeNotifier {
  List<Track> tracks = const [];
  List<String> categories = const ['Sleep', 'Focus', 'Rain', 'Nature', 'Lo-fi'];
  bool loading = false;
  ApiException? error;

  int? index;
  bool playing = false;
  int position = 0;
  bool shuffle = false;
  Timer? _timer;

  // Created on first real playback, so screens and tests without audio never touch the plugin.
  AudioPlayer? _audio;
  final _subs = <StreamSubscription<dynamic>>[];
  int? _audioSeconds;

  Track? get current => index == null || index! >= tracks.length ? null : tracks[index!];
  bool get active => current != null;

  /// Length shown in the UI: the real file length once known, otherwise the stored one.
  int get duration => (current?.hasAudio ?? false) ? (_audioSeconds ?? current!.seconds) : (current?.seconds ?? 0);

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await api.get('/music');
      final playingId = current?.id;
      tracks = [for (final t in r['tracks'] as List) Track.fromJson((t as Map).cast<String, dynamic>())];
      categories = [for (final c in r['categories'] as List) c as String];
      // Keep the current track selected if it still exists.
      final i = playingId == null ? -1 : tracks.indexWhere((t) => t.id == playingId);
      if (playingId != null && i < 0) {
        await _stopAudio();
        index = null;
        playing = false;
      } else if (i >= 0) {
        index = i;
      }
    } on ApiException catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> play(int i) async {
    if (i < 0 || i >= tracks.length) return;
    final changed = index != i;
    index = i;
    if (changed) {
      position = 0;
      _audioSeconds = null;
      _log();
    }
    playing = true;
    notifyListeners();
    final t = tracks[i];
    if (t.hasAudio) {
      _timer?.cancel();
      _timer = null;
      final p = _ensureAudio();
      try {
        if (changed || p.audioSource == null) await p.setUrl(t.url!);
        if (index != i) return; // another track was chosen while this one loaded
        unawaited(p.play());
      } catch (_) {
        playing = false;
        notifyListeners();
      }
    } else {
      await _audio?.stop();
      _ensureTimer();
    }
  }

  void toggle() {
    final t = current;
    if (t == null) return;
    if (playing) {
      playing = false;
      _audio?.pause();
      notifyListeners();
    } else {
      play(index!);
    }
  }

  void next() {
    if (tracks.isEmpty) return;
    play(((index ?? -1) + 1) % tracks.length);
  }

  void previous() {
    if (tracks.isEmpty) return;
    position > 5 ? seek(0) : play(((index ?? 1) - 1 + tracks.length) % tracks.length);
  }

  void seek(int seconds) {
    position = seconds.clamp(0, duration);
    if (current?.hasAudio ?? false) _audio?.seek(Duration(seconds: position));
    notifyListeners();
  }

  void stop() {
    playing = false;
    index = null;
    position = 0;
    _timer?.cancel();
    _timer = null;
    _stopAudio();
    notifyListeners();
  }

  AudioPlayer _ensureAudio() {
    final existing = _audio;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _subs.add(p.positionStream.listen((d) {
      if (!(current?.hasAudio ?? false)) return;
      final s = d.inSeconds;
      if (s != position) {
        position = s;
        notifyListeners();
      }
    }));
    _subs.add(p.durationStream.listen((d) {
      if (d == null) return;
      _audioSeconds = d.inSeconds;
      notifyListeners();
    }));
    _subs.add(p.processingStateStream.listen((s) {
      if (s == ProcessingState.completed && (current?.hasAudio ?? false)) next();
    }));
    return _audio = p;
  }

  Future<void> _stopAudio() async {
    try {
      await _audio?.stop();
    } catch (_) {}
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final t = current;
      if (!playing || t == null || t.hasAudio) return;
      position += 1;
      if (position >= t.seconds) {
        next();
        return;
      }
      notifyListeners();
    });
  }

  void _log() {
    final t = current;
    if (t == null || api.token == null) return;
    api.post('/wellness/events', {'kind': 'music', 'detail': t.category}).catchError((_) => <String, dynamic>{});
  }

  bool _disposed = false;

  // Loads and audio events can finish after the provider is gone (e.g. on sign-out).
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _audio?.dispose();
    super.dispose();
  }
}
