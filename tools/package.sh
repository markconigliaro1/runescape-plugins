#!/usr/bin/env bash
# Builds the mod.io upload zip for one plugin: dist/<plugin>-<version>.zip,
# with main.lua and plugin.json at the top level of the zip.
#
# Usage: tools/package.sh <plugin> [expected-version]
#   expected-version (e.g. from a git tag) must match plugin.json's version.
set -euo pipefail

plugin="${1:?usage: tools/package.sh <plugin> [expected-version]}"
src="plugins/$plugin"
[ -f "$src/plugin.json" ] || { echo "no such plugin: $src" >&2; exit 1; }

version="$(MANIFEST="$src/plugin.json" "${LUA:-lua}" -e 'local f = io.open(os.getenv("MANIFEST")); print(require("dkjson").decode(f:read("a")).version)')"
if [ -n "${2:-}" ] && [ "$2" != "$version" ]; then
	echo "version mismatch: tag says $2, plugin.json says $version" >&2
	exit 1
fi

mkdir -p dist
out="$PWD/dist/$plugin-$version.zip"
rm -f "$out"
# Docs and changelogs live on GitHub and mod.io, not in the plugin itself.
(cd "$src" && zip -qr "$out" . -x '*.md' -x '.DS_Store' -x '*/.DS_Store')
echo "$out"
