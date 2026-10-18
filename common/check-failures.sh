#!/bin/bash
# check-failures.sh <file-or-dir>...
#
# Scans benchmark log/output files for signs of failure and reports any file
# that contains one. Exits 0 if none are found (all clear), 1 if at least one
# file looks failed, and 2 on a usage error.
#
# This is deliberately benchmark-agnostic: it uses ONE suspicious-marker
# pattern for every kind of output (HOL Light holtest.mk logs, s2n-bignum
# '*.correct' proof logs, etc.), rather than a per-benchmark rule, so there is
# a single place that decides "what a failure looks like".
#
# What counts as suspicious (case-insensitive):
#   error:                  - diagnostic errors from OCaml/HOL Light and from
#                             s2n-bignum's proof runner (matches the grep in
#                             s2n-bignum's tools/run-proof.sh).
#   exception:              - uncaught exceptions printed by the REPL/proof.
#   error in included file  - HOL Light's loadt/needs wrapper message, printed
#                             when loading a file aborts. This is the reliable
#                             fatal marker for holtest logs.
#
# Known-benign lines that look suspicious but are NOT failures, so they are
# excluded:
#   '### Error: skip ...'   - holtest.mk's own marker for a deliberately
#                             skipped test (e.g. a missing external tool).
#
# Note: 'Exception: Not_found.' is intentionally NOT excluded. It was once
# treated as benign (it shows up at the end of the Library/apery log), but
# that turned out to hide a real problem -- holtest.mk's TESTS list points at
# 'Library/apery' while the file actually lives at 'Examples/apery.ml', so the
# test loads nothing and the stray Not_found is the only evidence. Catching it
# is the desired behavior.
#
# Scope note: this inspects log CONTENT only. It cannot tell that a run was
# interrupted and never produced output (e.g. a HOL Light test whose '.ready'
# marker is missing). For that fuller pass/fail/skip/missing view of a
# holtest run, use hol-light/collect-results.py.
#
# Arguments may be files or directories; directories are searched recursively
# for regular files. Point this at OUTPUT/log files only -- not at source
# trees, since source code (e.g. HOL Light '.ml' files) can legitimately
# contain the words 'Error:' / 'Exception:' in string literals and would be
# false-flagged. For s2n-bignum, pass the '*.correct' logs (run.sh does this);
# for holtest, the log directory is already output-only. Example:
#   check-failures.sh /tmp/hol-light-test
#   check-failures.sh arm/*/*.correct
set -uo pipefail

if [ "$#" -lt 1 ]; then
  echo "check-failures.sh <file-or-dir>..." >&2
  exit 2
fi

SUSPICIOUS='error:|exception:|error in included file'
BENIGN='^### Error: skip'

# Collect candidate files.
files=()
for arg in "$@"; do
  if [ -d "$arg" ]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$arg" -type f -print0 2>/dev/null)
  elif [ -e "$arg" ]; then
    files+=("$arg")
  else
    echo "warning: '$arg' does not exist, skipping" >&2
  fi
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "No files found under: $*" >&2
  exit 0
fi

# A file is failed if it has a suspicious line that is NOT a benign line.
# Implemented as: suspicious lines, minus benign lines; non-empty -> failed.
failed=()
for f in "${files[@]}"; do
  if grep -I -i -E -- "$SUSPICIOUS" "$f" 2>/dev/null \
       | grep -i -v -E -- "$BENIGN" \
       | grep -q .; then
    failed+=("$f")
  fi
done

if [ "${#failed[@]}" -eq 0 ]; then
  echo "No failures detected in ${#files[@]} file(s)."
  exit 0
fi

echo "Failures detected in ${#failed[@]} of ${#files[@]} file(s):"
for f in "${failed[@]}"; do
  echo "  $f"
done
exit 1
