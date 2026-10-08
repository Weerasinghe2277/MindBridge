import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/icons.dart';
import '../core/theme.dart';

// ─────────────────────────── Primitives ───────────────────────────

class MbIcon extends StatelessWidget {
  const MbIcon(this.name, {super.key, this.size = 22, this.color, this.fill = false});
  final String name;
  final double size;
  final Color? color;
  final bool fill;

  @override
  Widget build(BuildContext context) => Icon(I(name), size: size, color: color, fill: fill ? 1 : 0, weight: 400, opticalSize: 24);
}

class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.size = 44, this.fontSize, this.photoUrl});
  final String initials;
  final double size;
  final double? fontSize;

  /// Profile photo; the initials show while it loads or if it can't be loaded.
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final c = avatarColors(initials);
    final letters = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c[0], shape: BoxShape.circle),
      child: Text(initials, style: Ty.nunito(size: fontSize ?? size * 0.34, weight: FontWeight.w700, color: c[1])),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return letters;
    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'Profile photo',
        loadingBuilder: (_, child, progress) => progress == null ? child : letters,
        errorBuilder: (_, _, _) => letters,
      ),
    );
  }
}

class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.tone = Tone.green, this.size = 44, this.iconSize = 22, this.radius = 14});
  final String icon;
  final Tone tone;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(radius)),
        alignment: Alignment.center,
        child: MbIcon(icon, size: iconSize, color: tone.fg),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.green, this.icon});
  final String text;
  final Tone tone;
  final String? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[MbIcon(icon!, size: 15, color: tone.fg), const SizedBox(width: 5)],
          Text(text, style: Ty.nunito(size: 11.5, weight: FontWeight.w700, color: tone.fg)),
        ]),
      );
}

/// Rounded surface used by most blocks (#FFFDF9 with a warm border).
class MbCard extends StatelessWidget {
  const MbCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 18, this.onTap, this.color = C.card, this.border = C.line, this.borderWidth = 1});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color color;
  final Color border;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return Material(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: br, side: BorderSide(color: border, width: borderWidth)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

// ─────────────────────────── Buttons ───────────────────────────

enum BtnKind { primary, secondary, soft, danger, dangerSoft, ghost, light, outlineLight }

class _BtnColors {
  const _BtnColors(this.bg, this.fg, this.border);
  final Color bg, fg, border;
}

_BtnColors _btn(BtnKind k) => switch (k) {
      BtnKind.primary => const _BtnColors(C.primary, Colors.white, C.primary),
      BtnKind.secondary => const _BtnColors(Colors.white, C.dark, Color(0xFFD8CFBE)),
      BtnKind.soft => const _BtnColors(C.softGreen, C.dark, C.softGreen),
      BtnKind.danger => const _BtnColors(C.danger, Colors.white, C.danger),
      BtnKind.dangerSoft => const _BtnColors(Color(0xFFFBE5E2), Color(0xFFA52B22), Color(0xFFFBE5E2)),
      BtnKind.ghost => const _BtnColors(Colors.transparent, C.primary, Colors.transparent),
      BtnKind.light => const _BtnColors(Colors.white, C.dark, Colors.white),
      BtnKind.outlineLight => const _BtnColors(Color(0x14FFFFFF), Colors.white, Color(0x73FFFFFF)),
    };

class MbButton extends StatelessWidget {
  const MbButton(this.label, {super.key, this.onPressed, this.kind = BtnKind.primary, this.icon, this.loading = false, this.height = 50, this.fontSize = 15});
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final String? icon;
  final bool loading;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = _btn(kind);
    final disabled = onPressed == null && !loading;
    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Material(
          color: c.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: loading ? null : onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: loading
                      ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.fg))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          if (icon != null) ...[MbIcon(icon!, size: 20, color: c.fg), const SizedBox(width: 8)],
                          Flexible(child: Text(label, textAlign: TextAlign.center, style: Ty.nunito(size: fontSize, weight: FontWeight.w700, color: c.fg))),
                        ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stack of buttons (column) or a row of equal-width buttons.
class ButtonGroup extends StatelessWidget {
  const ButtonGroup(this.buttons, {super.key, this.row = false});
  final List<Widget> buttons;
  final bool row;

  @override
  Widget build(BuildContext context) {
    if (row) {
      return Row(children: [
        for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: buttons[i])],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(height: 10), buttons[i]],
    ]);
  }
}

class HeaderAction {
  const HeaderAction(this.icon, {this.onTap, this.label, this.dot = false, this.danger = false, this.tooltip});
  final String icon;
  final VoidCallback? onTap;
  final String? label;
  final bool dot;
  final bool danger;
  final String? tooltip;
}

class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton(this.a, {super.key, this.size = 42});
  final HeaderAction a;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = a.danger ? const Color(0xFFFBE5E2) : Colors.white;
    final fg = a.danger ? C.danger : C.ink;
    final bd = a.danger ? const Color(0xFFF5CFC9) : C.line;
    return Tooltip(
      message: a.tooltip ?? a.label ?? a.icon.replaceAll('_', ' '),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(size == 44 ? 15 : 14), side: BorderSide(color: bd)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: a.onTap,
          child: SizedBox(
            height: size,
            child: Stack(clipBehavior: Clip.none, children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: a.label != null ? 11 : 0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: size, minHeight: size),
                  child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                    MbIcon(a.icon, size: size == 44 ? 22 : 21, color: fg),
                    if (a.label != null) ...[const SizedBox(width: 4), Text(a.label!, style: Ty.nunito(size: 13, weight: FontWeight.w800, color: fg))],
                  ]),
                ),
              ),
              if (a.dot)
                Positioned(
                  top: 9,
                  right: 10,
                  child: Container(width: 9, height: 9, decoration: BoxDecoration(color: C.dot, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, this.onTap, this.color = C.primary, this.size = 13.5, this.icon});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final String? icon;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: Ty.nunito(size: size, weight: FontWeight.w700, color: color)),
            if (icon != null) ...[const SizedBox(width: 4), MbIcon(icon!, size: 17, color: color)],
          ]),
        ),
      );
}

class LinksRow extends StatelessWidget {
  const LinksRow(this.links, {super.key, this.lead, this.align = WrapAlignment.center});
  final List<(String, VoidCallback?)> links;
  final String? lead;
  final WrapAlignment align;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: align,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 6,
        children: [
          if (lead != null) Text(lead!, style: Ty.nunito(size: 14, color: C.muted)),
          for (final l in links) TextLink(l.$1, onTap: l.$2, size: 14),
        ],
      );
}

// ─────────────────────────── Text blocks ───────────────────────────

class Greet extends StatelessWidget {
  const Greet({super.key, required this.eyebrow, required this.title, this.sub, this.actions = const []});
  final String eyebrow;
  final String title;
  final String? sub;
  final List<HeaderAction> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eyebrow, style: Ty.nunito(size: 13, weight: FontWeight.w600, color: C.muted)),
              const SizedBox(height: 2),
              Text(title, style: Ty.lora(size: 27, height: 1.15, spacing: -0.3), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub!, style: Ty.nunito(size: 14, color: C.muted))),
            ]),
          ),
          for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: HeaderActionButton(a, size: 44)),
        ]),
      );
}

class LogoBlock extends StatelessWidget {
  const LogoBlock({super.key, required this.title, this.sub, this.padding = const EdgeInsets.fromLTRB(0, 26, 0, 8)});
  final String title;
  final String? sub;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(children: [
          const MindBridgeMark(),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: Ty.lora(size: 29, spacing: -0.3)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub!, textAlign: TextAlign.center, style: Ty.nunito(size: 14.5, color: C.muted, height: 1.45))),
        ]),
      );
}

/// The MindBridge logo (two people, a brain and a bridge) on a white tile, matching the app icon.
/// Image: assets/images/logo.png, generated from tool/icon/logo.svg.
class MindBridgeMark extends StatelessWidget {
  const MindBridgeMark({super.key, this.size = 76});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * .26),
          border: Border.all(color: const Color(0xFFE4ECE6)),
          boxShadow: [BoxShadow(color: const Color(0xFF1E6E8C).withValues(alpha: .08), blurRadius: size * .3, offset: Offset(0, size * .04))],
        ),
        child: Image.asset('assets/images/logo.png', semanticLabel: 'MindBridge logo', filterQuality: FilterQuality.medium),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.link, this.onLink});
  final String text;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Semantics(header: true, child: Text(text, style: Ty.nunito(size: 16, weight: FontWeight.w700, spacing: -0.15)))),
          if (link != null) TextLink(link!, onTap: onLink),
        ]),
      );
}

enum TxtSize { xl, lg, md, sm, xs }

class Txt extends StatelessWidget {
  const Txt(this.text, {super.key, this.size = TxtSize.md, this.align = TextAlign.left, this.color, this.weight});
  final String text;
  final TxtSize size;
  final TextAlign align;
  final Color? color;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) {
    final s = switch (size) { TxtSize.xl => Ty.xl, TxtSize.lg => Ty.lg, TxtSize.md => Ty.md, TxtSize.sm => Ty.sm, TxtSize.xs => Ty.xs };
    return Text(text, textAlign: align, style: s.copyWith(color: color, fontWeight: weight));
  }
}

class DividerText extends StatelessWidget {
  const DividerText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Divider(color: Color(0xFFE6DFD1), height: 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(text, style: Ty.nunito(size: 13, color: C.muted4))),
        const Expanded(child: Divider(color: Color(0xFFE6DFD1), height: 1)),
      ]);
}

// ─────────────────────────── Cards & lists ───────────────────────────

class ListItemData {
  const ListItemData({required this.title, this.sub, this.meta, this.avatar, this.avatarUrl, this.icon, this.tone = Tone.green, this.badge, this.badgeTone = Tone.green, this.onTap, this.trailing});
  final String title;
  final String? sub;
  final String? meta;
  final String? avatar;
  final String? avatarUrl; // profile photo shown instead of the initials
  final String? icon;
  final Tone tone;
  final String? badge;
  final Tone badgeTone;
  final VoidCallback? onTap;
  final Widget? trailing;
}

class ListTileCard extends StatelessWidget {
  const ListTileCard(this.d, {super.key});
  final ListItemData d;

  @override
  Widget build(BuildContext context) => MbCard(
        padding: const EdgeInsets.all(14),
        onTap: d.onTap,
        child: Row(children: [
          if (d.avatar != null) ...[Avatar(d.avatar!, photoUrl: d.avatarUrl), const SizedBox(width: 12)],
          if (d.icon != null) ...[IconChip(d.icon!, tone: d.tone), const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.title, style: Ty.nunito(size: 15, weight: FontWeight.w700, height: 1.3)),
              if (d.sub != null && d.sub!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(d.sub!, style: Ty.nunito(size: 13, color: C.muted, height: 1.4))),
              if (d.meta != null && d.meta!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(d.meta!, style: Ty.nunito(size: 12, weight: FontWeight.w700, color: C.primary))),
            ]),
          ),
          if (d.trailing != null) d.trailing!,
          if (d.badge != null) ...[const SizedBox(width: 8), Align(alignment: Alignment.topCenter, child: Pill(d.badge!, tone: d.badgeTone))],
          if (d.onTap != null && d.badge == null && d.trailing == null) const MbIcon('chevron_right', size: 20, color: C.chevron),
        ]),
      );
}

class ListCards extends StatelessWidget {
  const ListCards(this.items, {super.key});
  final List<ListItemData> items;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 10), ListTileCard(items[i])],
      ]);
}

class MenuItemData {
  const MenuItemData(this.icon, this.title, {this.sub, this.value, this.danger = false, this.onTap});
  final String icon;
  final String title;
  final String? sub;
  final String? value;
  final bool danger;
  final VoidCallback? onTap;
}

class MenuCard extends StatelessWidget {
  const MenuCard(this.items, {super.key, this.title});
  final List<MenuItemData> items;
  final String? title;

  @override
  Widget build(BuildContext context) => MbCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text(title!.toUpperCase(), style: Ty.eyebrow)),
          for (var i = 0; i < items.length; i++)
            InkWell(
              onTap: items[i].onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(border: i > 0 ? const Border(top: BorderSide(color: C.line2)) : null),
                child: Row(children: [
                  MbIcon(items[i].icon, size: 21, color: items[i].danger ? C.dangerText : C.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(items[i].title, style: Ty.nunito(size: 15, weight: FontWeight.w600, color: items[i].danger ? C.dangerText : C.ink)),
                      if (items[i].sub != null) Text(items[i].sub!, style: Ty.nunito(size: 12.5, color: C.muted)),
                    ]),
                  ),
                  if (items[i].value != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text(items[i].value!, style: Ty.nunito(size: 13, color: C.muted))),
                  const MbIcon('chevron_right', size: 20, color: C.chevron),
                ]),
              ),
            ),
        ]),
      );
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, this.style = HeroStyle.dark, required this.eyebrow, required this.title, this.sub, this.badge, this.badgeTone = Tone.green, this.rows = const [], this.actions = const [], this.onTap});
  final HeroStyle style;
  final String eyebrow;
  final String title;
  final String? sub;
  final String? badge;
  final Tone badgeTone;
  final List<(String, String)> rows;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final h = HeroColors.of(style);
    return Material(
      color: h.bg,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(eyebrow.toUpperCase(), style: Ty.nunito(size: 11.5, weight: FontWeight.w800, color: h.muted, spacing: 0.8))),
              if (badge != null) Pill(badge!, tone: badgeTone),
            ]),
            const SizedBox(height: 12),
            Text(title, style: Ty.lora(size: 21, color: h.fg, height: 1.2)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub!, style: Ty.nunito(size: 14, color: h.muted, height: 1.45))),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    MbIcon(r.$1, size: 19, color: h.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.$2, style: Ty.nunito(size: 14, weight: FontWeight.w600, color: h.fg))),
                  ]),
                ),
            ],
            if (actions.isNotEmpty) ...[
              SizedBox(height: rows.isNotEmpty ? 4 : 14),
              Row(children: [
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: actions[i])],
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class KvCard extends StatelessWidget {
  const KvCard(this.rows, {super.key, this.title});
  final List<(String, String)> rows;
  final String? title;

  @override
  Widget build(BuildContext context) => MbCard(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) Padding(padding: const EdgeInsets.only(top: 13, bottom: 3), child: Text(title!.toUpperCase(), style: Ty.eyebrow)),
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: (i > 0 || title != null) ? const Border(top: BorderSide(color: C.line2)) : null),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rows[i].$1, style: Ty.nunito(size: 14.5, color: C.muted)),
                const SizedBox(width: 16),
                Expanded(child: Text(rows[i].$2, textAlign: TextAlign.right, style: Ty.nunito(size: 14.5, weight: FontWeight.w700))),
              ]),
            ),
        ]),
      );
}

class BannerCard extends StatelessWidget {
  const BannerCard({super.key, this.tone = Tone.green, required this.icon, this.title, this.text, this.link, this.onLink});
  final Tone tone;
  final String icon;
  final String? title;
  final String? text;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(18)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MbIcon(icon, size: 22, color: tone.fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) Text(title!, style: Ty.nunito(size: 14.5, weight: FontWeight.w700, color: tone.fg)),
              if (title != null && text != null) const SizedBox(height: 3),
              if (text != null) Text(text!, style: Ty.nunito(size: 13.5, color: C.ink2, height: 1.45)),
              if (link != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextLink(link!, onTap: onLink, color: tone.fg, icon: 'arrow_forward'),
                ),
            ]),
          ),
        ]),
      );
}

class StateView extends StatelessWidget {
  const StateView({super.key, required this.icon, this.tone = Tone.green, required this.title, required this.text, this.padding = const EdgeInsets.fromLTRB(8, 30, 8, 6)});
  final String icon;
  final Tone tone;
  final String title;
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Column(children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(30)),
            alignment: Alignment.center,
            child: MbIcon(icon, size: 44, color: tone.fg),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: Ty.lora(size: 24, height: 1.2, spacing: -0.2)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: Text(text, textAlign: TextAlign.center, style: Ty.nunito(size: 15, color: C.body2, height: 1.55)),
          ),
        ]),
      );
}

class StatItem {
  const StatItem(this.value, this.label, {this.tone, this.onTap});
  final String value;
  final String label;
  final Tone? tone;
  final VoidCallback? onTap;
}

class StatsGrid extends StatelessWidget {
  const StatsGrid(this.items, {super.key, this.cols = 2});
  final List<StatItem> items;
  final int cols;

  @override
  Widget build(BuildContext context) {
    final rows = <List<StatItem>>[];
    for (var i = 0; i < items.length; i += cols) {
      rows.add(items.sublist(i, (i + cols).clamp(0, items.length)));
    }
    return Column(children: [
      for (var r = 0; r < rows.length; r++) ...[
        if (r > 0) const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cols; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: i < rows[r].length
                    ? MbCard(
                        padding: const EdgeInsets.all(14),
                        onTap: rows[r][i].onTap,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(rows[r][i].value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.nunito(size: cols >= 3 ? 19 : 26, weight: FontWeight.w800, spacing: -0.5, color: rows[r][i].tone?.fg ?? C.ink)),
                          const SizedBox(height: 4),
                          Text(rows[r][i].label, style: Ty.nunito(size: 12.5, color: C.muted, height: 1.3)),
                        ]),
                      )
                    : const SizedBox(),
              ),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class GridItem {
  const GridItem(this.icon, this.label, {this.sub, this.tone = Tone.green, this.onTap});
  final String icon;
  final String label;
  final String? sub;
  final Tone tone;
  final VoidCallback? onTap;
}

class ActionGrid extends StatelessWidget {
  const ActionGrid(this.items, {super.key, this.cols = 2});
  final List<GridItem> items;
  final int cols;

  @override
  Widget build(BuildContext context) {
    final rows = <List<GridItem>>[];
    for (var i = 0; i < items.length; i += cols) {
      rows.add(items.sublist(i, (i + cols).clamp(0, items.length)));
    }
    final compact = cols >= 3;
    return Column(children: [
      for (var r = 0; r < rows.length; r++) ...[
        if (r > 0) const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cols; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: i < rows[r].length
                    ? MbCard(
                        padding: compact ? const EdgeInsets.fromLTRB(6, 14, 6, 12) : const EdgeInsets.all(14),
                        onTap: rows[r][i].onTap,
                        child: Column(crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
                          IconChip(rows[r][i].icon, tone: rows[r][i].tone, size: 42),
                          const SizedBox(height: 10),
                          Text(rows[r][i].label, textAlign: compact ? TextAlign.center : TextAlign.left, style: Ty.nunito(size: 13.5, weight: FontWeight.w700, height: 1.25)),
                          if (rows[r][i].sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(rows[r][i].sub!, style: Ty.nunito(size: 12, color: C.muted))),
                        ]),
                      )
                    : const SizedBox(),
              ),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class ChecksCard extends StatelessWidget {
  const ChecksCard(this.items, {super.key, this.title});
  final List<(bool, String)> items;
  final String? title;

  @override
  Widget build(BuildContext context) => MbCard(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(title!.toUpperCase(), style: Ty.eyebrow)),
          for (final c in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MbIcon(c.$1 ? 'check_circle' : 'cancel', size: 20, color: c.$1 ? C.primary : C.danger, fill: true),
                const SizedBox(width: 10),
                Expanded(child: Text(c.$2, style: Ty.nunito(size: 14.5, height: 1.4))),
              ]),
            ),
        ]),
      );
}

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.initials, required this.name, this.sub, this.badge, this.badgeTone = Tone.green, this.onAvatarTap, this.photoUrl, this.editable = false});
  final String initials;
  final String? photoUrl;

  /// Shows a camera badge so people know they can tap to change the photo.
  final bool editable;
  final String name;
  final String? sub;
  final String? badge;
  final Tone badgeTone;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final c = avatarColors(initials);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(children: [
        Semantics(
          button: onAvatarTap != null,
          label: editable ? 'Change profile photo' : null,
          child: GestureDetector(
            onTap: onAvatarTap,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c[0],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: const [BoxShadow(color: Color(0x1A14281E), blurRadius: 10, offset: Offset(0, 2))],
                ),
                child: photoUrl == null
                    ? Text(initials, style: Ty.nunito(size: 30, weight: FontWeight.w800, color: c[1]))
                    : Avatar(initials, size: 80, fontSize: 28, photoUrl: photoUrl),
              ),
              if (editable)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: C.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                    alignment: Alignment.center,
                    child: const MbIcon('photo_camera', size: 16, color: Colors.white),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(name, textAlign: TextAlign.center, style: Ty.lora(size: 21)),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(sub!, textAlign: TextAlign.center, style: Ty.nunito(size: 13.5, color: C.muted, height: 1.4))),
        if (badge != null) Padding(padding: const EdgeInsets.only(top: 8), child: Pill(badge!, tone: badgeTone, icon: 'verified')),
      ]),
    );
  }
}

class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({super.key, this.height = 180, this.icon = 'spa', this.tone = Tone.green, this.label});
  final double height;
  final String icon;
  final Tone tone;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tone.bg, Color.lerp(tone.bg, Colors.white, .55)!]),
          border: Border.all(color: C.field),
        ),
        child: Stack(children: [
          Positioned(right: -30, top: -30, child: Container(width: height * .9, height: height * .9, decoration: BoxDecoration(shape: BoxShape.circle, color: tone.fg.withValues(alpha: .07)))),
          Positioned(left: -20, bottom: -40, child: Container(width: height * .7, height: height * .7, decoration: BoxDecoration(shape: BoxShape.circle, color: tone.fg.withValues(alpha: .05)))),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MbIcon(icon, size: height * .28, color: tone.fg.withValues(alpha: .75)),
              if (label != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(label!, style: Ty.nunito(size: 12.5, weight: FontWeight.w700, color: tone.fg))),
            ]),
          ),
        ]),
      );
}

class LoadingList extends StatefulWidget {
  const LoadingList({super.key, this.n = 4});
  final int n;

  @override
  State<LoadingList> createState() => _LoadingListState();
}

class _LoadingListState extends State<LoadingList> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const widths = [0.7, 0.55, 0.62, 0.48, 0.66];
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: Tween(begin: 0.5, end: 1.0).animate(_c),
        child: Column(children: [
          for (var i = 0; i < widget.n; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: MbCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFFEAE4D8), shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(height: 12, width: c.maxWidth * widths[i % 5], decoration: BoxDecoration(color: const Color(0xFFEAE4D8), borderRadius: BorderRadius.circular(6))),
                        const SizedBox(height: 8),
                        Container(height: 10, width: c.maxWidth * .45, decoration: BoxDecoration(color: const Color(0xFFF2EDE3), borderRadius: BorderRadius.circular(5))),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────── Inputs ───────────────────────────

class Chips extends StatelessWidget {
  const Chips({super.key, required this.items, required this.selected, required this.onTap, this.wrap = false});
  final List<String> items;
  final Set<int> selected;
  final ValueChanged<int> onTap;
  final bool wrap;

  Widget _chip(int i) {
    final on = selected.contains(i);
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? C.dark : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: on ? C.dark : C.field)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(i),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(items[i], style: Ty.nunito(size: 13.5, weight: FontWeight.w700, color: on ? Colors.white : C.body)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (wrap) return Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < items.length; i++) _chip(i)]);
    return SizedBox(
      height: 36,
      child: OverflowBox(
        maxWidth: MediaQuery.sizeOf(context).width,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _chip(i),
        ),
      ),
    );
  }
}

class Tags extends StatelessWidget {
  const Tags(this.items, {super.key});
  final List<String> items;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(color: C.softGreen, borderRadius: BorderRadius.circular(999)),
            child: Text(t, style: Ty.nunito(size: 13, weight: FontWeight.w700, color: const Color(0xFF3A6647))),
          ),
      ]);
}

class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.index, required this.onChanged});
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: C.segBg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: i == index ? const [BoxShadow(color: Color(0x2414281E), blurRadius: 3, offset: Offset(0, 1))] : null,
                    ),
                    child: Text(items[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.nunito(size: 13.5, weight: FontWeight.w700, color: i == index ? C.ink : C.muted)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, this.controller, this.hint = 'Search', this.onChanged, this.onSubmitted, this.onFilter, this.filterActive = false});
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onFilter;
  final bool filterActive;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: C.card, border: Border.all(color: C.field), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const MbIcon('search', size: 21, color: C.muted3),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.search,
                  style: Ty.nunito(size: 15),
                  decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: hint, hintStyle: Ty.nunito(size: 15, color: C.muted4)),
                ),
              ),
            ]),
          ),
        ),
        if (onFilter != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Filters',
            child: Material(
              color: C.dark,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onFilter,
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(alignment: Alignment.center, children: [
                    const MbIcon('tune', size: 21, color: Colors.white),
                    if (filterActive) Positioned(top: 10, right: 10, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: C.leaf, shape: BoxShape.circle))),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]);
}

enum FieldType { text, password, area, select, email, phone, number }

class MbField extends StatefulWidget {
  const MbField({super.key, this.label, this.controller, this.hint, this.icon, this.type = FieldType.text, this.error, this.helper, this.enabled = true, this.onTap, this.value, this.rows = 4, this.onChanged, this.maxLength, this.autofill, this.textInputAction, this.onSubmitted, this.capitalization = TextCapitalization.none});
  final String? label;
  final TextEditingController? controller;
  final String? hint;
  final String? icon;
  final FieldType type;
  final String? error;
  final String? helper;
  final bool enabled;
  final VoidCallback? onTap; // for select fields
  final String? value; // for select fields
  final int rows;
  final ValueChanged<String>? onChanged;
  final int? maxLength;
  final Iterable<String>? autofill;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization capitalization;

  @override
  State<MbField> createState() => _MbFieldState();
}

class _MbFieldState extends State<MbField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final hasError = w.error != null && w.error!.isNotEmpty;
    final borderColor = hasError ? C.error : C.field;
    Widget input;
    if (w.type == FieldType.area) {
      input = TextField(
        controller: w.controller,
        enabled: w.enabled,
        minLines: w.rows,
        maxLines: w.rows + 4,
        maxLength: w.maxLength,
        onChanged: w.onChanged,
        textCapitalization: TextCapitalization.sentences,
        style: Ty.nunito(size: 15, height: 1.5),
        decoration: InputDecoration(
          hintText: w.hint,
          hintStyle: Ty.nunito(size: 15, color: C.muted4),
          counterText: '',
          filled: true,
          fillColor: w.enabled ? Colors.white : C.fieldDisabled,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor, width: 1.5)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.field, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: hasError ? C.error : C.primary, width: 1.5)),
        ),
      );
    } else {
      final isSelect = w.type == FieldType.select;
      final isPw = w.type == FieldType.password;
      input = Material(
        color: w.enabled ? Colors.white : C.fieldDisabled,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: borderColor, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isSelect && w.enabled ? w.onTap : null,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              if (w.icon != null) ...[MbIcon(w.icon!, size: 20, color: C.muted3), const SizedBox(width: 10)],
              Expanded(
                child: isSelect
                    ? Text(
                        (w.value == null || w.value!.isEmpty) ? (w.hint ?? 'Choose') : w.value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.nunito(size: 15, color: (w.value == null || w.value!.isEmpty) ? C.muted4 : (w.enabled ? C.ink : C.muted2)),
                      )
                    : TextField(
                        controller: w.controller,
                        enabled: w.enabled,
                        obscureText: isPw && _obscure,
                        onChanged: w.onChanged,
                        maxLength: w.maxLength,
                        autofillHints: w.autofill,
                        textInputAction: w.textInputAction,
                        onSubmitted: w.onSubmitted,
                        textCapitalization: w.capitalization,
                        keyboardType: switch (w.type) {
                          FieldType.email => TextInputType.emailAddress,
                          FieldType.phone => TextInputType.phone,
                          FieldType.number => TextInputType.number,
                          _ => TextInputType.text,
                        },
                        style: Ty.nunito(size: 15, color: w.enabled ? C.ink : C.muted2),
                        decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, counterText: '', hintText: w.hint, hintStyle: Ty.nunito(size: 15, color: C.muted4)),
                      ),
              ),
              if (isSelect) const MbIcon('expand_more', size: 20, color: C.muted3),
              if (isPw)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: MbIcon(_obscure ? 'visibility' : 'visibility_off', size: 20, color: C.muted3),
                ),
            ]),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (w.label != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(w.label!, style: Ty.nunito(size: 13.5, weight: FontWeight.w700, color: C.ink2))),
      input,
      if (hasError)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const MbIcon('error', size: 16, color: C.dangerText),
            const SizedBox(width: 6),
            Expanded(child: Text(w.error!, style: Ty.nunito(size: 12.5, weight: FontWeight.w600, color: C.dangerText))),
          ]),
        ),
      if (w.helper != null && !hasError) Padding(padding: const EdgeInsets.only(top: 6), child: Text(w.helper!, style: Ty.nunito(size: 12.5, color: C.muted2))),
    ]);
  }
}

class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.controller, this.onCompleted, this.length = 6});
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final int length;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    setState(() {});
    if (widget.controller.text.length == widget.length) widget.onCompleted?.call(widget.controller.text);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.controller.text;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(children: [
        Opacity(
          opacity: 0,
          child: SizedBox(
            height: 58,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: widget.length,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(counterText: ''),
            ),
          ),
        ),
        Semantics(
          label: 'Verification code, ${v.length} of ${widget.length} digits entered',
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Container(
                width: 48,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: (i < v.length || i == v.length) ? C.primary : C.field, width: 1.5),
                ),
                child: Text(i < v.length ? v[i] : '', style: Ty.nunito(size: 24, weight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class ToggleTile extends StatelessWidget {
  const ToggleTile({super.key, required this.title, this.sub, this.icon, required this.value, this.onChanged, this.locked = false});
  final String title;
  final String? sub;
  final String? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        enabled: !locked,
        label: title,
        child: MbCard(
          padding: const EdgeInsets.all(14),
          radius: 16,
          onTap: locked || onChanged == null ? null : () => onChanged!(!value),
          child: Row(children: [
            if (icon != null) ...[MbIcon(icon!, size: 21, color: C.primary), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Ty.nunito(size: 15, weight: FontWeight.w600)),
                if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: Ty.nunito(size: 12.5, color: C.muted, height: 1.4))),
              ]),
            ),
            const SizedBox(width: 10),
            Opacity(
              opacity: locked ? .6 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: value ? C.primary : C.track, borderRadius: BorderRadius.circular(14)),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))])),
                ),
              ),
            ),
          ]),
        ),
      );
}

class OptionItem {
  const OptionItem(this.title, {this.sub, this.icon});
  final String title;
  final String? sub;
  final String? icon;
}

class OptionsList extends StatelessWidget {
  const OptionsList({super.key, required this.items, required this.selected, required this.onSelect});
  final List<OptionItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Semantics(
            selected: i == selected,
            inMutuallyExclusiveGroup: true,
            child: MbCard(
              padding: const EdgeInsets.all(14),
              color: i == selected ? const Color(0xFFF1F5EA) : Colors.white,
              border: i == selected ? C.primary : C.line,
              borderWidth: 1.5,
              onTap: () => onSelect(i),
              child: Row(children: [
                if (items[i].icon != null) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: i == selected ? const Color(0xFFD6E3C8) : const Color(0xFFEFEFE4), borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: MbIcon(items[i].icon!, size: 22, color: C.dark),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(items[i].title, style: Ty.nunito(size: 15, weight: FontWeight.w700)),
                    if (items[i].sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(items[i].sub!, style: Ty.nunito(size: 13, color: C.muted, height: 1.4))),
                  ]),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: i == selected ? C.primary : const Color(0xFFCFC7B6), width: 2)),
                  alignment: Alignment.center,
                  child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: i == selected ? C.primary : Colors.transparent)),
                ),
              ]),
            ),
          ),
        ],
      ]);
}

class StepsBar extends StatelessWidget {
  const StepsBar({super.key, required this.n, required this.of, required this.label});
  final int n;
  final int of;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Step $n of $of, $label',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Step $n of $of', style: Ty.nunito(size: 12.5, weight: FontWeight.w700, color: C.primary)),
            const Spacer(),
            Text(label, style: Ty.nunito(size: 12.5, weight: FontWeight.w700, color: C.muted)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < of; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(child: Container(height: 5, decoration: BoxDecoration(color: i < n ? C.primary : C.field, borderRadius: BorderRadius.circular(3)))),
            ],
          ]),
        ]),
      );
}

class CompareCard extends StatelessWidget {
  const CompareCard({super.key, required this.fromLabel, required this.fromA, required this.fromB, required this.toLabel, required this.toA, required this.toB});
  final String fromLabel, fromA, fromB, toLabel, toA, toB;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MbCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fromLabel.toUpperCase(), style: Ty.eyebrow.copyWith(color: C.muted4)),
            const SizedBox(height: 4),
            Text(fromA, style: Ty.nunito(size: 16, weight: FontWeight.w700, color: C.muted3).copyWith(decoration: TextDecoration.lineThrough)),
            Text(fromB, style: Ty.nunito(size: 14, color: C.muted4).copyWith(decoration: TextDecoration.lineThrough)),
          ]),
        ),
        const SizedBox(height: 6),
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(color: C.softGreen, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.primary, width: 1.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(toLabel.toUpperCase(), style: Ty.eyebrow.copyWith(color: const Color(0xFF3A6647))),
              const SizedBox(height: 4),
              Text(toA, style: Ty.nunito(size: 17, weight: FontWeight.w800)),
              Text(toB, style: Ty.nunito(size: 14, color: C.ink2)),
            ]),
          ),
          Positioned(
            top: -20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: C.softGreen, shape: BoxShape.circle, border: Border.all(color: C.bg, width: 3)),
                alignment: Alignment.center,
                child: const MbIcon('arrow_downward', size: 18, color: C.dark),
              ),
            ),
          ),
        ]),
      ]);
}

class TimelineStep {
  const TimelineStep(this.label, {this.sub, this.state = 'todo'});
  final String label;
  final String? sub;
  final String state; // done | now | bad | todo

  factory TimelineStep.fromJson(Map<String, dynamic> j) => TimelineStep(j['label'] as String, sub: j['sub'] as String?, state: j['s'] as String? ?? 'todo');
}

class TimelineCard extends StatelessWidget {
  const TimelineCard(this.steps, {super.key});
  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) => MbCard(
        child: Column(children: [
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Column(children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (steps[i].state) { 'done' => C.primary, 'now' => C.markLow, 'bad' => C.danger, _ => Colors.white },
                      border: Border.all(color: steps[i].state == 'todo' ? C.track : Colors.transparent, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: steps[i].state == 'todo' ? null : MbIcon(switch (steps[i].state) { 'done' => 'check', 'now' => 'more_horiz', _ => 'close' }, size: 15, color: Colors.white),
                  ),
                  if (i < steps.length - 1)
                    Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), constraints: const BoxConstraints(minHeight: 16), color: steps[i].state == 'done' ? C.primary : C.field)),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 2, bottom: i == steps.length - 1 ? 0 : 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(steps[i].label, style: Ty.nunito(size: 14.5, weight: FontWeight.w700, color: steps[i].state == 'todo' ? C.muted4 : C.ink)),
                      if (steps[i].sub != null && steps[i].sub!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(steps[i].sub!, style: Ty.nunito(size: 12.5, color: C.muted2))),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      );
}

class SlotsGrid extends StatelessWidget {
  const SlotsGrid({super.key, required this.labels, required this.disabled, required this.selected, required this.onSelect});
  final List<String> labels;
  final Set<int> disabled;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final w = (c.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < labels.length; i++)
            Builder(builder: (_) {
              final off = disabled.contains(i);
              final on = selected == i && !off;
              return Semantics(
                button: true,
                enabled: !off,
                selected: on,
                label: '${labels[i]}${off ? ', taken' : ''}',
                child: SizedBox(
                  width: w,
                  height: 46,
                  child: Material(
                    color: on ? C.primary : (off ? const Color(0xFFF1ECE2) : Colors.white),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: on ? C.primary : (off ? const Color(0xFFF1ECE2) : C.field), width: 1.5)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: off ? null : () => onSelect(i),
                      child: Center(
                        child: Text(labels[i], style: Ty.nunito(size: 14.5, weight: FontWeight.w700, color: on ? Colors.white : (off ? const Color(0xFFB0A998) : C.ink)).copyWith(decoration: off ? TextDecoration.lineThrough : null)),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ]);
      });
}
