#!/usr/bin/env bash
# Reports any package contained in more than one of the given jars.
# JPMS forbids split packages on the module path; OSGi tolerated them.
# Pins the JDK itself (SPIKE_JDK, default 17) so callers cannot forget.
set -euo pipefail
export LC_ALL=C
. "$(dirname "$0")/jdk-select.sh"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <jar>..." >&2
  exit 2
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for jar in "$@"; do
  [ -f "$jar" ] || continue
  unzip -l "$jar" \
    | awk '{print $4}' \
    | grep -E '\.class$' \
    | grep -v -E '^(META-INF|OSGI-INF|WEB-INF)/' \
    | grep -v -E '(^|/)module-info\.class$' \
    | sed 's#/[^/]*$##; s#/#.#g' \
    | sort -u \
    | while read -r pkg; do [ -n "$pkg" ] && echo "$pkg $(basename "$jar")"; done >> "$tmp"
done

found=0
while read -r pkg jars; do
  echo "SPLIT $pkg $jars"
  found=1
done < <(sort "$tmp" | awk '{a[$1]=a[$1]" "$2; n[$1]++} END {for (p in n) if (n[p]>1) print p, a[p]}' | sort)

[ "$found" -eq 0 ] && echo "OK no split packages"
exit "$found"
