import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// MindBridge design tokens — taken directly from the v3 hi-fi prototype.
class C {
  static const bg = Color(0xFFF6F2EA);
  static const white = Color(0xFFFFFFFF);
  static const calm = Color(0xFFE8EFDF);
  static const alertBg = Color(0xFFFFF5F3);
  static const lilacBg = Color(0xFFF5F2FB);

  static const ink = Color(0xFF22261F);
  static const ink2 = Color(0xFF3B3A31);
  static const body = Color(0xFF45443A);
  static const body2 = Color(0xFF57554A);
  static const muted = Color(0xFF6E6A5D);
  static const muted2 = Color(0xFF7A7567);
  static const muted3 = Color(0xFF8A8475);
  static const muted4 = Color(0xFF979080);
  static const chevron = Color(0xFFA69F8E);
  static const disabled = Color(0xFFBDB6A6);

  static const card = Color(0xFFFFFDF9);
  static const line = Color(0xFFEAE3D6);
  static const line2 = Color(0xFFF0EBE0);
  static const field = Color(0xFFE0D8C8);
  static const fieldDisabled = Color(0xFFF2EEE5);
  static const track = Color(0xFFD5CDBD);
  static const segBg = Color(0xFFECE6DA);
  static const barBg = Color(0xFFEFEADF);

  static const primary = Color(0xFF4A7C59);
  static const dark = Color(0xFF2F5A3D);
  static const leaf = Color(0xFFB8D39A);
  static const selected = Color(0xFFE3EBD8);
  static const softGreen = Color(0xFFE6EEDD);
  static const barLight = Color(0xFFC5D7B3);
  static const markGood = Color(0xFF2C7A57);
  static const markLow = Color(0xFFE59A2B);

  static const danger = Color(0xFFC2382E);
  static const dangerText = Color(0xFFB3362C);
  static const error = Color(0xFFD9534A);
  static const dot = Color(0xFFE0533F);
}

/// Background + foreground pair for badges, icon chips and banners.
class Tone {
  const Tone(this.bg, this.fg);
  final Color bg;
  final Color fg;

  static const green = Tone(Color(0xFFE6EEDD), Color(0xFF3A6647));
  static const amber = Tone(Color(0xFFFBEFD8), Color(0xFF8A5A0B));
  static const blue = Tone(Color(0xFFE2ECF7), Color(0xFF2B5C8A));
  static const red = Tone(Color(0xFFFBE5E2), Color(0xFFA52B22));
  static const grey = Tone(Color(0xFFECEFEA), Color(0xFF4F5A53));
  static const lilac = Tone(Color(0xFFECE8F7), Color(0xFF58479A));
  static const dark = Tone(Color(0xFF2F5A3D), Colors.white);

  static Tone of(String? name) => switch (name) {
        'amber' => amber,
        'blue' => blue,
        'red' => red,
        'grey' => grey,
        'lilac' => lilac,
        'dark' => dark,
        _ => green,
      };
}

enum HeroStyle { dark, soft, lilac, white, alert, amber }

class HeroColors {
  const HeroColors(this.bg, this.fg, this.muted);
  final Color bg;
  final Color fg;
  final Color muted;

  static HeroColors of(HeroStyle s) => switch (s) {
        HeroStyle.dark => const HeroColors(Color(0xFF2F5A3D), Colors.white, Color(0xC7FFFFFF)),
        HeroStyle.soft => const HeroColors(Color(0xFFE6EEDD), Color(0xFF22261F), Color(0xFF3F5A4A)),
        HeroStyle.lilac => const HeroColors(Color(0xFFECE8F7), Color(0xFF1F1838), Color(0xFF58479A)),
        HeroStyle.white => const HeroColors(Colors.white, Color(0xFF22261F), Color(0xFF6E6A5D)),
        HeroStyle.alert => const HeroColors(Color(0xFFFBE5E2), Color(0xFF4A1410), Color(0xFFA52B22)),
        HeroStyle.amber => const HeroColors(Color(0xFFFBEFD8), Color(0xFF3E2A06), Color(0xFF8A5A0B)),
      };
}

enum PageBg { normal, white, calm, alert, lilac }

Color pageBg(PageBg b) => switch (b) {
      PageBg.white => C.white,
      PageBg.calm => C.calm,
      PageBg.alert => C.alertBg,
      PageBg.lilac => C.lilacBg,
      PageBg.normal => C.bg,
    };

/// Avatar colour pairs, chosen deterministically from the initials.
const avatarPalettes = [
  [Color(0xFFE2EBD6), Color(0xFF3A6647)],
  [Color(0xFFE2ECF7), Color(0xFF2B5C8A)],
  [Color(0xFFECE8F7), Color(0xFF58479A)],
  [Color(0xFFFBEFD8), Color(0xFF8A5A0B)],
  [Color(0xFFF6E3DD), Color(0xFF8E3B2B)],
];

List<Color> avatarColors(String seed) {
  final h = seed.codeUnits.fold<int>(0, (a, b) => a + b);
  return avatarPalettes[h % avatarPalettes.length];
}

/// Typography: Nunito for UI, Lora for headings.
class Ty {
  static TextStyle nunito({double size = 15, FontWeight weight = FontWeight.w400, Color color = C.ink, double? height, double? spacing}) =>
      GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);
  static TextStyle lora({double size = 21, FontWeight weight = FontWeight.w600, Color color = C.ink, double? height, double? spacing}) =>
      GoogleFonts.lora(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

  static TextStyle get xl => lora(size: 25, height: 1.2, spacing: -0.6);
  static TextStyle get lg => lora(size: 19, height: 1.3, spacing: -0.2);
  static TextStyle get md => nunito(size: 15, color: C.body, height: 1.6);
  static TextStyle get sm => nunito(size: 13, weight: FontWeight.w500, color: C.muted, height: 1.5);
  static TextStyle get xs => nunito(size: 12, weight: FontWeight.w500, color: C.muted2, height: 1.45);
  static TextStyle get eyebrow => nunito(size: 11.5, weight: FontWeight.w700, color: C.muted3, spacing: 0.7);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, surface: C.bg, error: C.danger),
    scaffoldBackgroundColor: C.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.primary, selectionHandleColor: C.primary),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      contentTextStyle: Ty.nunito(size: 14, weight: FontWeight.w600, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
