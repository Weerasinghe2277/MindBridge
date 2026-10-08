/// Date/time helpers. Every schedule in MindBridge is in Sri Lanka time (GMT+5:30,
/// no daylight saving), so we convert explicitly instead of relying on the device zone.
class Fmt {
  static const _offset = Duration(minutes: 330);
  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _wdLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _monLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  /// Wall-clock Sri Lanka time (fields read as local SL values).
  static DateTime sl(DateTime d) => d.toUtc().add(_offset);
  static DateTime parse(dynamic v) => v is DateTime ? v : DateTime.parse(v.toString());
  static DateTime nowSl() => sl(DateTime.now());

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String dateStr(DateTime slDate) => '${slDate.year}-${_two(slDate.month)}-${_two(slDate.day)}';
  static String todayStr() => dateStr(nowSl());
  static DateTime fromDateStr(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]);
  }

  static String addDays(String s, int n) => dateStr(fromDateStr(s).add(Duration(days: n)));

  static String time(dynamic iso) {
    final d = sl(parse(iso));
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// '09:30' -> '9:30'
  static String hhmm(String t) {
    final p = t.split(':');
    final h = int.parse(p[0]);
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${p[1]}';
  }

  static String hhmmAmPm(String t) {
    final h = int.parse(t.split(':')[0]);
    return '${hhmm(t)} ${h < 12 ? 'AM' : 'PM'}';
  }

  static String timeRange(dynamic start, dynamic end) {
    final a = time(start), b = time(end);
    final sameHalf = a.substring(a.length - 2) == b.substring(b.length - 2);
    return sameHalf ? '${a.substring(0, a.length - 3)} – $b' : '$a – $b';
  }

  /// 'Thu, 8 Oct'
  static String day(dynamic iso) {
    final d = sl(parse(iso));
    return '${_wd[d.weekday - 1]}, ${d.day} ${_mon[d.month - 1]}';
  }

  /// 'Thu, 8 Oct 2026'
  static String dayYear(dynamic iso) {
    final d = sl(parse(iso));
    return '${_wd[d.weekday - 1]}, ${d.day} ${_mon[d.month - 1]} ${d.year}';
  }

  /// 'Thu, 8 Oct · 10:30 AM' (with Today / Tomorrow where it helps)
  static String dateTime(dynamic iso, {bool relative = true}) {
    final label = relative ? relDay(iso) : null;
    return '${label ?? day(iso)} · ${time(iso)}';
  }

  static String? relDay(dynamic iso) {
    final s = dateStr(sl(parse(iso)));
    final t = todayStr();
    if (s == t) return 'Today';
    if (s == addDays(t, 1)) return 'Tomorrow';
    if (s == addDays(t, -1)) return 'Yesterday';
    return null;
  }

  /// For a 'YYYY-MM-DD' string: 'Thursday, 8 October'
  static String longDateStr(String s) {
    final d = fromDateStr(s);
    return '${_wdLong[d.weekday - 1]}, ${d.day} ${_monLong[d.month - 1]}';
  }

  static String shortDateStr(String s) {
    final d = fromDateStr(s);
    return '${_wd[d.weekday - 1]}, ${d.day} ${_mon[d.month - 1]}';
  }

  static String monthTitle(int year, int month) => '${_monLong[month - 1]} $year';

  static String todayLong() {
    final d = nowSl();
    return '${_wdLong[d.weekday - 1]}, ${d.day} ${_monLong[d.month - 1]}';
  }

  /// Notification-style stamp: '9:41 AM' today, 'Yesterday', 'Sat', '2 Oct'.
  static String stamp(dynamic iso) {
    final d = sl(parse(iso));
    final s = dateStr(d);
    final t = todayStr();
    if (s == t) return time(iso);
    if (s == addDays(t, -1)) return 'Yesterday';
    final diff = fromDateStr(t).difference(fromDateStr(s)).inDays;
    if (diff < 7) return _wd[d.weekday - 1];
    return '${d.day} ${_mon[d.month - 1]}';
  }

  static String ago(dynamic iso) {
    final diff = DateTime.now().difference(parse(iso));
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays} days ago';
  }

  static String greeting() {
    final h = nowSl().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String mmss(int seconds) => '${seconds ~/ 60}:${_two(seconds % 60)}';

  static String fileSize(num? bytes) {
    if (bytes == null) return '';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  static String startsIn(dynamic iso) {
    final m = parse(iso).difference(DateTime.now()).inMinutes;
    if (m <= 0) return 'Now';
    if (m < 60) return 'Starts in $m min';
    if (m < 60 * 24) return 'Starts in ${m ~/ 60} h ${m % 60} min';
    return dateTime(iso);
  }
}
