#!/usr/bin/env bash
# Fail on Lua globals the addon writes by accident. A global written from addon code is
# tainted: any Blizzard code that reads the same name afterwards runs tainted too, and in
# combat that blocks Blizzard's protected calls and blames SanctuaryUI. Intended globals are
# listed below. Uses luac's listing (SETGLOBAL), so it needs luac5.1 (or luac).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAC="$(command -v luac5.1 || command -v luac)"
ALLOWED='^(SanctuaryUI|SanctuaryUIDB|SanctuaryUILog|SANCTUARYUI[A-Z0-9_]*|SLASH_[A-Z0-9_]+|BINDING_[A-Z0-9_]+|GetMinimapShape|ClickCastFrames)$'
bad=0
while IFS= read -r -d '' f; do
  while read -r name line; do
    if [[ ! "$name" =~ $ALLOWED ]]; then
      echo "${f#$ROOT/}:$line: writes global $name"
      bad=1
    fi
  done < <("$LUAC" -p -l "$f" | sed -nE 's/.*\[([0-9]+)\][[:space:]]+SETGLOBAL.*; (.*)$/\2 \1/p' | sort -u)
done < <(find "$ROOT/SanctuaryUI" -name '*.lua' -not -path '*/libs/*' -print0)
if [[ $bad -ne 0 ]]; then
  echo "Make these local, or add them to ALLOWED in tools/check_globals.sh if they are meant to be global." >&2
  exit 1
fi
echo "globals: ok"
