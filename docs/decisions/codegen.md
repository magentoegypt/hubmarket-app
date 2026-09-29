# Decision — GraphQL schema → SDL → typed Dart (codegen)

The app is a typed GraphQL client: feature code never touches
`Map<String, dynamic>`. Typed Dart is generated from `.graphql` files by
**`graphql_codegen`**, against the **live** Magento schema.

## The pipeline

```
zoonze.com/graphql
  │  tool/introspect.sh            (runs on a network that reaches the origin → CI)
  ▼
lib/core/graphql/schema.introspection.json   (raw introspection JSON — gitignored)
  │  tool/json_to_sdl.mjs          (graphql buildClientSchema → printSchema)
  ▼
lib/core/graphql/schema.graphql    (SDL — COMMITTED, the codegen input)
  │  dart run build_runner build   (graphql_codegen, configured in build.yaml)
  ▼
lib/<feature>/data/graphql/<op>.graphql.dart   (typed Dart — gitignored)
```

### Why each piece

- **`tool/json_to_sdl.mjs`** uses the official `graphql` npm package
  (`buildClientSchema` → `lexicographicSortSchema` → `printSchema`) so the SDL is
  correct and **deterministic** — re-running only diffs when the live schema
  actually changes. Accepts either `{data:{__schema}}` or a bare `{__schema}`.
- **`schema.graphql` is committed**; the raw `schema.introspection.json` and the
  generated `*.graphql.dart` are **gitignored** (`schema.graphql` is the
  reviewable source of truth, the rest is reproducible output).
- Generated files are **excluded from `flutter analyze`** (`analysis_options.yaml`)
  — they're machine-written and lint-noisy.

## How to refresh the schema

The agent sandbox can't reach `zoonze.com`, but the **Introspect Live GraphQL**
workflow can:

1. **Actions → Introspect Live GraphQL → Run workflow.**
2. It installs `graphql`, runs `tool/introspect.sh` (which calls
   `tool/json_to_sdl.mjs`), uploads the `introspection` artifact, and
   **commits the refreshed `lib/core/graphql/schema.graphql`** back to `main`
   (`[skip ci]`).
3. Locally instead: `npm i graphql && bash tool/introspect.sh` on any networked
   machine.

## How to add a typed operation (Phase 1+)

1. Write the operation in `lib/<feature>/data/graphql/<name>.graphql`, e.g.:
   ```graphql
   query CategoryList { categoryList { uid name url_key } }
   ```
2. `dart run build_runner build --delete-conflicting-outputs` →
   `<name>.graphql.dart` with typed `Query$CategoryList`, `Variables$…`, and
   graphql_flutter `Options$…` helpers.
3. Use it in the repository layer (never in widgets/providers directly).

`build.yaml` options: `clients: [graphql_flutter]`, `addTypename: true`, and a
`scalars:` map to extend as Magento custom scalars surface.

## CI runs codegen

Every workflow that compiles or tests Dart runs
`dart run build_runner build --delete-conflicting-outputs` right after
`flutter pub get` (`ci.yml`, both `build-on-push` jobs, `release-android`,
`release-ios`). Because the generated `*.graphql.dart` are gitignored, CI
regenerates them on each run — and this **doubles as a drift guard**: if an
operation references a field that no longer exists in the committed
`schema.graphql`, codegen fails and CI goes red. (`introspect.yml` is the one
exception — it *produces* the schema rather than building the app.)
