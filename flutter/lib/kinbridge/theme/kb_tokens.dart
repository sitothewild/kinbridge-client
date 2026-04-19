// KinBridge design tokens — strict warm-hearth palette + type scale.
//
// Source of truth: kinbridge-android-spec-full.pdf (Lovable) + the dashboard
// CSS at www.kinbridge.support. No off-brand colors. No ad-hoc sizes.
//
// Keep this file UI-library-free so it's safe to import everywhere.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Warm-hearth color tokens. Hex values are verbatim from spec page 2.
class KB {
  KB._();

  // Surfaces
  static const Color parchment = Color(0xFFFBF7EE); // app background
  static const Color surface = Color(0xFFFFFFFF); // card surface

  // Primary
  static const Color amber = Color(0xFFE59A4D); // primary action
  static const Color amberGlow = Color(0xFFF2B670); // gradient stop

  // Status
  static const Color sage = Color(0xFF8FB58A); // online / positive
  static const Color coral = Color(0xFFE89A8A); // alerts / soft

  // Type
  static const Color deepInk = Color(0xFF3A2E22); // primary text
  static const Color muted = Color(0xFF8A7A66); // secondary text

  // Structure
  static const Color hairline = Color(0xFFEFE4D2); // dividers

  // Derived gradient (used on the "Need a hand?" card, buttons, onboarding glow)
  static const LinearGradient amberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [amberGlow, amber],
  );

  // Radii — spec uses generous rounding on cards + pills
  static const double radiusCard = 20;
  static const double radiusPill = 28;
  static const double radiusField = 14;

  // Spacing scale — 4-point system as seen on spec mockups
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
}

/// KinBridge type scale. Fraunces (serif) for display/titles/headings,
/// Manrope (sans) for body/labels/captions/overlines. Sizes per the README
/// (Display 96 · Title 56 · Heading 36 · Body 28 · Label 22 · Caption 18 ·
/// Overline 16), scaled down ~0.5x for phone mockup realism because the spec
/// mockups are shown at 2x device density.
class KBText {
  KBText._();

  // Display — used sparingly, only on onboarding hero
  static TextStyle display({Color color = KB.deepInk}) => GoogleFonts.fraunces(
        fontSize: 48,
        color: color,
        fontWeight: FontWeight.w500,
        height: 1.05,
      );

  // Title — screen titles, big greetings ("Hi, Mom 🦋")
  static TextStyle title({Color color = KB.deepInk}) => GoogleFonts.fraunces(
        fontSize: 32,
        color: color,
        fontWeight: FontWeight.w500,
        height: 1.1,
      );

  // Heading — card headlines ("Need a hand?")
  static TextStyle heading({Color color = KB.deepInk}) => GoogleFonts.fraunces(
        fontSize: 22,
        color: color,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  // Modal / success titles ("You're connected with Mom")
  static TextStyle modalTitle({Color color = KB.deepInk}) =>
      GoogleFonts.fraunces(
        fontSize: 20,
        color: color,
        fontWeight: FontWeight.w600,
        height: 1.2,
      );

  // Body — main paragraph copy, descriptions
  static TextStyle body({Color color = KB.deepInk}) => GoogleFonts.manrope(
        fontSize: 15,
        color: color,
        height: 1.45,
      );

  // Label — buttons, UI labels ("Ask for help")
  static TextStyle label({Color color = KB.deepInk}) => GoogleFonts.manrope(
        fontSize: 15,
        color: color,
        fontWeight: FontWeight.w600,
      );

  // Caption — timestamps, metadata ("32 seconds ago")
  static TextStyle caption({Color color = KB.muted}) => GoogleFonts.manrope(
        fontSize: 12,
        color: color,
        height: 1.3,
      );

  // Overline — section eyebrows ("GOOD AFTERNOON", "RECENT HELPERS")
  static TextStyle overline({Color color = KB.muted}) => GoogleFonts.manrope(
        fontSize: 11,
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
      );
}
