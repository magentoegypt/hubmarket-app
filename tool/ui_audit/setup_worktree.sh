#!/usr/bin/env bash
# Run once in a fresh git worktree of this repo: dependencies, localisations and the GraphQL
# codegen (the *.graphql.dart files and AppLocalizations are build output, not committed), then
# link the Figma frames the main checkout already downloaded so pairs.py / compose.py find them.
#
#     bash tool/ui_audit/setup_worktree.sh
set -euo pipefail

MAIN="${UI_AUDIT_MAIN:-/c/xampp/htdocs/hubmarket}"

flutter pub get
dart run build_runner build --delete-conflicting-outputs

mkdir -p build/ui_audit
if [ -d "$MAIN/build/ui_audit/figma" ] && [ ! -e build/ui_audit/figma ]; then
  cp -r "$MAIN/build/ui_audit/figma" build/ui_audit/figma
  echo "copied $(ls build/ui_audit/figma | wc -l) Figma frames"
fi
