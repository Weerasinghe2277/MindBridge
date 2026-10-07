import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/notifications.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

/// Shared notifications screen (M1-24, M2-44, M4-18, M3-50). Each role passes
/// a handler that opens the screen a notification links to.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.onOpen, this.emptyText = 'Booking updates and reminders will appear here.'});
  final void Function(BuildContext context, Map<String, dynamic> link) onOpen;
  final String emptyText;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _key = GlobalKey<LoaderState<List<Map<String, dynamic>>>>();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await api.get('/notifications');
    if (mounted) context.read<NotificationsState>().setUnread((r['unread'] as num).toInt());
    return (r['notifications'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _readAll() async {
    await guard(context, () => api.post('/notifications/read-all'));
    if (!mounted) return;
    context.read<NotificationsState>().setUnread(0);
    _key.currentState?.reload();
  }

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['read'] != true) {
      final notes = context.read<NotificationsState>();
      api.post('/notifications/${n['id']}/read').then((_) => notes.refresh()).catchError((_) {});
      n['read'] = true;
    }
    final link = n['link'] as Map<String, dynamic>?;
    if (link != null) widget.onOpen(context, link);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Loader<List<Map<String, dynamic>>>(
      key: _key,
      load: _load,
      wrap: (c) => MbPage(title: 'Notifications', children: [c]),
      builder: (context, list, reload) {
        final today = list.where((n) => Fmt.relDay(n['createdAt']) == 'Today').toList();
        final earlier = list.where((n) => Fmt.relDay(n['createdAt']) != 'Today').toList();
        final unread = list.any((n) => n['read'] != true);
        ListItemData item(Map<String, dynamic> n) => ListItemData(
              icon: n['icon'] as String? ?? 'notifications',
              tone: Tone.of(n['tone'] as String?),
              title: n['title'] as String,
              sub: n['body'] as String?,
              meta: Fmt.stamp(n['createdAt']),
              onTap: () => _open(n),
              trailing: n['read'] == true ? null : Container(width: 9, height: 9, margin: const EdgeInsets.only(left: 6), decoration: const BoxDecoration(color: C.dot, shape: BoxShape.circle)),
            );
        return MbPage(
          title: 'Notifications',
          actions: [if (unread) HeaderAction('done_all', tooltip: 'Mark all as read', onTap: _readAll)],
          onRefresh: reload,
          children: list.isEmpty
              ? [StateView(icon: 'notifications_off', tone: Tone.grey, title: 'You’re all caught up', text: widget.emptyText)]
              : [
                  if (today.isNotEmpty) ...[const SectionHeader('Today'), ListCards(today.map(item).toList())],
                  if (earlier.isNotEmpty) ...[const SectionHeader('Earlier'), ListCards(earlier.map(item).toList())],
                ],
        );
      },
    );
  }
}
