#!/usr/bin/env bash
# Normalized JPMS descriptor report for the given jars. Output is byte-stable:
# jars sorted by basename, descriptor body lines sorted, trailing space stripped.
# Pins the JDK itself (SPIKE_JDK, default 17) so callers cannot forget.
set -euo pipefail
export LC_ALL=C
. "$(dirname "$0")/jdk-select.sh"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <jar>..." >&2
  exit 2
fi

# Sort by basename, not full path: block order must not depend on where a jar
# happens to live, or cross-branch diffs reorder for irrelevant reasons.
# `sort -t/ -k99` does NOT do this — an out-of-range key makes GNU sort fall
# back to comparing the whole line, i.e. the full path.
while IFS= read -r jar; do
  [ -f "$jar" ] || { echo "=== $(basename "$jar") ===" ; echo "MISSING FILE"; echo; continue; }
  echo "=== $(basename "$jar") ==="
  if unzip -l "$jar" | grep -qE ' module-info\.class$'; then
    echo "HAS module-info.class"
    # Capture once: piping the same command's output into both `head` and
    # `tail` races on the pipe buffer and silently drops the `tail` half.
    mod_desc="$(jar --describe-module --file="$jar")"
    printf '%s\n' "$mod_desc" | head -1
    printf '%s\n' "$mod_desc" | tail -n +2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort
  else
    # `jar --describe-module` exits non-zero when the filename cannot yield a
    # legal automatic module name (e.g. `-999-SNAPSHOT`). Record what it says
    # rather than filtering it away, and do not let it abort the loop.
    echo "NO module-info.class (automatic module)"
    jar --describe-module --file="$jar" 2>&1 \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
      | grep -v '^$' \
      | sort || true
  fi
  echo
done < <(printf '%s\n' "$@" | awk -F/ '{print $NF "\t" $0}' | sort -k1,1 | cut -f2-)
