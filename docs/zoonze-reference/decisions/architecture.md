# Decision — Architecture

_Last updated: Phase 0 foundation._

Feature-first, layered (CLAUDE.md §4). Cross-cutting code in `core/`; each
feature owns `data / domain / presentation`. **The repository boundary is
sacred:** UI → Riverpod providers → repository → GraphQL. Presentation never
touches GraphQL directly; repositories return domain entities or throw a
`Failure` (never a raw GraphQL map/exception).

```
lib/
  main.dart, main_{dev,staging,prod}.dart   # entrypoints → bootstrap()
  bootstrap.dart                            # init storage, container, runApp
  app/        app.dart · router.dart · theme/(app_colors, app_theme)
  core/
    config/   app_config.dart               # --dart-define-from-file
    graphql/  store_link.dart · graphql_client.dart   # link chain
    store/    store_view.dart · store_repository.dart · store_controller.dart
    storage/  secure_token_store · local_cache(Hive) · locale_prefs
    error/    failure.dart · graphql_failure_mapper.dart
    widgets/  failure_message.dart
    assets/   app_images.dart
  features/
    diagnostics/  data/store_config_repository.dart
                  presentation/health_check_screen.dart
  l10n/       app_en.arb · app_ar.arb (+ generated AppLocalizations)
```

## Key flows
- **GraphQL link chain:** `AuthLink` (bearer when present) → `StoreHeaderLink`
  (dynamic `Store` header + stable `User-Agent`) → terminating `HttpLink`.
  Exception → `Failure` mapping lives at the repository layer
  (`graphql_failure_mapper.dart`): non-JSON/HTML → `service`; auth → `auth`;
  GraphQL errors → `server`. (An in-link `ErrorLink` for auto-logout/backoff is
  a planned Phase-1 enhancement.)
- **Store switch is atomic** (`StoreController.switchLocale`): persist locale →
  `ref.invalidate(graphqlClientProvider)` (drops cache) → state change rebuilds
  Directionality, theme (font), and router.
- **Errors are values:** `Failure(FailureKind, detail?)`; the UI maps kind →
  localized string (`failure_message.dart`).

## Conventions
Bidirectional by default (build + test EN/LTR **and** AR/RTL) · directional
layout primitives (`EdgeInsetsDirectional`, etc.) · no fabricated data · token in
secure storage only · analyzer clean · tests for critical paths.
