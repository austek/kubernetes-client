#!/usr/bin/env bash
# Source this to pin JAVA_HOME. Select with SPIKE_JDK (default 17).
# Shell state does not persist between tool calls, so every command that
# needs a JDK must pin it itself rather than relying on a previous export.
case "${SPIKE_JDK:-17}" in
  11) _jh="$HOME/.sdkman/candidates/java/11.0.24-zulu" ;;
  17) _jh="$HOME/.sdkman/candidates/java/17.0.19-zulu" ;;
  21) _jh="$HOME/.sdkman/candidates/java/21-zulu" ;;
  *)  echo "jdk-select: unsupported SPIKE_JDK='${SPIKE_JDK}' (use 11, 17 or 21)" >&2; exit 2 ;;
esac
if [ ! -x "$_jh/bin/java" ]; then
  echo "jdk-select: no JDK at $_jh" >&2
  exit 2
fi
export JAVA_HOME="$_jh"
export PATH="$JAVA_HOME/bin:$PATH"
