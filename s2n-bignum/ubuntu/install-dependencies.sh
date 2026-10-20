#!/bin/bash
# install-dependencies.sh
#
# Checks the apt packages needed to build & check the s2n-bignum HOL Light
# proofs for BOTH architectures (arm/ and x86/) on this machine. If any are
# missing it prints the apt-get line and exits non-zero, rather than
# installing anything itself.
#
# Why cross toolchains: s2n-bignum assembles each architecture's .S sources
# into object files that the proofs are checked against. On the native arch
# the stock `as`/`objdump` are used; for the OTHER architecture the Makefiles
# call the cross tools (e.g. x86/Makefile uses `x86_64-linux-gnu-as` when not
# on x86_64, arm/Makefile uses `aarch64-linux-gnu-as` when not on aarch64).
# So on an arm64 box you need the x86_64 cross toolchain to check the x86
# proofs, and on an x86_64 box you need the aarch64 cross toolchain for the
# arm proofs. We also pull the cross gcc (not just binutils): the Makefiles'
# preprocess step runs $(CC) -E, and a matching cross gcc is the least
# surprising choice for the foreign target.
#
# Note: building/checking the proofs does not EXECUTE the foreign code, so no
# emulator (qemu) is needed here -- that is only required for the sematest /
# cosimulation targets, which this benchmark flow does not run.
set -euo pipefail

host_arch=$(uname -m)

# Packages needed regardless of arch (HOL Light proof scaffolding + tools the
# s2n-bignum proof/build scripts call). Mirrors the CI "proofs" job.
common_packages=(
  build-essential   # native as/objdump/gcc for the host arch
  git
  python3
  libpcre2-dev
  libgmp-dev
  libstring-shellquote-perl
  xdot
)

# The foreign-architecture cross toolchain (binutils = as/objdump, plus gcc).
case "$host_arch" in
  aarch64|arm64)
    cross_packages=(binutils-x86-64-linux-gnu gcc-x86-64-linux-gnu)
    cross_desc="x86_64 cross toolchain (to check the x86/ proofs on this arm64 host)"
    ;;
  x86_64|amd64)
    cross_packages=(binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu)
    cross_desc="aarch64 cross toolchain (to check the arm/ proofs on this x86_64 host)"
    ;;
  *)
    echo "Unsupported host architecture '$host_arch' (expected aarch64 or x86_64)." >&2
    exit 1
    ;;
esac

echo "Host architecture: $host_arch"
echo "Foreign toolchain needed: $cross_desc"
echo

required_packages=("${common_packages[@]}" "${cross_packages[@]}")

missing_packages=()
for pkg in "${required_packages[@]}"; do
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

echo "All required apt packages and cross toolchains are present."
