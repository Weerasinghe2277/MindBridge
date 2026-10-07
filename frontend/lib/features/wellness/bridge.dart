import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';
import '../student/counsellors.dart';
import 'emergency.dart';

/// M4-37 — sets expectations before the first message.
class BridgeIntroScreen extends StatelessWidget {
  const BridgeIntroScreen({super.key});

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Bridge',
        subtitle: 'AI wellness assistant',
        bg: PageBg.lilac,
        children: const [
          StateView(icon: 'forum', tone: Tone.lilac, title: 'Meet Bridge', text: 'A supportive space to talk things through, any time of day.', padding: EdgeInsets.fromLTRB(8, 8, 8, 4)),
          ChecksCard(title: 'Bridge can', [(true, 'Listen and help you sort your thoughts'), (true, 'Suggest breathing exercises and articles'), (true, 'Help you book a university counsellor')]),
          ChecksCard(title: 'Bridge can’t', [(false, 'Diagnose or give medical advice'), (false, 'Handle emergencies. Call 1926 for that')]),
          BannerCard(icon: 'lock', text: 'Chats are private and are not shared with counsellors. They’re deleted automatically after 30 days.'),
        ],
        foot: [MbButton('Start chatting', onPressed: () => replace(context, const BridgeChatScreen()))],
      );
}

/// M4-38 — live chat. Messages that suggest risk switch to crisis support (FR10 → FR8).
class BridgeChatScreen extends StatefulWidget {
  const BridgeChatScreen({super.key});

  @override
  State<BridgeChatScreen> createState() => _BridgeChatScreenState();
}

class _BridgeChatScreenState extends State<BridgeChatScreen> {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMsg> _msgs = [];
  bool _loading = true;
  bool _typing = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await api.get('/wellness/bridge');
      final list = (r['messages'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(list.map((m) => ChatMsg(m['from'] == 'me', m['text'] as String)));
        if (_msgs.isEmpty) _msgs.add(const ChatMsg(false, 'Hi, I’m Bridge. How are you feeling today?'));
        _loading = false;
        _error = null;
      });
      _toBottom();
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _send() async {
    final text = _draft.text.trim();
    if (text.isEmpty || _typing) return;
    _draft.clear();
    setState(() {
      _msgs.add(ChatMsg(true, text));
      _typing = true;
    });
    _toBottom();
    try {
      final r = await api.post('/wellness/bridge', {'text': text});
      if (!mounted) return;
      final reply = (r['reply'] as Map)['text'] as String;
      setState(() {
        _typing = false;
        _msgs.add(ChatMsg(false, reply));
      });
      _toBottom();
      if (r['escalate'] == true) push(context, BridgeEscalationScreen(userText: text, reply: reply), root: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _msgs.removeLast();
      });
      _draft.text = text;
      toast(context, e.message);
    }
  }

  Future<void> _clear() async {
    final r = await showMbSheet(context, icon: 'delete_sweep', tone: Tone.grey, title: 'Clear this chat?', text: 'Your messages with Bridge will be deleted from MindBridge.', actions: [
      SheetAction('Clear chat', kind: BtnKind.danger, run: (_) async {
        await api.delete('/wellness/bridge');
        return true;
      }),
      const SheetAction('Keep it', kind: BtnKind.ghost),
    ]);
    if (r == 'Clear chat') _load();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return MbPage(
      title: 'Bridge',
      subtitle: 'AI wellness assistant · private',
      scrollController: _scroll,
      actions: [
        HeaderAction('delete_sweep', tooltip: 'Clear chat', onTap: _clear),
        HeaderAction('sos', danger: true, tooltip: 'Crisis support', onTap: () => push(context, const SupportOptionsScreen(), root: true)),
      ],
      children: [
        if (_loading)
          const LoadingList(n: 2)
        else if (_error != null)
          ErrorBlock(error: _error!, onRetry: _load)
        else
          ChatBubbles(_msgs, typing: _typing),
        const Txt('Bridge is an AI and can make mistakes. In an emergency call 1926.', size: TxtSize.xs, align: TextAlign.center),
      ],
      bottom: Container(
        padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + (inset > 0 ? inset : 4)),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _draft,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              textCapitalization: TextCapitalization.sentences,
              style: Ty.nunito(size: 15),
              decoration: InputDecoration(
                hintText: 'Type how you’re feeling…',
                hintStyle: Ty.nunito(size: 15, color: C.muted4),
                filled: true,
                fillColor: C.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: const BorderSide(color: C.field)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: const BorderSide(color: C.field)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: const BorderSide(color: C.primary)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Send',
            child: Material(
              color: C.primary,
              shape: const CircleBorder(),
              child: InkWell(customBorder: const CircleBorder(), onTap: _send, child: const SizedBox(width: 46, height: 46, child: Center(child: MbIcon('arrow_upward', size: 22, color: Colors.white)))),
            ),
          ),
        ]),
      ),
    );
  }
}

/// M4-39
class BridgeEscalationScreen extends StatelessWidget {
  const BridgeEscalationScreen({super.key, required this.userText, required this.reply});
  final String userText;
  final String reply;

  @override
  Widget build(BuildContext context) => MbPage(
        title: 'Bridge',
        subtitle: 'AI wellness assistant',
        bg: PageBg.alert,
        children: [
          ChatBubbles([ChatMsg(true, userText), ChatMsg(false, reply)]),
          HeroCard(
            style: HeroStyle.alert,
            eyebrow: 'Talk to someone now',
            title: 'National Mental Health Helpline',
            sub: 'Call 1926. Free, confidential, 24 hours a day.',
            actions: [MbButton('Call 1926', kind: BtnKind.danger, icon: 'call', onPressed: () => callHelpline(context))],
          ),
          ListCards([
            ListItemData(icon: 'support_agent', tone: Tone.red, title: 'Other support options', sub: '1929, Medical Centre, campus security', onTap: () => push(context, const SupportOptionsScreen(), root: true)),
            ListItemData(icon: 'event_available', title: 'Book the earliest counsellor slot', sub: 'Sorted by next available time', onTap: () => push(context, const CounsellorListScreen(), root: true)),
          ]),
        ],
        foot: [MbButton('Back to chat', kind: BtnKind.ghost, onPressed: () => Navigator.of(context).pop())],
      );
}
