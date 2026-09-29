# Decision — Tech stack & versions

_Last updated: Phase 0 foundation._

Toolchain pinned and verified in-session:

- **Flutter** 3.44.4 (stable) · **Dart** 3.12.2
- Android + iOS single codebase (Android flavors wired; iOS schemes are a local Xcode step).

## Runtime dependencies (constraints in `pubspec.yaml`; exact resolved versions in `pubspec.lock`)

| Package | Constraint | Role |
|---|---|---|
| `flutter_riverpod` | ^2.5.0 | State management + DI (resolved 2.6.1) |
| `graphql_flutter` | ^5.1.0 | GraphQL transport (primary backend) |
| `go_router` | ^14.0.0 | Declarative routing / deep links |
| `flutter_secure_storage` | ^9.0.0 | Customer token (secure only) |
| `shared_preferences` | ^2.2.0 | Locale / flags |
| `hive_ce` + `hive_ce_flutter` | ^2.0.0 | Offline cache (store list now; cart/wishlist later) |
| `dio` | ^5.4.0 | Non-GraphQL HTTP (payment callbacks, health checks) |
| `cached_network_image` | ^3.3.0 | Product imagery |
| `intl` + `flutter_localizations` | sdk / any | Localization, AED formatting |

## Dev dependencies
- `flutter_lints` ^5.0.0 — analyzer clean.

## Deliberate Phase-0 deviations from CLAUDE.md (revisit in Phase 1)
- **Codegen deferred.** CLAUDE.md specifies `riverpod_generator` + `graphql_codegen`. Phase 0 uses **plain Riverpod providers** and **hand-written GraphQL documents + typed DTOs** for the two bootstrap ops (`availableStores`, `storeConfig`). Rationale: the live schema can't be introspected from this environment (origin blocked), so `graphql_codegen` has no schema yet; keeping Phase 0 codegen-free makes the bootstrap build deterministic. Both generators are introduced in **Phase 1** once `tool/introspect.sh` produces `schema.graphql` (see `build.yaml` for the prepared target).
- **Fonts** are bundled as **variable** TTFs (Inter, Cairo, Playfair Display) fetched from `github.com/google/fonts`, one file per family (all weights via the variable axis).
