#!/bin/bash
# clone-repo.sh <workspace dir> [catalan-is-irrational repo URL] [commit-ish]
#
# Clones catalan-is-irrational into <workspace dir>/catalan-is-irrational,
# next to the workspace's hol-light checkout. The repository defaults to
# https://github.com/hol-light-family/catalan-is-irrational.git and commit-ish
# defaults to HEAD (the latest commit on its default branch). The resolved
# commit is recorded in catalan-is-irrational/CATALAN_IS_IRRATIONAL_COMMIT.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "clone-repo.sh <workspace dir> [catalan-is-irrational repo URL] [commit-ish]" >&2
  exit 1
fi

workspace_dir=$1
repo_url=${2:-https://github.com/hol-light-family/catalan-is-irrational.git}
commit_ish=${3:-HEAD}

if [ ! -d "$workspace_dir" ]; then
  echo "Workspace dir '$workspace_dir' does not exist." >&2
  exit 1
fi
workspace_dir=$(cd "$workspace_dir" && pwd)

checkout_dir="$workspace_dir/catalan-is-irrational"
if [ -e "$checkout_dir" ]; then
  echo "'$checkout_dir' already exists; remove it or choose another workspace." >&2
  exit 1
fi

git clone "$repo_url" "$checkout_dir"
git -C "$checkout_dir" checkout --detach "$commit_ish"

resolved_commit=$(git -C "$checkout_dir" rev-parse HEAD)
printf '%s\n' "$resolved_commit" > "$checkout_dir/CATALAN_IS_IRRATIONAL_COMMIT"

printf '\nCloned catalan-is-irrational into: %s\n' "$checkout_dir"
printf 'Checked out commit:               %s\n' "$resolved_commit"
