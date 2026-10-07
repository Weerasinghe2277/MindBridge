import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import 'ui.dart';

/// Standard MindBridge screen: header (back + title + actions), a scrolling
/// column of blocks with 14px gaps, and an optional sticky footer of actions.
class MbPage extends StatelessWidget {
  const MbPage({
    super.key,
    this.title,
    this.subtitle,
    this.root = false,
    this.actions = const [],
    this.bg = PageBg.normal,
    this.children = const [],
    this.foot = const [],
    this.footRow = false,
    this.footNote,
    this.onRefresh,
    this.bottom,
    this.scrollController,
    this.gap = 14,
    this.onBack,
  });

  final String? title;
  final String? subtitle;
  final bool root; // tab root: large serif title, no back button
  final List<HeaderAction> actions;
  final PageBg bg;
  final List<Widget> children;
  final List<Widget> foot;
  final bool footRow;
  final String? footNote;
  final Future<void> Function()? onRefresh;
  final Widget? bottom;
  final ScrollController? scrollController;
  final double gap;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final color = pageBg(bg);
    final canPop = Navigator.of(context).canPop();
    final showBack = title != null && !root && (canPop || onBack != null);
    Widget list = ListView.separated(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(18, title != null ? 4 : 8, 18, 24),
      itemCount: children.length,
      separatorBuilder: (_, _) => SizedBox(height: gap),
      itemBuilder: (_, i) => children[i],
    );
    if (onRefresh != null) list = RefreshIndicator(color: C.primary, onRefresh: onRefresh!, child: list);

    return Scaffold(
      backgroundColor: color,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(children: [
                  if (showBack)
                    HeaderActionButton(HeaderAction('arrow_back', tooltip: 'Back', onTap: onBack ?? () => Navigator.of(context).maybePop())),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: root ? 6 : (showBack ? 10 : 2)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: root ? Ty.lora(size: 25, spacing: -0.4) : Ty.nunito(size: 17, weight: FontWeight.w700, spacing: -0.25),
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.nunito(size: 12.5, color: C.muted)),
                      ]),
                    ),
                  ),
                  for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: HeaderActionButton(a)),
                ]),
              ),
            ),
          Expanded(child: list),
          if (foot.isNotEmpty) _Foot(foot: foot, row: footRow, note: footNote, bg: bg == PageBg.normal ? Colors.white : color),
          ?bottom,
        ]),
      ),
    );
  }
}

class _Foot extends StatelessWidget {
  const _Foot({required this.foot, required this.row, required this.note, required this.bg});
  final List<Widget> foot;
  final bool row;
  final String? note;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 14 + inset),
      decoration: BoxDecoration(color: bg, border: const Border(top: BorderSide(color: C.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ButtonGroup(foot, row: row),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!, textAlign: TextAlign.center, style: Ty.nunito(size: 12, color: C.muted2))),
      ]),
    );
  }
}

/// Loads data for a screen and shows the skeleton / offline / error states (NFR5).
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.skeleton, this.wrap});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Widget? skeleton;

  /// Wraps the loading / error state in a page (title, tabs…) so the screen doesn't jump.
  final Widget Function(Widget child)? wrap;

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? _data;
  ApiException? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> reload() => _run();

  @override
  Widget build(BuildContext context) {
    if (_data != null) return widget.builder(context, _data as T, reload);
    final wrap = widget.wrap ?? (c) => MbPage(children: [c]);
    if (_loading) return wrap(widget.skeleton ?? const LoadingList());
    return wrap(ErrorBlock(error: _error!, onRetry: () {
      setState(() => _loading = true);
      _run();
    }));
  }
}

class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.error, this.onRetry});
  final ApiException error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(children: [
        error.isNetwork
            ? const StateView(icon: 'wifi_off', tone: Tone.grey, title: 'You’re offline', text: 'Check your connection. Everything will refresh as soon as you’re back online.')
            : StateView(icon: 'error', tone: Tone.red, title: 'Something went wrong', text: error.message),
        if (onRetry != null) ...[const SizedBox(height: 18), MbButton('Try again', onPressed: onRetry, kind: BtnKind.secondary, icon: 'refresh')],
      ]);
}

// ─────────────────────────── Navigation & feedback ───────────────────────────

/// [name] tags routes that belong to one flow so the flow can be unwound as a group.
Future<T?> push<T>(BuildContext context, Widget page, {bool root = false, String? name}) =>
    Navigator.of(context, rootNavigator: root).push<T>(MaterialPageRoute(builder: (_) => page, settings: RouteSettings(name: name)));

/// Replaces the current flow with a result screen (e.g. booking success).
Future<T?> replace<T>(BuildContext context, Widget page, {bool root = false, String? name}) =>
    Navigator.of(context, rootNavigator: root).pushReplacement(MaterialPageRoute(builder: (_) => page, settings: RouteSettings(name: name)));

/// Pops every route tagged with [name] (the screens of one flow).
void popFlow(BuildContext context, String name) =>
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst || r.settings.name != name);

void popToFirst(BuildContext context, {bool root = false}) => Navigator.of(context, rootNavigator: root).popUntil((r) => r.isFirst);

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message)));
}

/// Runs an API action and shows its error message if it fails. Returns null on error.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } on ApiException catch (e) {
    if (context.mounted && !e.isSessionExpired) toast(context, e.message);
    return null;
  }
}

// ─────────────────────────── Bottom sheets ───────────────────────────

class SheetAction {
  const SheetAction(this.label, {this.kind = BtnKind.primary, this.run, this.value});
  final String label;
  final BtnKind kind;

  /// Optional async work; the sheet shows a spinner and closes when it returns true.
  final Future<bool> Function(String text)? run;
  final Object? value;
}

/// Confirmation sheet from the design (icon, title, text, optional detail rows,
/// optional text area, stacked buttons). Returns the tapped action's value.
Future<Object?> showMbSheet(
  BuildContext context, {
  required String icon,
  Tone tone = Tone.green,
  required String title,
  required String text,
  List<(String, String)> rows = const [],
  String? areaHint,
  required List<SheetAction> actions,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x730E1A14),
    builder: (_) => _Sheet(icon: icon, tone: tone, title: title, text: text, rows: rows, areaHint: areaHint, actions: actions),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.icon, required this.tone, required this.title, required this.text, required this.rows, required this.areaHint, required this.actions});
  final String icon;
  final Tone tone;
  final String title;
  final String text;
  final List<(String, String)> rows;
  final String? areaHint;
  final List<SheetAction> actions;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  final _area = TextEditingController();
  int? _busy;

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  Future<void> _tap(int i) async {
    final a = widget.actions[i];
    if (a.run == null) {
      Navigator.of(context).pop(a.value ?? a.label);
      return;
    }
    setState(() => _busy = i);
    bool ok = false;
    try {
      ok = await a.run!(_area.text.trim());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) Navigator.of(context).pop(a.value ?? a.label);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 10, 22, 26 + bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFFDCD4C4), borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 20),
          Align(alignment: Alignment.centerLeft, child: IconChip(widget.icon, tone: widget.tone, size: 58, iconSize: 29, radius: 19)),
          const SizedBox(height: 14),
          Text(widget.title, style: Ty.lora(size: 22, height: 1.25, spacing: -0.2)),
          const SizedBox(height: 6),
          Text(widget.text, style: Ty.nunito(size: 15, color: C.body2, height: 1.5)),
          if (widget.rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                for (var i = 0; i < widget.rows.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(border: i > 0 ? const Border(top: BorderSide(color: C.line)) : null),
                    child: Row(children: [
                      Text(widget.rows[i].$1, style: Ty.nunito(size: 14.5, color: C.muted)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(widget.rows[i].$2, textAlign: TextAlign.right, style: Ty.nunito(size: 14.5, weight: FontWeight.w700))),
                    ]),
                  ),
              ]),
            ),
          ],
          if (widget.areaHint != null) ...[
            const SizedBox(height: 14),
            MbField(controller: _area, hint: widget.areaHint, type: FieldType.area, rows: 3),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < widget.actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            MbButton(
              widget.actions[i].label,
              kind: widget.actions[i].kind,
              height: 52,
              fontSize: 15.5,
              loading: _busy == i,
              onPressed: _busy != null ? null : () => _tap(i),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Simple picker sheet used by select fields.
Future<String?> pickOption(BuildContext context, {required String title, required List<String> options, String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFFDCD4C4), borderRadius: BorderRadius.circular(3))),
          Padding(padding: const EdgeInsets.fromLTRB(22, 16, 22, 8), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: Ty.lora(size: 20)))),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
              for (final o in options)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  title: Text(o, style: Ty.nunito(size: 15, weight: o == current ? FontWeight.w700 : FontWeight.w500)),
                  trailing: o == current ? const MbIcon('check', color: C.primary) : null,
                  onTap: () => Navigator.of(ctx).pop(o),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}
