#!/usr/bin/env bash
# Normalized JPMS descriptor report for the given jars. Output is byte-stable:
# jars sorted by basename, descriptor body lines sorted, trailing space stripped.
# Pins the JDK itself (SPIKE_JDK, default 17) so callers cannot forget.
set -euo pipefail
. "$(dirname "$0")/jdk-select.sh"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <jar>..." >&2
  exit 2
fi

for jar in $(printf '%s\n' "$@" | sort -t/ -k99); do
  [ -f "$jar" ] || { echo "=== $(basename "$jar") ===" ; echo "MISSING FILE"; echo; continue; }
  echo "=== $(basename "$jar") ==="
  if unzip -l "$jar" | grep -qE ' module-info\.class$'; then
    echo "HAS module-info.class"
    ./scripts/jdk-run jar --describe-module --file="$jar" \
      | { head -1; tail -n +2 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort; }
  else
    echo "NO module-info.class (automatic module)"
    ./scripts/jdk-run jar --describe-module --file="$jar" 2>&1 \
      | grep -E '@|automatic' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort || true
  fi
  echo
done
