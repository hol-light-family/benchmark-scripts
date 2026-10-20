#!/bin/bash
# clone-repo.sh <workspace dir> [s2n-bignum repo URL] [commit-ish]
#
# Clones s2n-bignum into an existing benchmark workspace, right next to the
# hol-light checkout, i.e. it creates <workspace dir>/s2n-bignum. This is the
# same workspace that holds hol-light (e.g.
#   holbench-workspace/holbench-.../hol-light
# ), so run.sh can point HOLDIR at that sibling hol-light.
#
# A full clone (not --depth 1) is used: a specific commit-ish may not be the
# tip, and the proof Makefiles are happier with a normal git working tree.
# The repository defaults to https://github.com/awslabs/s2n-bignum.git and
# commit-ish defaults to HEAD (the latest commit on its default branch).
# The resolved commit is written to <workspace dir>/s2n-bignum/S2N_BIGNUM_COMMIT.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "clone-repo.sh <workspace dir> [s2n-bignum repo URL] [commit-ish]" >&2
  exit 1
fi

workspace_dir=$1
repo_url=${2:-https://github.com/awslabs/s2n-bignum.git}
commit_ish=${3:-HEAD}

if ! command -v git >/dev/null 2>&1; then
  echo "git is required but not found on PATH." >&2
  exit 1
fi

if [ ! -d "$workspace_dir" ]; then
  echo "Workspace dir '$workspace_dir' does not exist." >&2
  echo "Point this at the workspace that already holds hol-light." >&2
  exit 1
fi
workspace_dir=$(cd "$workspace_dir" && pwd)

checkout_dir="$workspace_dir/s2n-bignum"
if [ -e "$checkout_dir" ]; then
  echo "'$checkout_dir' already exists; remove it or choose another workspace." >&2
  exit 1
fi

git clone "$repo_url" "$checkout_dir"
git -C "$checkout_dir" checkout --detach "$commit_ish"

resolved_commit=$(git -C "$checkout_dir" rev-parse HEAD)
echo "$resolved_commit" > "$checkout_dir/S2N_BIGNUM_COMMIT"

echo
echo "Cloned s2n-bignum into: $checkout_dir"
echo "Checked out commit:     $resolved_commit"
if [ -d "$workspace_dir/hol-light" ]; then
  echo "Sibling hol-light found: $workspace_dir/hol-light"
else
  echo "Note: no hol-light checkout found next to it yet in $workspace_dir."
fi
echo
echo "Next:"
echo "  install-dependencies.sh"
echo "  run.sh $checkout_dir <arm|x86> $workspace_dir/hol-light"
