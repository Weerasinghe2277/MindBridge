import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../modules/appointment/appointments.dart';
import '../../modules/appointment/booking.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

class CounsellorFilter {
  String available = 'any'; // any | today | week
  Set<String> modes = {};
  Set<String> focus = {};
  Set<String> languages = {};
  String gender = '';

  bool get active => available != 'any' || modes.isNotEmpty || focus.isNotEmpty || languages.isNotEmpty || gender.isNotEmpty;

  CounsellorFilter copy() => CounsellorFilter()
    ..available = available
    ..modes = {...modes}
    ..focus = {...focus}
    ..languages = {...languages}
    ..gender = gender;

  Map<String, dynamic> query(String q) => {
        'q': q,
        'available': available == 'any' ? '' : available,
        'mode': modes.join(','),
        'focus': focus.join(','),
        'language': languages.join(','),
        'gender': gender,
      };
}

String nextLabel(Map<String, dynamic>? next) {
  if (next == null) return 'No openings in the next 3 weeks';
  final s = next['start'];
  return 'Next: ${Fmt.relDay(s) ?? Fmt.day(s)} ${Fmt.time(s)}';
}

/// M1-06 — counsellors sorted by next available slot (FR2).
class CounsellorListScreen extends StatefulWidget {
  const CounsellorListScreen({super.key});

  @override
  State<CounsellorListScreen> createState() => _CounsellorListScreenState();
}

class _CounsellorListScreenState extends State<CounsellorListScreen> {
  final _search = TextEditingController();
  var _filter = CounsellorFilter();
  int _chip = 0;
  Timer? _debounce;
  List<Map<String, dynamic>>? _list;
  ApiException? _error;
  int _req = 0;

  static const _chips = ['All', 'Available today', 'Online', 'In person', 'Stress', 'Academic'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  CounsellorFilter get _effective {
    final f = _filter.copy();
    switch (_chip) {
      case 1:
        f.available = 'today';
      case 2:
        f.modes = {'online'};
      case 3:
        f.modes = {'in_person'};
      case 4:
        f.focus = {...f.focus, 'Stress'};
      case 5:
        f.focus = {...f.focus, 'Academic'};
    }
    return f;
  }

  Future<void> _load() async {
    final id = ++_req;
    setState(() => _error = null);
    try {
      final r = await api.get('/counsellors', query: _effective.query(_search.text.trim()));
      if (!mounted || id != _req) return;
      setState(() => _list = (r['counsellors'] as List).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted && id == _req) setState(() => _error = e);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return MbPage(
      title: 'Find a counsellor',
      onRefresh: _load,
      children: [
        SearchBox(
          controller: _search,
          hint: 'Search by name or focus area',
          onChanged: _onSearch,
          filterActive: _filter.active,
          onFilter: () async {
            final f = await push<CounsellorFilter>(context, CounsellorFiltersScreen(initial: _filter), root: true);
            if (f != null) {
              setState(() {
                _filter = f;
                _list = null;
              });
              _load();
            }
          },
        ),
        Chips(items: _chips, selected: {_chip}, onTap: (i) {
          setState(() {
            _chip = i;
            _list = null;
          });
          _load();
        }),
        if (_error != null)
          ErrorBlock(error: _error!, onRetry: _load)
        else if (list == null)
          const LoadingList()
        else if (list.isEmpty) ...[
          const StateView(icon: 'person_search', tone: Tone.grey, title: 'No counsellors match', text: 'Try a broader topic or remove a filter.'),
          MbButton('Clear search', kind: BtnKind.secondary, onPressed: () {
            _search.clear();
            setState(() {
              _filter = CounsellorFilter();
              _chip = 0;
              _list = null;
            });
            _load();
          }),
        ] else ...[
          Txt('${list.length} counsellor${list.length == 1 ? '' : 's'} · sorted by next available', size: TxtSize.sm),
          ListCards([
            for (final c in list)
              ListItemData(
                avatar: c['initials'] as String,
                avatarUrl: c['photoUrl'] as String?,
                title: c['name'] as String,
                sub: [c['title'], ((c['focusAreas'] as List?) ?? []).take(2).join(', ')].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
                meta: nextLabel(c['next'] as Map<String, dynamic>?),
                badge: switch (c['next'] == null ? null : Fmt.relDay(c['next']['start'])) { 'Today' => 'Today', 'Tomorrow' => 'Tomorrow', _ => null },
                badgeTone: c['next'] != null && Fmt.relDay(c['next']['start']) == 'Tomorrow' ? Tone.blue : Tone.green,
                onTap: () => push(context, CounsellorProfileScreen(id: c['id'] as String)),
              ),
          ]),
        ],
      ],
    );
  }
}

/// M1-07 — filters.
class CounsellorFiltersScreen extends StatefulWidget {
  const CounsellorFiltersScreen({super.key, required this.initial});
  final CounsellorFilter initial;

  @override
  State<CounsellorFiltersScreen> createState() => _CounsellorFiltersScreenState();
}

class _CounsellorFiltersScreenState extends State<CounsellorFiltersScreen> {
  late var f = widget.initial.copy();
  static const _avail = ['any', 'today', 'week'];
  static const _modes = ['online', 'in_person'];
  static const _focus = ['Stress', 'Anxiety', 'Academic pressure', 'Relationships', 'Sleep', 'Homesickness', 'Low mood'];
  static const _langs = ['English', 'Sinhala', 'Tamil'];
  static const _genders = ['', 'female', 'male'];

  Set<int> _idx<T>(List<T> all, Set<T> sel) => {for (var i = 0; i < all.length; i++) if (sel.contains(all[i])) i};
  void _toggle<T>(Set<T> s, T v) => s.contains(v) ? s.remove(v) : s.add(v);

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Filters',
        bg: PageBg.white,
        children: [
          const SectionHeader('Availability'),
          Chips(wrap: true, items: const ['Any time', 'Today', 'This week'], selected: {_avail.indexOf(f.available)}, onTap: (i) => setState(() => f.available = _avail[i])),
          const SectionHeader('Meeting type'),
          Chips(wrap: true, items: const ['Online', 'In person'], selected: _idx(_modes, f.modes), onTap: (i) => setState(() => _toggle(f.modes, _modes[i]))),
          const SectionHeader('Focus area'),
          Chips(wrap: true, items: _focus, selected: _idx(_focus, f.focus), onTap: (i) => setState(() => _toggle(f.focus, _focus[i]))),
          const SectionHeader('Language'),
          Chips(wrap: true, items: _langs, selected: _idx(_langs, f.languages), onTap: (i) => setState(() => _toggle(f.languages, _langs[i]))),
          const SectionHeader('Counsellor gender'),
          Chips(wrap: true, items: const ['No preference', 'Female', 'Male'], selected: {_genders.indexOf(f.gender)}, onTap: (i) => setState(() => f.gender = _genders[i])),
        ],
        footRow: true,
        foot: [
          MbButton('Reset', kind: BtnKind.secondary, onPressed: () => setState(() => f = CounsellorFilter())),
          MbButton('Show results', onPressed: () => Navigator.of(context).pop(f)),
        ],
      );
}

/// M1-08 — counsellor profile with the next free slots.
class CounsellorProfileScreen extends StatefulWidget {
  const CounsellorProfileScreen({super.key, required this.id});
  final String id;

  @override
  State<CounsellorProfileScreen> createState() => _CounsellorProfileScreenState();
}

class _CounsellorProfileScreenState extends State<CounsellorProfileScreen> {
  int? _slot;
  bool? _fav;

  /// FR7 — before starting a booking, make sure the student has no other active one.
  Future<bool> _checkNoActiveBooking() async {
    final r = await guard(context, () => api.get('/appointments/active-check'));
    if (r == null || !mounted) return false;
    final existing = r['existing'] as Map<String, dynamic>?;
    if (existing == null || r['blocking'] != true) return true;
    await showDuplicateSheet(context, Appointment(existing));
    return false;
  }

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/counsellors/${widget.id}'),
        wrap: (c) => MbPage(title: 'Counsellor', children: [c]),
        builder: (context, d, reload) {
          final c = d['counsellor'] as Map<String, dynamic>;
          final slots = (d['nextSlots'] as List).cast<Map<String, dynamic>>();
          final fav = _fav ?? c['favorite'] == true;
          final modes = (c['modes'] as List).cast<String>();
          final langs = (c['languages'] as List).cast<String>();
          final abbrev = {'English': 'EN', 'Sinhala': 'SI', 'Tamil': 'TA'};
          return MbPage(
            title: 'Counsellor',
            onRefresh: reload,
            actions: [
              HeaderAction(fav ? 'favorite' : 'favorite_border', tooltip: fav ? 'Remove from favourites' : 'Save to favourites', onTap: () async {
                final r = await guard(context, () => api.post('/counsellors/${widget.id}/favorite'));
                if (r != null) setState(() => _fav = r['favorite'] == true);
              }),
            ],
            children: [
              ProfileHeader(
                initials: c['initials'] as String,
                photoUrl: c['photoUrl'] as String?,
                name: c['name'] as String,
                sub: [c['title'], if (c['experienceYears'] != null) '${c['experienceYears']} years’ experience'].whereType<String>().join(' · '),
                badge: 'Verified by Student Affairs',
              ),
              StatsGrid(cols: 3, [
                StatItem('${c['sessionLength']} min', 'Per session'),
                StatItem(modes.length == 2 ? 'Both' : modeLabel(modes.first), modes.length == 2 ? 'Online & in person' : 'Meeting type'),
                StatItem(langs.map((l) => abbrev[l] ?? l).join(' · '), 'Languages'),
              ]),
              if ((c['about'] as String).isNotEmpty) ...[const SectionHeader('About'), Txt(c['about'] as String)],
              if ((c['focusAreas'] as List).isNotEmpty) ...[const SectionHeader('Focus areas'), Tags((c['focusAreas'] as List).cast<String>())],
              SectionHeader('Next available', link: 'Full calendar', onLink: () async {
                if (await _checkNoActiveBooking() && context.mounted) push(context, BookDateScreen(draft: BookingDraft(c)), root: true, name: 'book');
              }),
              if (slots.isEmpty)
                const BannerCard(tone: Tone.amber, icon: 'event_busy', text: 'No openings in the next three weeks. Try another counsellor or check back soon.')
              else
                SlotsGrid(
                  labels: [for (final s in slots) '${Fmt.relDay(s['start']) ?? Fmt.day(s['start']).split(',').first} ${Fmt.hhmm(s['time'] as String)}'],
                  disabled: const {},
                  selected: _slot,
                  onSelect: (i) => setState(() => _slot = i),
                ),
            ],
            foot: [
              MbButton(_slot == null ? 'Check availability' : 'Continue with this time', onPressed: () async {
                if (!await _checkNoActiveBooking() || !context.mounted) return;
                final draft = BookingDraft(c);
                if (_slot != null) {
                  final s = slots[_slot!];
                  draft
                    ..date = Fmt.dateStr(Fmt.sl(Fmt.parse(s['start'])))
                    ..slot = s;
                  push(context, BookMeetingScreen(draft: draft), root: true, name: 'book');
                } else {
                  push(context, BookDateScreen(draft: draft), root: true, name: 'book');
                }
              }),
            ],
          );
        },
      );
}

/// M1-13 — duplicate booking warning (FR7).
Future<void> showDuplicateSheet(BuildContext context, Appointment existing) async {
  final r = await showMbSheet(
    context,
    icon: 'warning',
    tone: Tone.amber,
    title: 'You already have an active booking',
    text: 'You have a ${existing.statusLabel.toLowerCase()} booking with ${existing.counsellorName}. Booking again would hold a second slot another student could use.',
    rows: [('Existing', Fmt.dateTime(existing.start)), ('Status', existing.statusLabel)],
    actions: [
      if (existing.canChange) const SheetAction('Reschedule existing booking', value: 'reschedule'),
      const SheetAction('View my booking', kind: BtnKind.secondary, value: 'view'),
      const SheetAction('Close', kind: BtnKind.ghost, value: 'close'),
    ],
  );
  if (!context.mounted) return;
  if (r == 'reschedule') push(context, RescheduleScreen(appointment: existing), root: true, name: 'resched');
  if (r == 'view') push(context, AppointmentDetailScreen(id: existing.id), root: true);
}
