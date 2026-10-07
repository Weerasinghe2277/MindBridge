import '../widgets/ui.dart';
import 'format.dart';
import 'theme.dart';

/// Booking as returned by /api/appointments (same shape for student and counsellor, NFR5).
class Appointment {
  Appointment(this.j);
  final Map<String, dynamic> j;

  String get id => j['id'] as String;
  String get reference => j['reference'] as String? ?? '';
  DateTime get start => Fmt.parse(j['start']);
  DateTime get end => Fmt.parse(j['end']);
  String get mode => j['mode'] as String;
  bool get online => mode == 'online';
  String get modeLabel => online ? 'Online' : 'In person';
  String get location => j['location'] as String? ?? '';
  String? get meetingLink => j['meetingLink'] as String?;
  String get status => j['status'] as String;
  String get statusLabel => j['statusLabel'] as String;
  Tone get statusTone => Tone.of(j['statusTone'] as String?);
  bool get isActive => j['isActive'] == true;
  bool get duplicateFlag => j['duplicateFlag'] == true;
  bool get remindersOn => j['remindersOn'] == true;
  String get note => j['note'] as String? ?? '';
  Map<String, dynamic>? get proposal => j['proposal'] as Map<String, dynamic>?;
  Map<String, dynamic>? get decline => j['decline'] as Map<String, dynamic>?;
  Map<String, dynamic>? get cancel => j['cancel'] as Map<String, dynamic>?;
  Map<String, dynamic>? get session => j['session'] as Map<String, dynamic>?;
  Map<String, dynamic> get student => (j['student'] as Map<String, dynamic>?) ?? const {};
  Map<String, dynamic> get counsellor => (j['counsellor'] as Map<String, dynamic>?) ?? const {};
  String get counsellorName => counsellor['name'] as String? ?? '';
  String get studentName => student['name'] as String? ?? '';
  DateTime get createdAt => Fmt.parse(j['createdAt']);
  List<TimelineStep> get timeline => ((j['timeline'] as List?) ?? []).map((e) => TimelineStep.fromJson(e as Map<String, dynamic>)).toList();

  String get whenShort => Fmt.dateTime(start);
  String get timeRange => Fmt.timeRange(start, end);
  bool get isPast => end.isBefore(DateTime.now());
  bool get canChange => status == 'pending' || status == 'confirmed';

  static List<Appointment> list(dynamic l) => ((l as List?) ?? []).map((e) => Appointment(e as Map<String, dynamic>)).toList();
}

String modeLabel(String m) => m == 'online' ? 'Online' : 'In person';
