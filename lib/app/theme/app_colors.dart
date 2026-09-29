import 'package:flutter/material.dart';

/// Hub Market design tokens (Figma file rJVCVQdnC59gNbLAWQBZw3, page
/// "01 · Cover & Foundations", mirrored from the storefront's `--hm-*` CSS
/// variables). A single source of truth for brand colours so theming stays
/// consistent across every screen.
abstract final class AppColors {
  /// Navy — primary actions, active tabs, headers.
  static const Color brandPrimary = Color(0xFF0F2144);

  /// Pressed / active state of [brandPrimary].
  static const Color brandPrimaryPressed = Color(0xFF0A1731);

  /// Logo navy (`#02224D`) — app icon tile and the logo artwork only.
  static const Color logoNavy = Color(0xFF02224D);

  /// Orange accent (storefront `--hm-orange`) — highlights, search button, dots.
  static const Color accent = Color(0xFFF26522);

  /// Accent for text and filled buttons on white — passes AA contrast where
  /// [accent] does not (prices, "See all" links, Accent buttons).
  static const Color accentStrong = Color(0xFFC2410C);

  /// Light navy tint — section backgrounds, icon chips, empty-state circles.
  static const Color surfaceTint = Color(0xFFEEF2F8);

  /// Discount badges (e.g. `-24%`).
  static const Color accentSale = Color(0xFFE5484D);

  /// Rank / "#1" badges and review stars.
  static const Color accentGold = Color(0xFFF5B700);

  /// Positive states — "FREE" delivery, in-stock, unlocked thresholds.
  static const Color success = Color(0xFF16A34A);

  /// Figma `--hm-success` — completed checkout steps, the order-placed and
  /// added-to-cart ticks, free-shipping notes.
  static const Color successStrong = Color(0xFF0F7B3F);

  /// Figma `--hm-success-subtle` — the halo behind the order-placed tick.
  static const Color successSubtle = Color(0xFFEAF6EF);

  /// Figma `--hm-info` / `--hm-info-subtle` — informational notes, e.g.
  /// checkout's "You already have an account with us".
  static const Color info = Color(0xFF1D4ED8);
  static const Color infoSubtle = Color(0xFFEAF0FD);

  /// WhatsApp brand green — WhatsApp code / support actions.
  static const Color whatsappGreen = Color(0xFF25D366);

  /// Headings / primary text (Figma `text/primary`).
  static const Color inkHeading = Color(0xFF1A1A2E);

  /// Secondary text, struck-through prices.
  static const Color inkMuted = Color(0xFF6B7280);

  /// Faint text — input placeholders, inline field icons (Figma `text/muted`).
  static const Color inkFaint = Color(0xFF9CA3AF);

  /// Default hairline border (`border/default`) — card outlines, dividers.
  static const Color borderDefault = Color(0xFFE3E8EF);

  /// Figma `--hm-default` — a firmer outline: upcoming checkout steps and their
  /// connectors, the bottom-sheet handle.
  static const Color borderStrong = Color(0xFFCBD3E2);

  /// Light neutral band — section separators between sticky header and content.
  static const Color surfaceMuted = Color(0xFFF3F4F6);

  /// Page background behind grouped sections (Figma `bg/subtle`).
  static const Color surfaceSubtle = Color(0xFFF5F7FA);

  /// Dark surfaces.
  static const Color surfaceDark = Color(0xFF1F2937);

  /// Marketing-footer ground — the storefront footer navy.
  static const Color footerSurface = Color(0xFF0F1A2E);
}
