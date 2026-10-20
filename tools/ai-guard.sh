#!/usr/bin/env bash
# Claude Code PreToolUse hook that enforces the AI rules in AGENTS.md.
# It reads the tool call as JSON on stdin and prints a "deny" decision to
# block it; printing nothing lets the call go ahead.
set -euo pipefail

input=$(cat)
tool=$(jq -r '.tool_name' <<<"$input")
root=${CLAUDE_PROJECT_DIR:-$(pwd)}

# Most results Grep may return from data/ in one search.
max_data_results=50

deny() {
	jq -n --arg reason "$1" '{
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason: $reason
		}
	}'
	exit 0
}

# Succeeds if the path points at the repo's data/ folder or a file inside it.
in_data() {
	case "$1" in
	"$root/data" | "$root"/data/* | data | data/* | ./data | ./data/*) return 0 ;;
	*) return 1 ;;
	esac
}

case "$tool" in
Bash)
	cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
	# Any shell command that names data/ could dump an export, so block them all.
	if grep -qE "(^|[[:space:]\"'=])(\./)?data(/|[[:space:]]|$)|runescape-plugins/data" <<<"$cmd"; then
		deny "data/ holds client exports. Use tools/data-lookup.sh PATTERN (or the Grep tool with a specific pattern and head_limit <= $max_data_results), not other shell commands (see AGENTS.md)."
	fi
	;;
Read)
	path=$(jq -r '.tool_input.file_path // ""' <<<"$input")
	if in_data "$path"; then
		deny "Don't read whole files in data/. Look up the entry you need with tools/data-lookup.sh PATTERN (see AGENTS.md)."
	fi
	;;
Grep)
	path=$(jq -r '.tool_input.path // ""' <<<"$input")
	if in_data "$path"; then
		pattern=$(jq -r '.tool_input.pattern // ""' <<<"$input")
		limit=$(jq -r '.tool_input.head_limit // 0' <<<"$input")
		if [ "${#pattern}" -lt 3 ]; then
			deny "Searches of data/ need a specific pattern (3+ characters) (see AGENTS.md)."
		fi
		if [ "$limit" -lt 1 ] || [ "$limit" -gt "$max_data_results" ]; then
			deny "Searches of data/ need head_limit between 1 and $max_data_results (see AGENTS.md)."
		fi
	fi
	;;
esac
