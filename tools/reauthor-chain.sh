#!/bin/bash
# Re-author the corporate-identity commits on the given refs of a repo (shallow clones and
# worktrees included), keeping trees, messages and dates. Commits by others are kept as is,
# unless an ancestor changed. Appends "old new" lines to $MAP.
# Usage: MAP=file tools/reauthor-chain.sh <repo> <ref>...
set -euo pipefail
repo=$1; shift
old_email=alexander.gurov@konsulko.com
new_name="Alexander Gurov" new_email=aliogu23@gmail.com
: "${MAP:?}"
cd "$repo"
declare -A map
while read -r c; do
	read -r -a parents <<< "$(git rev-list --parents -n1 "$c" | cut -s -d' ' -f2-)"
	changed=0 pargs=()
	for p in "${parents[@]}"; do
		np=${map[$p]:-$p}; [[ $np == "$p" ]] || changed=1
		pargs+=(-p "$np")
	done
	IFS=$'\t' read -r an ae ad cn ce cd < <(git log -1 --format=$'%an\t%ae\t%ad\t%cn\t%ce\t%cd' --date=raw "$c")
	[[ $ae == "$old_email" ]] && { an=$new_name ae=$new_email changed=1; }
	[[ $ce == "$old_email" ]] && { cn=$new_name ce=$new_email changed=1; }
	if (( changed )); then
		new=$(git cat-file commit "$c" | sed "1,/^$/d" | GIT_AUTHOR_NAME=$an GIT_AUTHOR_EMAIL=$ae GIT_AUTHOR_DATE=$ad \
			GIT_COMMITTER_NAME=$cn GIT_COMMITTER_EMAIL=$ce GIT_COMMITTER_DATE=$cd \
			git commit-tree "$(git rev-parse "$c^{tree}")" "${pargs[@]}")
		map[$c]=$new
		echo "$c $new" >> "$MAP"
	fi
done < <(git rev-list --reverse --topo-order "$@")
for ref in "$@"; do
	if [[ $ref == HEAD ]]; then
		old=$(git rev-parse HEAD); new=${map[$old]:-$old}
		git update-ref --no-deref HEAD "$new" "$old"
	else
		full=$(git rev-parse --symbolic-full-name "$ref"); old=$(git rev-parse "$full"); new=${map[$old]:-$old}
		git update-ref "$full" "$new" "$old"
	fi
	echo "$repo $ref: ${old:0:12} -> ${new:0:12}"
done
