#!/bin/bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "create-workspace.sh <parent dir> <hol-light Github repo> <hol-light commit hash>"
  echo "                    <make switch param(either switch or switch-5)>"
  exit 1
fi

parent_dir=$1
hol_light_repo_url=$2
hol_light_commit=$3
switch_param=$4

# Packages required to build HOL Light (OCaml + opam switch + native compile
# toolchain) on a fresh Ubuntu machine.
required_apt_packages=(
  build-essential
  m4
  pkg-config
  curl
  wget
  git
  unzip
  rsync
  patch
  bubblewrap
  opam
)

missing_packages=()
for pkg in "${required_apt_packages[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing_packages+=("$pkg")
  fi
done

if [ "${#missing_packages[@]}" -gt 0 ]; then
  echo "Missing required apt packages: ${missing_packages[*]}" >&2
  echo "Please install them first, e.g.:" >&2
  echo "  sudo apt-get update && sudo apt-get install -y ${missing_packages[*]}" >&2
  exit 1
fi

if ! opam env >/dev/null 2>&1; then
  echo "opam is installed but has not been initialized. Please run:" >&2
  echo "  opam init" >&2
  exit 1
fi

# Derive "owner/repo" from the Github URL, e.g.
#   https://github.com/jrh13/hol-light.git -> jrh13/hol-light
#   https://github.com/jrh13/hol-light     -> jrh13/hol-light
owner_repo=$(echo "$hol_light_repo_url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/$##')
if [[ ! "$owner_repo" =~ ^[^/]+/[^/]+$ ]]; then
  echo "Could not parse <owner>/<repo> out of '$hol_light_repo_url'. Expected a Github repo URL." >&2
  exit 1
fi

workspace_name="holbench-$(date +%Y-%m-%d-%H.%M.%s --utc)"
workspace_path="$parent_dir/$workspace_name"
mkdir -p "$workspace_path"

cd "$workspace_path"

# Fetch a single commit as a tarball from Github's codeload service instead of
# a git clone.
resolved_commit=$(curl -fsSL "https://api.github.com/repos/$owner_repo/commits/$hol_light_commit" \
  | grep -m1 '"sha"' | sed -E 's/.*"sha":\s*"([0-9a-f]+)".*/\1/')
if [[ ! "$resolved_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not resolve '$hol_light_commit' to a full commit hash in $owner_repo." >&2
  exit 1
fi

tarball_url="https://github.com/$owner_repo/archive/$resolved_commit.tar.gz"
curl -fsSL -o hol-light.tar.gz "$tarball_url"
mkdir hol-light
tar xzf hol-light.tar.gz -C hol-light --strip-components=1
rm hol-light.tar.gz
echo "$resolved_commit" > hol-light/HOL_LIGHT_COMMIT

cd hol-light

make "$switch_param"
eval "$(opam env --set-switch)"
export HOLLIGHT_USE_MODULE=1
make
