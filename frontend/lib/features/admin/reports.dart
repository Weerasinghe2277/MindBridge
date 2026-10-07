import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../modules/counsellor_approval/verification.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// Shared date range for every report screen (FR12).
class ReportRange {
  ReportRange({this.preset = 'month', this.from, this.to});
  String preset; // month | last_month | semester | custom
  String? from;
  String? to;

  Map<String, dynamic> get query => preset == 'custom' && from != null && to != null ? {'from': from, 'to': to} : {'range': preset};
  String get label => switch (preset) {
        'last_month' => 'Last month',
        'semester' => 'This semester',
        'custom' => '${Fmt.shortDateStr(from!)} – ${Fmt.shortDateStr(to!)}',
        _ => 'This month',
      };
}

String _v(dynamic x, {String suffix = ''}) => x == null ? '<10' : '$x$suffix';

const _anon = BannerCard(icon: 'visibility_off', title: 'Anonymized', text: 'Aggregated data only. Groups smaller than 10 are hidden.');

/// M3-37 / M3-59
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _range = ReportRange();
  int _chip = 0;
  static const _presets = ['month', 'last_month', 'semester', 'custom'];

  Future<void> _pickRange() async {
    final r = await push<ReportRange>(context, DateRangeScreen(initial: _range), root: true);
    if (r != null) {
      setState(() {
        _range
          ..preset = r.preset
          ..from = r.from
          ..to = r.to;
        _chip = _presets.indexOf(r.preset);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chips = Chips(items: const ['This month', 'Last month', 'Semester', 'Custom'], selected: {_chip}, onTap: (i) {
      if (i == 3) {
        _pickRange();
        return;
      }
      setState(() {
        _chip = i;
        _range.preset = _presets[i];
      });
    });
    return Loader<Map<String, dynamic>>(
      key: ValueKey(_range.query.toString()),
      load: () => api.get('/admin/reports/overview', query: _range.query),
      wrap: (c) => MbPage(title: 'Reports', root: true, children: [chips, c]),
      builder: (context, d, reload) {
        final o = d['data'] as Map<String, dynamic>;
        Future<void> open(Widget page) => push(context, page);
        return MbPage(
          title: 'Reports',
          subtitle: (d['range'] as Map)['label'] as String,
          root: true,
          onRefresh: reload,
          actions: [HeaderAction('download', tooltip: 'Export report', onTap: () => open(ReportExportScreen(range: _range)))],
          children: [
            chips,
            Align(alignment: Alignment.centerLeft, child: TextLink('Choose date range', onTap: _pickRange)),
            if (o['enoughData'] != true)
              const StateView(icon: 'bar_chart', tone: Tone.grey, title: 'Not enough data yet', text: 'Reports appear once each group has at least 10 records, to keep everyone anonymous.')
            else
              StatsGrid([
                StatItem(_v(o['bookingRequests']), 'Booking requests', onTap: () => open(AppointmentStatsScreen(range: _range))),
                StatItem(_v(o['studentsSupported']), 'Students supported', onTap: () => open(ServiceUsageScreen(range: _range))),
                StatItem(_v(o['onlinePct'], suffix: '%'), 'Online sessions', onTap: () => open(TypeStatsScreen(range: _range))),
                StatItem(_v(o['moodCheckins']), 'Mood check-ins', onTap: () => open(WellnessUsageScreen(range: _range))),
              ]),
            MenuCard([
              MenuItemData('event_note', 'Appointment statistics', onTap: () => open(AppointmentStatsScreen(range: _range))),
              MenuItemData('devices', 'Online vs in person', onTap: () => open(TypeStatsScreen(range: _range))),
              MenuItemData('psychology', 'Counselling service usage', onTap: () => open(ServiceUsageScreen(range: _range))),
              MenuItemData('spa', 'Wellness usage', onTap: () => open(WellnessUsageScreen(range: _range))),
              MenuItemData('group', 'User statistics', onTap: () => open(const UserStatsScreen())),
            ]),
            _anon,
          ],
        );
      },
    );
  }
}

Widget _report(BuildContext context, {required String title, required String path, required ReportRange? range, required List<Widget> Function(Map<String, dynamic> d) build}) =>
    Loader<Map<String, dynamic>>(
      load: () => api.get('/admin/reports/$path', query: range?.query),
      wrap: (c) => MbPage(title: title, children: [c]),
      builder: (context, r, reload) => MbPage(title: title, subtitle: (r['range'] as Map)['label'] as String, onRefresh: reload, children: build(r['data'] as Map<String, dynamic>)),
    );

List<BarDatum> _bars(List l, {String suffix = ''}) => [for (final x in l) BarDatum(x['label'] as String, (x['value'] as num?)?.toDouble(), text: x['value'] == null ? '<10' : '${x['value']}$suffix')];

/// M3-38
class AppointmentStatsScreen extends StatelessWidget {
  const AppointmentStatsScreen({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context) => _report(context, title: 'Appointments', path: 'appointments', range: range, build: (d) {
        final weeks = d['weeks'] as List;
        return [
          StatsGrid([
            StatItem(_v(d['requests']), 'Requests'),
            StatItem(d['avgHoursToConfirm'] == null ? '<10' : '${d['avgHoursToConfirm']} h', 'Avg. time to confirm'),
            StatItem(_v(d['completed']), 'Completed'),
            StatItem(_v(d['duplicatePct'], suffix: '%'), 'Duplicates flagged', tone: Tone.red),
          ]),
          if (weeks.length > 1) BarsChart(title: 'Requests per week', highlight: weeks.length - 1, items: _bars(weeks)),
          HBarsChart(title: 'Outcomes', items: _bars(d['outcomes'] as List)),
          _anon,
        ];
      });
}

/// M3-39
class TypeStatsScreen extends StatelessWidget {
  const TypeStatsScreen({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context) => _report(context, title: 'Online vs in person', path: 'types', range: range, build: (d) => [
        HBarsChart(title: 'Share of sessions', max: 100, items: [
          BarDatum('Online', (d['onlinePct'] as num?)?.toDouble(), text: _v(d['onlinePct'], suffix: '%')),
          BarDatum('In person', (d['inPersonPct'] as num?)?.toDouble(), text: _v(d['inPersonPct'], suffix: '%')),
        ]),
        BarsChart(title: 'Online share by month', max: 100, highlight: 4, items: _bars(d['months'] as List, suffix: '%')),
        _anon,
      ]);
}

/// M3-40
class ServiceUsageScreen extends StatelessWidget {
  const ServiceUsageScreen({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context) => _report(context, title: 'Service usage', path: 'usage', range: range, build: (d) => [
        StatsGrid([StatItem(_v(d['uniqueStudents']), 'Unique students'), StatItem(_v(d['sessionsPerStudent']), 'Sessions per student')]),
        HBarsChart(title: 'Students by faculty', max: 100, items: _bars(d['faculties'] as List, suffix: '%')),
        _anon,
      ]);
}

/// M3-41
class WellnessUsageScreen extends StatelessWidget {
  const WellnessUsageScreen({super.key, required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context) => _report(context, title: 'Wellness usage', path: 'wellness', range: range, build: (d) => [
        HBarsChart(title: 'Feature use (sessions)', items: _bars(d['features'] as List)),
        StatsGrid([StatItem('${d['helplineTaps']}', 'Helpline taps (1926)', tone: Tone.red), StatItem('${d['escalations']}', 'Bridge escalations')]),
        const Txt('Safety figures are shown as totals only. They never identify who tapped or chatted.', size: TxtSize.xs),
        _anon,
      ]);
}

/// M3-42
class UserStatsScreen extends StatelessWidget {
  const UserStatsScreen({super.key});

  @override
  Widget build(BuildContext context) => _report(context, title: 'Users', path: 'users', range: null, build: (d) {
        final c = (d['counts'] as Map).cast<String, dynamic>();
        return [
          StatsGrid([StatItem('${c['student']}', 'Students'), StatItem('${c['counsellor']}', 'Counsellors'), StatItem('${c['doctor']}', 'Doctors'), StatItem('${c['admin']}', 'Admins')]),
          BarsChart(title: 'New student sign-ups', highlight: 4, items: _bars(d['signups'] as List)),
        ];
      });
}

/// M3-43
class DateRangeScreen extends StatefulWidget {
  const DateRangeScreen({super.key, required this.initial});
  final ReportRange initial;

  @override
  State<DateRangeScreen> createState() => _DateRangeScreenState();
}

class _DateRangeScreenState extends State<DateRangeScreen> {
  static const _presets = ['month', 'last_month', 'semester', 'custom'];
  late int _sel = _presets.indexOf(widget.initial.preset);
  late String _from = widget.initial.from ?? '${Fmt.todayStr().substring(0, 7)}-01';
  late String _to = widget.initial.to ?? Fmt.todayStr();

  Future<String?> _pick(String current) async {
    final d = await showDatePicker(context: context, initialDate: Fmt.fromDateStr(current), firstDate: DateTime(2024), lastDate: DateTime.now());
    return d == null ? null : Fmt.dateStr(DateTime.utc(d.year, d.month, d.day));
  }

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Date range',
        bg: PageBg.white,
        children: [
          OptionsList(items: const [OptionItem('This month'), OptionItem('Last month'), OptionItem('This semester', sub: 'Last 4 months'), OptionItem('Custom range')], selected: _sel, onSelect: (i) => setState(() => _sel = i)),
          if (_sel == 3) ...[
            MbField(label: 'From', type: FieldType.select, value: Fmt.longDateStr(_from), onTap: () async {
              final v = await _pick(_from);
              if (v != null) setState(() => _from = v);
            }),
            MbField(label: 'To', type: FieldType.select, value: Fmt.longDateStr(_to), error: _from.compareTo(_to) > 0 ? '“To” must be after “From”' : null, onTap: () async {
              final v = await _pick(_to);
              if (v != null) setState(() => _to = v);
            }),
          ],
        ],
        foot: [
          MbButton('Apply', onPressed: _sel == 3 && _from.compareTo(_to) > 0 ? null : () => Navigator.of(context).pop(ReportRange(preset: _presets[_sel], from: _sel == 3 ? _from : null, to: _sel == 3 ? _to : null))),
        ],
      );
}

/// M3-44 — PDF or CSV through a one-time download link.
class ReportExportScreen extends StatefulWidget {
  const ReportExportScreen({super.key, this.range});
  final ReportRange? range;

  @override
  State<ReportExportScreen> createState() => _ReportExportScreenState();
}

class _ReportExportScreenState extends State<ReportExportScreen> {
  int _fmt = 0;
  final Map<String, bool> _sections = {'appointments': true, 'usage': true, 'wellness': true, 'types': false, 'users': false};
  bool _busy = false;
  late final ReportRange _range = widget.range ?? ReportRange();

  static const _labels = {'appointments': 'Appointments', 'usage': 'Counselling usage', 'wellness': 'Wellness usage', 'types': 'Online vs in person', 'users': 'User statistics'};

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Export report',
        subtitle: _range.label,
        children: [
          const SectionHeader('Format'),
          OptionsList(items: const [OptionItem('PDF', sub: 'For sharing with management', icon: 'picture_as_pdf'), OptionItem('CSV', sub: 'For your own analysis', icon: 'table_chart')], selected: _fmt, onSelect: (i) => setState(() => _fmt = i)),
          const SectionHeader('Include'),
          for (final k in _sections.keys) ToggleTile(title: _labels[k]!, value: _sections[k]!, onChanged: (v) => setState(() => _sections[k] = v)),
          _anon,
        ],
        foot: [
          MbButton('Export ${_fmt == 0 ? 'PDF' : 'CSV'}', icon: 'download', loading: _busy, onPressed: !_sections.values.any((v) => v)
              ? null
              : () async {
                  setState(() => _busy = true);
                  await openDownload(context, {
                    'target': 'report',
                    'query': {
                      ..._range.query.map((k, v) => MapEntry(k, '$v')),
                      'format': _fmt == 0 ? 'pdf' : 'csv',
                      'sections': _sections.entries.where((e) => e.value).map((e) => e.key).join(','),
                    },
                  });
                  if (mounted) setState(() => _busy = false);
                }),
        ],
      );
}
