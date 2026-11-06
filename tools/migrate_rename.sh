#!/usr/bin/env bash
# One-time move of WoW-side data from the old addon name (Wow3DUI) to SanctuaryUI.
# Run with WoW closed: the client rewrites SavedVariables and bindings on logout.
set -euo pipefail

WOW="${WOW:-/mnt/d/Games/World of Warcraft/_forever_}"
ADDONS="$WOW/Interface/AddOns"
SRC_WIN='\\wsl$\Ubuntu\home\codym\wow3dui\SanctuaryUI'

if tasklist.exe 2>/dev/null | grep -qi '^Wow.exe'; then
	echo "WoW is running. Exit the game first, then rerun." >&2
	exit 1
fi

stamp=$(date +%Y%m%d-%H%M%S)

for acct in "$WOW"/WTF/Account/*/; do
	sv="$acct/SavedVariables"
	if [[ -f "$sv/Wow3DUI.lua" ]]; then
		[[ -f "$sv/SanctuaryUI.lua" ]] && cp "$sv/SanctuaryUI.lua" "$sv/SanctuaryUI.lua.pre-rename-$stamp"
		cp "$sv/Wow3DUI.lua" "$sv/SanctuaryUI.lua"
		echo "settings: $sv/SanctuaryUI.lua"
	fi
	# Key bindings (account and per-character) and per-character AddOns.txt.
	while IFS= read -r -d '' f; do
		if grep -q 'Wow3DUI\|WOW3DUI' "$f"; then
			cp "$f" "$f.pre-rename-$stamp"
			sed -i -e 's/WOW3DUI/SANCTUARYUI/g' -e 's/Wow3DUI/SanctuaryUI/g' "$f"
			echo "renamed in: $f"
		fi
	done < <(find "$acct" \( -name 'bindings-cache.wtf' -o -name 'AddOns.txt' \) -print0)
done

# Swap the AddOns symlink.
cd "$ADDONS"
cmd.exe /c "if exist Wow3DUI rmdir Wow3DUI" >/dev/null 2>&1 || true
if [[ ! -e SanctuaryUI && ! -L SanctuaryUI ]]; then
	# No quotes around the target: WSL interop mangles escaped quotes into extra backslashes.
	cmd.exe /c "mklink /D SanctuaryUI $SRC_WIN"
fi
cmd.exe /c "dir /AL" 2>/dev/null | grep -i -E 'wow3dui|sanctuaryui' || true
echo "done."
