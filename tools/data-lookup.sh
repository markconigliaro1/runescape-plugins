#!/usr/bin/env bash
# Look up specific entries in the local client exports in data/ (see AGENTS.md).
# Prints at most 50 matching lines per file, so a search can't dump a whole export.
#
#   tools/data-lookup.sh DOG_STRAY        search every export
#   tools/data-lookup.sh "stray dog" NPC  search data/NPC.txt only
set -euo pipefail

max_results=50
pattern=${1:-}
export_name=${2:-}
data_dir="$(cd "$(dirname "$0")/.." && pwd)/data"

if [ "${#pattern}" -lt 3 ]; then
	echo "usage: $0 PATTERN [EXPORT]  (PATTERN needs 3+ characters)" >&2
	exit 2
fi

if [ -n "$export_name" ]; then
	files=("$data_dir/$export_name.txt")
else
	files=("$data_dir"/*.txt)
fi

# Case-insensitive fixed-string match; -m caps the lines printed per file.
grep -i -F -m "$max_results" -H -- "$pattern" "${files[@]}" | sed "s|^$data_dir/||"
