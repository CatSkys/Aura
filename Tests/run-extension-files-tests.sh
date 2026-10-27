#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/search-extension-files-tests.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM

# Localized.swift comes along: ExtensionFiles.swift says why an install failed
# through Localized(...), so the runner needs it beside the file under test.
swiftc -swift-version 5 \
    "$repo_dir/Sources/Aura/ExtensionFiles.swift" \
    "$repo_dir/Sources/Aura/Localized.swift" \
    "$repo_dir/Tests/ExtensionFilesTests.swift" \
    -o "$build_dir/extension-files-tests"
"$build_dir/extension-files-tests"
