import 'package:flutter/material.dart';

abstract final class AppColors {
  // Core palette extracted from the approved warm Japanese-natural UI.
  static const brand = Color(0xFF245E2B);
  static const brandDark = Color(0xFF14341E);
  static const brandMid = Color(0xFF3F7A35);
  static const brandSoft = Color(0xFF73945B);
  static const brandLight = Color(0xFFE6ECDD);

  static const cream = Color(0xFFFFFDF8);
  static const mist = Color(0xFFF0F2E9);
  static const paper = Color(0xFFF7F3EA);
  static const paperStrong = Color(0xFFFFFDF8);
  static const outline = Color(0xFFD8DDCF);
  static const outlineStrong = Color(0xFFB9C4AE);
  static const ink = Color(0xFF14341E);
  static const inkMuted = Color(0xFF706D68);
  static const inkFaint = Color(0xFF98948C);

  static const amber = Color(0xFFD8A83C);
  static const amberSoft = Color(0xFFE3BE68);
  static const amberLight = Color(0xFFF4E8C7);

  static const success = Color(0xFF3F7A35);
  static const warning = Color(0xFFDE8B2D);
  static const danger = Color(0xFFC95745);
  static const dangerSoft = Color(0xFFF8E5E0);
  static const info = Color(0xFF557761);

  static const keep = success;
  static const discard = Color(0xFF747772);
  static const pending = warning;
  static const featured = amber;

  // Dark surfaces remain available because the delivered app follows the
  // system theme even though the supplied references only cover light mode.
  static const darkSurface = Color(0xFF17251B);
  static const darkSurfaceRaised = Color(0xFF223527);
  static const darkOutline = Color(0xFF526453);
}
