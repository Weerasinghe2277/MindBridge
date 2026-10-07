import 'package:flutter/material.dart';

import '../../modules/appointment/appointments.dart';
import '../../modules/article/articles.dart';
import '../../modules/mood/mood.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';
import '../wellness/music.dart';
import '../wellness/wellness_home.dart';
import 'home.dart';
import 'profile.dart';

class StudentShell extends StatelessWidget {
  const StudentShell({super.key});

  @override
  Widget build(BuildContext context) => RoleShell(
        aboveTabs: const MiniPlayer(),
        tabs: [
          ShellTab('home', 'home', 'Home', (_) => const StudentHome()),
          ShellTab('appts', 'event_note', 'Bookings', (_) => const MyAppointmentsScreen()),
          ShellTab('mood', 'mood', 'Mood', (_) => const MoodTrackerScreen()),
          ShellTab('well', 'spa', 'Wellness', (_) => const WellnessHome()),
          ShellTab('me', 'person', 'Profile', (_) => const StudentProfileScreen()),
        ],
      );
}

/// Opens the screen a student notification points to.
void openStudentLink(BuildContext context, Map<String, dynamic> link) {
  final id = link['id'] as String?;
  switch (link['screen']) {
    case 'appointment':
      if (id != null) push(context, AppointmentDetailScreen(id: id));
    case 'appointments':
      RoleShell.maybeOf(context)?.switchTo('appts');
    case 'article':
      if (id != null) push(context, ArticleDetailScreen(id: id));
    case 'checkin':
      push(context, const CheckInScreen(), root: true);
  }
}
