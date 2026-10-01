import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/theme_x.dart';
import '../../l10n/l10n.dart';
import '../network/connectivity.dart';
import '../../app/theme/hub_icons.dart';

/// Figma "S3 Offline", the page: an amber no-signal disc, "You're offline",
/// a line about Wi-Fi / mobile data and "Try again". Shown where content
/// failed to load because the request never reached the store. It also
/// retries by itself the moment the OS reports the network back.
class OfflineState extends ConsumerStatefulWidget {
  const OfflineState({super.key, this.onRetry});

  /// Loads the content again; without it there is no "Try again".
  final VoidCallback? onRetry;

  @override
  ConsumerState<OfflineState> createState() => _OfflineStateState();
}

class _OfflineStateState extends ConsumerState<OfflineState> {
  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isOfflineProvider, (was, now) {
      if (was == true && !now) widget.onRetry?.call();
    });
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: AppColors.warningSubtle,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                HubIcons.wifiOff,
                size: 48,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: 14),
            // On the scaffold: ink in light mode, light text in dark mode.
            Text(
              l10n.offlineTitle,
              textAlign: TextAlign.center,
              style: t.heading1.copyWith(color: context.scaffoldHeading),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.offlineBody,
              textAlign: TextAlign.center,
              style: t.body.copyWith(color: context.scaffoldMuted),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.onRetry,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: t.button,
                  ),
                  child: Text(l10n.offlineTryAgain),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Figma "S3 Offline", the toast: a navy strip — no-signal icon, "No internet
/// connection" and an orange "Retry" that asks the OS again.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Material(
      color: AppColors.brandPrimary,
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 4, 0),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const Icon(
                  HubIcons.wifiOff,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.offlineBanner,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyStrong.copyWith(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(connectivityProvider),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentOnDark,
                    textStyle: t.bodyStrong,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(l10n.actionRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a screen with the bottom tab bar shows [OfflineBanner]: directly
/// above the tabs, as in S3. While its route is the one on top it tells the
/// app-wide [OfflineBannerHost] so, and the host keeps its own strip hidden.
class OfflineBannerSlot extends ConsumerStatefulWidget {
  const OfflineBannerSlot({super.key});

  @override
  ConsumerState<OfflineBannerSlot> createState() => _OfflineBannerSlotState();
}

class _OfflineBannerSlotState extends ConsumerState<OfflineBannerSlot> {
  _OfflineDocks? _docks;
  bool _docked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _docks = _OfflineDockScope.maybeOf(context);
    _setDocked(ModalRoute.of(context)?.isCurrent ?? true);
  }

  void _setDocked(bool docked) {
    if (docked == _docked) return;
    _docked = docked;
    final docks = _docks;
    if (docks == null) return;
    // Not during build: the host rebuilds when the count changes.
    WidgetsBinding.instance.addPostFrameCallback((_) => docks.update(docked));
  }

  @override
  void dispose() {
    if (_docked) {
      final docks = _docks;
      WidgetsBinding.instance.addPostFrameCallback((_) => docks?.update(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ref.watch(isOfflineProvider)
      ? const OfflineBanner()
      : const SizedBox.shrink();
}

/// Shows [OfflineBanner] app-wide: at the foot of any screen without the tab
/// bar (sign-in, checkout, …), unless a screen that has one is on top and
/// shows it above its tabs ([OfflineBannerSlot]) — or the keyboard is up.
/// Wraps the router's navigator in `MaterialApp.builder`.
class OfflineBannerHost extends ConsumerStatefulWidget {
  const OfflineBannerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OfflineBannerHost> createState() => _OfflineBannerHostState();
}

class _OfflineBannerHostState extends ConsumerState<OfflineBannerHost> {
  final _docks = _OfflineDocks();

  @override
  void dispose() {
    _docks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    final media = MediaQuery.of(context);
    return _OfflineDockScope(
      docks: _docks,
      child: ListenableBuilder(
        listenable: _docks,
        builder: (context, _) {
          final show =
              offline && _docks.count == 0 && media.viewInsets.bottom == 0;
          // The navigator keeps its place in the tree either way, so showing
          // the strip never rebuilds the routes.
          return Column(
            children: [
              Expanded(
                child: MediaQuery(
                  data: show ? media.removePadding(removeBottom: true) : media,
                  child: widget.child,
                ),
              ),
              if (show)
                ColoredBox(
                  color: AppColors.brandPrimary,
                  child: SafeArea(
                    top: false,
                    child: const OfflineBanner(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// How many on-top screens currently show the banner above their tabs.
class _OfflineDocks extends ChangeNotifier {
  int count = 0;
  bool _disposed = false;

  void update(bool docked) {
    // A slot's last word can land after the app itself was torn down.
    if (_disposed) return;
    count = (count + (docked ? 1 : -1)).clamp(0, 1 << 20);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _OfflineDockScope extends InheritedWidget {
  const _OfflineDockScope({required this.docks, required super.child});

  final _OfflineDocks docks;

  static _OfflineDocks? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_OfflineDockScope>()
      ?.docks;

  @override
  bool updateShouldNotify(_OfflineDockScope old) => old.docks != docks;
}
