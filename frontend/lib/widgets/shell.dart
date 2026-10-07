import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'ui.dart';

class ShellTab {
  const ShellTab(this.key, this.icon, this.label, this.builder);
  final String key;
  final String icon;
  final String label;
  final WidgetBuilder builder;
}

/// Bottom-tab shell. Each tab keeps its own navigation stack, so the tab bar
/// stays visible while browsing inside a tab (as in the design).
class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.tabs, this.aboveTabs});
  final List<ShellTab> tabs;
  final Widget? aboveTabs;

  static RoleShellState of(BuildContext context) => context.findAncestorStateOfType<RoleShellState>()!;
  static RoleShellState? maybeOf(BuildContext context) => context.findAncestorStateOfType<RoleShellState>();

  @override
  State<RoleShell> createState() => RoleShellState();
}

class RoleShellState extends State<RoleShell> {
  int index = 0;
  late final List<GlobalKey<NavigatorState>> _keys = [for (final _ in widget.tabs) GlobalKey<NavigatorState>()];
  final Set<int> _built = {0};

  /// Switch to a tab by key. With [reset], the tab returns to its first screen.
  void switchTo(String key, {bool reset = true}) {
    final i = widget.tabs.indexWhere((t) => t.key == key);
    if (i < 0) return;
    if (reset) _keys[i].currentState?.popUntil((r) => r.isFirst);
    setState(() {
      index = i;
      _built.add(i);
    });
  }

  void _tap(int i) {
    if (i == index) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      index = i;
      _built.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _keys[index].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (index != 0) {
          setState(() => index = 0);
        }
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: Column(children: [
          Expanded(
            child: IndexedStack(index: index, children: [
              for (var i = 0; i < widget.tabs.length; i++)
                _built.contains(i)
                    ? HeroControllerScope.none(
                        child: Navigator(
                          key: _keys[i],
                          onGenerateRoute: (_) => MaterialPageRoute(builder: widget.tabs[i].builder),
                        ),
                      )
                    : const SizedBox(),
            ]),
          ),
          if (widget.aboveTabs != null) widget.aboveTabs!,
          Container(
            padding: EdgeInsets.fromLTRB(6, 8, 6, inset > 0 ? inset : 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
            child: Row(children: [
              for (var i = 0; i < widget.tabs.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: widget.tabs[i].label,
                    child: InkResponse(
                      onTap: () => _tap(i),
                      radius: 36,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56,
                          height: 30,
                          decoration: BoxDecoration(color: i == index ? C.selected : Colors.transparent, borderRadius: BorderRadius.circular(15)),
                          alignment: Alignment.center,
                          child: MbIcon(widget.tabs[i].icon, size: 22, fill: i == index, color: i == index ? C.dark : C.muted3),
                        ),
                        const SizedBox(height: 3),
                        Text(widget.tabs[i].label, maxLines: 1, style: Ty.nunito(size: 11, weight: FontWeight.w700, color: i == index ? C.dark : C.muted3)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
