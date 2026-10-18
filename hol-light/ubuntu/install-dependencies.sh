#!/bin/bash
# install-dependencies.sh <hol-light dir>
#
# Prepares an Ubuntu machine (or CI sandbox) to run holtest.mk against an
# already-cloned HOL Light checkout.
#
# What this does:
#   1. Checks for the apt packages that cover most of holtest.mk's external
#      tool dependencies (csdp for Examples/sos, maxima for WZ/make, pari-gp
#      for Library/prime-pratt and Library/prime-pocklington, and
#      libocamlgraph-ocaml-dev for QBF). If any are missing, it prints the
#      apt-get command to install them and exits, rather than installing
#      anything itself.
#   2. Builds cadical and lrat-trim from source (holtest.mk's Cadical test
#      needs both; the apt "cadical" package is not guaranteed to be built
#      with the --lrat/--no-binary support HOL Light relies on, and
#      lrat-trim isn't packaged at all) and prover9 from the official LADR
#      source distribution (not packaged at all). Both are built into
#      <hol-light dir>/external-bin so nothing is installed system-wide and
#      no sudo is needed for this part.
#
# Not handled here: zchaff and MiniSat-p (used by the Minisat/* tests). Both
# are legacy tools with no apt package and no actively maintained source
# distribution; holtest.mk already treats their absence as a soft skip
# (see $(LOGDIR)/Minisat/make-test.ready in holtest.mk), so this script
# leaves that test skipped rather than attempting a fragile build. If you
# need it, see hol-light/Minisat/README and hol-light/Minisat/zc2mso/README.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "install-dependencies.sh <hol-light dir>" >&2
  exit 1
fi

hol_light_dir=$(cd "$1" && pwd)
bin_dir="$hol_light_dir/external-bin"
mkdir -p "$bin_dir"

# ---------------------------------------------------------------------------
# 1. apt dependencies
# ---------------------------------------------------------------------------

required_apt_packages=(
  build-essential   # to build cadical, lrat-trim, prover9 from source
  cmake              # cadical's build uses ./configure + make, lrat-trim too; cmake kept for safety on some branches
  git
  curl
  coinor-csdp        # Examples/sos.ml -> csdp
  maxima             # WZ/maxima.ml -> maxima
  pari-gp            # Library/prime-pratt, Library/prime-pocklington -> gp
  libocamlgraph-ocaml-dev  # QBF -> ocamlgraph
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

# ---------------------------------------------------------------------------
# 2. cadical + lrat-trim (built from source into $bin_dir)
# ---------------------------------------------------------------------------

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

if [ ! -x "$bin_dir/cadical" ]; then
  echo "Building cadical..."
  git clone --depth 1 https://github.com/arminbiere/cadical "$build_dir/cadical"
  (cd "$build_dir/cadical" && ./configure && make -j"$(nproc)")
  cp "$build_dir/cadical/build/cadical" "$bin_dir/cadical"
else
  echo "cadical already present in $bin_dir, skipping build."
fi

if [ ! -x "$bin_dir/lrat-trim" ]; then
  echo "Building lrat-trim..."
  git clone --depth 1 https://github.com/arminbiere/lrat-trim "$build_dir/lrat-trim"
  (cd "$build_dir/lrat-trim" && ./configure && make)
  cp "$build_dir/lrat-trim/lrat-trim" "$bin_dir/lrat-trim"
else
  echo "lrat-trim already present in $bin_dir, skipping build."
fi

# ---------------------------------------------------------------------------
# 3. prover9 (built from source into $bin_dir)
# ---------------------------------------------------------------------------

if [ ! -x "$bin_dir/prover9" ] || [ ! -x "$bin_dir/prooftrans" ]; then
  echo "Building prover9 (LADR)..."
  ladr_tarball_url="https://www.cs.unm.edu/~mccune/prover9/download/LADR-2009-11A.tar.gz"
  curl -fsSL -o "$build_dir/ladr.tar.gz" "$ladr_tarball_url"
  mkdir "$build_dir/ladr"
  tar xzf "$build_dir/ladr.tar.gz" -C "$build_dir/ladr" --strip-components=1
  # The 2009 LADR sources predate C99's stricter rules and GCC 14+ now turns
  # implicit-int / implicit-function-declaration / K&R definitions into hard
  # errors. LADR's Makefiles expose an $(XFLAGS) hook that is prepended to
  # CFLAGS, so downgrade those back to warnings there. Also build serially:
  # LADR's top-level Makefile runs each subdir's `all` (which includes an
  # `install` that mv's the binary into ./bin) and is not -j safe.
  ladr_xflags="-Wno-implicit-int -Wno-implicit-function-declaration -fcommon"
  (cd "$build_dir/ladr" && make all XFLAGS="$ladr_xflags")
  # HOL Light's Examples/prover9.ml runs a "prover9 -f ... | prooftrans ivy"
  # pipeline, so both binaries are needed on PATH, not just prover9.
  cp "$build_dir/ladr/bin/prover9" "$bin_dir/prover9"
  cp "$build_dir/ladr/bin/prooftrans" "$bin_dir/prooftrans"
else
  echo "prover9 and prooftrans already present in $bin_dir, skipping build."
fi

echo
echo "Done. Add this to PATH before running holtest.mk, e.g.:"
echo "  export PATH=\"$bin_dir:\$PATH\""
echo
echo "Not installed (legacy, no apt package, no maintained source): zchaff, MiniSat-p."
echo "The Minisat/make-test target in holtest.mk will be skipped without it."
