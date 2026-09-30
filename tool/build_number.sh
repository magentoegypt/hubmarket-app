#!/usr/bin/env bash
# The build number CI gives every Loadly, TestFlight and Google Play build: the number of commits on
# the checked-out branch. It only ever goes up, which is what both stores demand of an upload
# (App Store Connect within a version, Google Play for the life of the app), so nobody has to
# remember to bump the +N in pubspec.yaml before a release.
#
#   bash tool/build_number.sh            # prints e.g. 240
#   flutter build apk --build-number="$(bash tool/build_number.sh)" ...
#
# It needs the full history: with actions/checkout use `fetch-depth: 0`. A shallow clone would
# print a small number that App Store Connect or Play refuses, so this stops instead.
set -euo pipefail

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  echo "error: shallow clone: the commit count is wrong. Use actions/checkout with fetch-depth: 0." >&2
  exit 1
fi

count="$(git rev-list --count HEAD)"
if [ "${count}" -lt 1 ]; then
  echo "error: no commits found" >&2
  exit 1
fi
echo "${count}"
