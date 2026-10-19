#!/usr/bin/env bash
# Linearize main: drop bot (renovate/dependabot) commits and merge commits.
# Every kept commit keeps its exact tree, message, author and dates, so nothing can conflict:
# bot changes simply land in the next human commit. Bot changes after the last human commit
# become one "Dependency updates" commit. Rerunning is cheap: unchanged commits get the same hashes.
#
# usage: scripts/clean-history.sh     then: git push --force-with-lease origin main
set -euo pipefail

branch=main
bot_re='\[bot\]|dependabot|renovate'

cd "$(git rev-parse --show-toplevel)"
[ "$(git branch --show-current)" = "$branch" ] || { echo "❌ check out $branch first" >&2; exit 1; }

# Renovate PRs are merged on GitHub: the remote state must be part of local history
# (by tree, since a previous unpushed run rewrote the hashes).
git fetch -q origin "$branch"
if ! git merge-base --is-ancestor "origin/$branch" HEAD &&
    ! git log --format=%T HEAD | grep -qx "$(git rev-parse "origin/$branch^{tree}")"; then
    echo "❌ origin/$branch has changes that are not in $branch, run git pull first" >&2
    exit 1
fi

old=$(git rev-parse HEAD)
new=""
kept=0 dropped=0

while IFS=$'\x1f' read -r c parents author; do
    if [[ "$parents" == *" "* ]] || grep -qiE "$bot_re" <<<"$author"; then
        dropped=$((dropped + 1))
        continue
    fi
    IFS=$'\x1f' read -r an ae ad cn ce cd < <(git log -1 --format='%an%x1f%ae%x1f%aI%x1f%cn%x1f%ce%x1f%cI' "$c")
    # Exact message from the raw object (log --format=%B adds a newline, changing the hash on rerun)
    new=$(git cat-file commit "$c" | sed '1,/^$/d' |
        GIT_AUTHOR_NAME=$an GIT_AUTHOR_EMAIL=$ae GIT_AUTHOR_DATE=$ad \
        GIT_COMMITTER_NAME=$cn GIT_COMMITTER_EMAIL=$ce GIT_COMMITTER_DATE=$cd \
        git commit-tree "$c^{tree}" ${new:+-p "$new"})
    kept=$((kept + 1))
done < <(git log --reverse --first-parent --format='%H%x1f%P%x1f%an <%ae>' HEAD)

if [ "$(git rev-parse "HEAD^{tree}")" != "$(git rev-parse "$new^{tree}")" ]; then
    new=$(echo "Dependency updates" | git commit-tree "HEAD^{tree}" -p "$new")
fi

if [ "$new" = "$old" ]; then
    echo "✅ already clean ($kept commits)"
    exit 0
fi

backup="backup/$branch-$(date +%Y%m%d-%H%M%S)"
git branch "$backup" "$old"
# Same tree as before: staged and unstaged changes stay untouched
git reset -q --soft "$new"

echo "✅ $branch: kept $kept commits, dropped $dropped bot/merge commits, final tree unchanged"
echo "   old state: $backup (delete with: git branch -D $backup)"
echo "   publish:   git push --force-with-lease origin $branch"
