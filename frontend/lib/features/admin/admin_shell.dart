import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../modules/counsellor_approval/verification.dart';
import '../../modules/user/users.dart';
import '../../state/auth.dart';
import '../../state/notifications.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import '../common/notifications.dart';
import 'moderation.dart';
import 'reports.dart';
import 'system.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) => RoleShell(tabs: [
        ShellTab('home', 'dashboard', 'Home', (_) => const AdminDashboard()),
        ShellTab('users', 'group', 'Users', (_) => const UsersScreen()),
        ShellTab('ver', 'verified_user', 'Verify', (_) => const VerificationCenterScreen()),
        ShellTab('rep', 'bar_chart', 'Reports', (_) => const ReportsScreen()),
        ShellTab('sys', 'settings', 'System', (_) => const SystemScreen()),
      ]);
}

void openAdminLink(BuildContext context, Map<String, dynamic> link) {
  final id = link['id'] as String?;
  switch (link['screen']) {
    case 'verification':
      push(context, id == null ? const VerificationCenterScreen() : ApplicationScreen(id: id));
    case 'article_review':
      push(context, id == null ? const ModerationScreen() : ArticleReviewScreen(id: id));
  }
}


String logIcon(String? cat) => switch (cat) {
      'users' => 'manage_accounts',
      'verification' => 'verified',
      'articles' => 'article',
      'settings' => 'tune',
      'access' => 'visibility',
      'auth' => 'login',
      _ => 'history',
    };

Tone logTone(String? cat) => switch (cat) {
      'users' => Tone.blue,
      'articles' => Tone.amber,
      'settings' || 'auth' => Tone.grey,
      'access' => Tone.lilac,
      _ => Tone.green,
    };

ListItemData logItem(Map<String, dynamic> l) => ListItemData(
      icon: logIcon(l['category'] as String?),
      tone: logTone(l['category'] as String?),
      title: l['action'] as String,
      sub: [l['target'], if (l['actor'] != null) 'by ${l['actor']}'].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
      meta: Fmt.stamp(l['at']),
    );

/// M3-02 — pending work first, anonymous totals below. No session content ever.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final unread = context.watch<NotificationsState>().unread;
    final greet = Greet(
      eyebrow: 'Student Affairs',
      title: '${Fmt.greeting()}, ${auth.firstName}',
      actions: [HeaderAction('notifications', tooltip: 'Notifications', dot: unread > 0, onTap: () => push(context, const NotificationsScreen(onOpen: openAdminLink, emptyText: 'Applications, reviews and alerts will appear here.')))],
    );
    return Loader<Map<String, dynamic>>(
      load: () => api.get('/admin/dashboard'),
      wrap: (c) => MbPage(children: [greet, c]),
      builder: (context, d, reload) {
        final shell = RoleShell.maybeOf(context);
        final recent = (d['recent'] as List).cast<Map<String, dynamic>>();
        Future<void> open(Widget page) async {
          await push(context, page);
          reload();
        }

        return MbPage(
          onRefresh: reload,
          children: [
            greet,
            StatsGrid([
              StatItem('${d['pendingVerifications']}', 'Pending verifications', tone: (d['pendingVerifications'] as num) > 0 ? Tone.amber : null, onTap: () => shell?.switchTo('ver')),
              StatItem('${d['articlesToReview']}', 'Articles to review', tone: (d['articlesToReview'] as num) > 0 ? Tone.amber : null, onTap: () => open(const ModerationScreen())),
              StatItem('${d['activeStudents']}', 'Active students', onTap: () => shell?.switchTo('users')),
              StatItem('${d['sessionsThisMonth']}', 'Sessions this month', onTap: () => open(const ActivityOverviewScreen())),
            ]),
            SectionHeader('Quick actions', link: 'All', onLink: () => open(QuickActionsScreen(data: d))),
            ActionGrid(cols: 4, [
              GridItem('verified_user', 'Verify', onTap: () => shell?.switchTo('ver')),
              GridItem('group', 'Users', tone: Tone.blue, onTap: () => shell?.switchTo('users')),
              GridItem('bar_chart', 'Reports', tone: Tone.lilac, onTap: () => shell?.switchTo('rep')),
              GridItem('article', 'Articles', tone: Tone.amber, onTap: () => open(const ModerationScreen())),
            ]),
            SectionHeader('Recent activity', link: 'Overview', onLink: () => open(const ActivityOverviewScreen())),
            if (recent.isEmpty) const BannerCard(tone: Tone.grey, icon: 'history', text: 'No activity yet.') else ListCards(recent.map(logItem).toList()),
          ],
        );
      },
    );
  }
}

/// M3-03
class QuickActionsScreen extends StatelessWidget {
  const QuickActionsScreen({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final shell = RoleShell.maybeOf(context);
    return MbPage(
      title: 'Quick actions',
      children: [
        ActionGrid([
          GridItem('psychology', 'Review counsellors', sub: '${data['pendingCounsellors']} pending', onTap: () => push(context, const ApplicationListScreen(role: 'counsellor'))),
          GridItem('stethoscope', 'Review doctors', sub: '${data['pendingDoctors']} pending', tone: Tone.blue, onTap: () => push(context, const ApplicationListScreen(role: 'doctor'))),
          GridItem('group', 'Manage users', sub: '${data['totalUsers']} accounts', tone: Tone.lilac, onTap: () {
            Navigator.of(context).pop();
            shell?.switchTo('users');
          }),
          GridItem('admin_panel_settings', 'Roles & permissions', sub: '4 roles', tone: Tone.grey, onTap: () => push(context, const RolesScreen())),
          GridItem('article', 'Moderate articles', sub: '${data['articlesToReview']} waiting', tone: Tone.amber, onTap: () => push(context, const ModerationScreen())),
          GridItem('download', 'Export report', sub: Fmt.monthTitle(Fmt.nowSl().year, Fmt.nowSl().month).split(' ').first, onTap: () => push(context, const ReportExportScreen())),
        ]),
      ],
    );
  }
}

/// M3-04
class ActivityOverviewScreen extends StatelessWidget {
  const ActivityOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => Loader<Map<String, dynamic>>(
        load: () => api.get('/admin/activity'),
        wrap: (c) => MbPage(title: 'System activity', children: [c]),
        builder: (context, d, reload) {
          final week = (d['week'] as List).cast<Map<String, dynamic>>();
          final today = Fmt.nowSl().weekday - 1;
          return MbPage(
            title: 'System activity',
            onRefresh: reload,
            children: [
              StatsGrid(cols: 3, [
                StatItem('${d['bookingsToday']}', 'Bookings today'),
                StatItem(d['confirmedIn24hPct'] == null ? '—' : '${d['confirmedIn24hPct']}%', 'Confirmed in 24 h'),
                StatItem('${d['duplicatesFlagged']}', 'Duplicates flagged', tone: (d['duplicatesFlagged'] as num) > 0 ? Tone.red : null),
              ]),
              BarsChart(title: 'Booking requests this week', highlight: today, items: [for (final w in week) BarDatum(w['label'] as String, (w['value'] as num).toDouble(), text: '${w['value']}')]),
              const BannerCard(icon: 'visibility_off', text: 'No session content, notes or check-ins appear here.'),
              LinksRow([('Open full activity log', () => push(context, const ActivityLogScreen()))]),
            ],
          );
        },
      );
}
