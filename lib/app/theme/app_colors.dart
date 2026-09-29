import 'package:flutter/material.dart';

/// Figma design tokens (`Hub Market/Color`). A single source of truth for brand
/// colours so theming stays consistent across every screen.
abstract final class AppColors {
  /// Burgundy — primary actions, prices, wordmark.
  static const Color brandPrimary = Color(0xFF9E1B3F);

  /// Pressed / active state.
  static const Color brandPrimaryPressed = Color(0xFF7E1632);

  /// Blush — section backgrounds, icon chips, empty-state circles.
  static const Color surfaceTint = Color(0xFFFBF1F4);

  /// Discount badges (e.g. `-24%`).
  static const Color accentSale = Color(0xFFEF4444);

  /// `BESTSELLER` badge and review stars.
  static const Color accentGold = Color(0xFFC9A24C);

  /// Positive states — "FREE" delivery, in-stock, unlocked thresholds.
  static const Color success = Color(0xFF16A34A);

  /// WhatsApp brand green — the "Send WhatsApp code" registration action.
  static const Color whatsappGreen = Color(0xFF25D366);

  /// Headings / primary text.
  static const Color inkHeading = Color(0xFF1F2937);

  /// Secondary text, struck-through prices.
  static const Color inkMuted = Color(0xFF6B7280);

  /// Faint text — input placeholders, inline field icons (Figma `text/muted`).
  static const Color inkFaint = Color(0xFF9CA3AF);

  /// Default hairline border (`border/default`) — card outlines, dividers.
  static const Color borderDefault = Color(0xFFE5E7EB);

  /// Light neutral band — section separators between sticky header and content.
  static const Color surfaceMuted = Color(0xFFF3F4F6);

  /// Dark surfaces.
  static const Color surfaceDark = Color(0xFF1F2937);

  /// Marketing-footer ground. Its own token rather than [surfaceDark] because
  /// it has to match the storefront exactly (`.page-footer{background-color}`
  /// on hub-market.magento2.click), while [surfaceDark] also paints dark-mode scaffolds and
  /// app bars — moving that would repaint the whole dark theme.
  static const Color footerSurface = Color(0xFF0F1A2E);
}
