#!/usr/bin/env bash
# Claude Code PostToolUse hook: after Claude changes files, copy the affected
# plugins into the beta client's dev_plugins (like `make sync`), so `prl <name>`
# in game picks the change up. Does nothing if dev_plugins doesn't exist.
set -euo pipefail

input=$(cat)
root=${CLAUDE_PROJECT_DIR:-$(pwd)}
dev_plugins=${DEV_PLUGINS:-$HOME/Jagex/RuneScape-BETA/dev_plugins}
[ -d "$dev_plugins" ] || exit 0

tool=$(jq -r '.tool_name' <<<"$input")
path=$(jq -r '.tool_input.file_path // ""' <<<"$input")

cd "$root"
if [ "$tool" = "Bash" ]; then
	# A shell command could have changed any plugin, so check them all.
	dirs=(plugins/*/)
else
	case "$path" in
	"$root"/plugins/*/*)
		name=${path#"$root"/plugins/}
		dirs=("plugins/${name%%/*}/")
		;;
	*) exit 0 ;;
	esac
fi

synced=()
for dir in "${dirs[@]}"; do
	name=$(basename "$dir")
	# Same flags as `make sync`; -i lists what changed, so unchanged plugins stay quiet.
	changes=$(rsync -a -i --delete --exclude '*.md' --exclude '.DS_Store' "$dir" "$dev_plugins/$name/")
	if [ -n "$changes" ]; then
		synced+=("$name")
	fi
done

if [ ${#synced[@]} -gt 0 ]; then
	jq -n --arg msg "Synced to dev_plugins: ${synced[*]}. Run prl <name> in game." '{systemMessage: $msg}'
fi
