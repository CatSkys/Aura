#!/bin/sh
# Compiles the block list in Resources/Shield with WebKit, as Shield.swift does
# at launch, so a list WebKit would refuse fails here instead of in a browser
# that quietly keeps its adverts.
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/aura-blocker-regression.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

swiftc \
  -O \
  -swift-version 5 \
  -framework WebKit \
  "$repo_root/Tests/BlockerRegression/main.swift" \
  -o "$test_root/blocker-regression"

"$test_root/blocker-regression" "$repo_root/Resources/Shield"
