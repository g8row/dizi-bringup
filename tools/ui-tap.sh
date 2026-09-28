#!/bin/bash
# Tap the first on-screen element whose text or content-desc matches one of the given labels
# (exact match, in order of preference), from a uiautomator dump. Prints what it tapped.
# Usage: tools/ui-tap.sh "Skip" "Next" ...   (exit 1 if none is on screen)
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
a() { "$R" adb "$@" </dev/null 2>/dev/null | tr -d '\r'; }
dump=$(a shell 'uiautomator dump /data/local/tmp/ui-tap.xml >/dev/null; cat /data/local/tmp/ui-tap.xml' | grep -o '<node [^>]*>')
for label in "$@"; do
	node=$(grep -F -e "text=\"$label\"" -e "content-desc=\"$label\"" <<<"$dump" | head -1)
	[[ -n $node ]] || continue
	read -r x y < <(sed -E 's/.*bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]".*/\1 \2 \3 \4/' <<<"$node" |
		awk '{print int(($1 + $3) / 2), int(($2 + $4) / 2)}')
	a shell "input tap $x $y"
	echo "tapped '$label' at $x,$y"
	exit 0
done
echo "none of: $* (screen texts: $(grep -o 'text="[^"]\+"' <<<"$dump" | head -12 | tr '\n' ' '))" >&2
exit 1
