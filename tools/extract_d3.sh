#!/usr/bin/env bash
# Pull the modern D3 HUD textures into art-src/hud, then decode them with build_hud_art.py.
#
# Reading CASC straight from /mnt/d is ~70 KB/s under WSL (14+ minutes). This mirrors the
# small index/config files to the Linux disk once and symlinks the large data.NNN archives,
# so a run takes seconds. The folder must be named "Diablo III" for the casc tool.
#
# Needs a jybp/casc build: go build -o /tmp/casc-bin2 ./cmd/casc  (github.com/jybp/casc)
set -euo pipefail

GAME="${GAME:-/mnt/d/Games/Diablo III}"
MIRROR="${MIRROR:-$HOME/.cache/d3mirror/Diablo III}"
CASC="${CASC:-/tmp/casc-bin2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/art-src/hud"

if [ ! -d "$MIRROR/Data/data" ]; then
	mkdir -p "$MIRROR/Data/data"
	cp "$GAME/.build.info" "$GAME/.product.db" "$MIRROR/"
	cp -r "$GAME/Data/config" "$GAME/Data/d3" "$GAME/Data/ecache" "$GAME/Data/indices" "$MIRROR/Data/"
	cp "$GAME"/Data/data/*.idx "$MIRROR/Data/data/"
	for f in "$GAME"/Data/data/data.*; do ln -sf "$f" "$MIRROR/Data/data/"; done
fi

mkdir -p "$OUT"
for n in BottomBar_GameRes BottomBar_GameRes_DH 2DUIBottomBar bottomBar_buttonFX_frameGlow \
	healthBall_liquid health_liquid_alpha health_hotline_alpha health_hotline_liquid health_hotline_color \
	healthBall_streaks_alpha 2DUIGlows 2DUISkills 2DUIBuffIcons 2DUIEnemyHPbar \
	2DUI_BarbarianResourceGlobe 2DUI_CrusaderResourceGlobe 2DUI_DemonHunterResourceGlobe 2DUI_MonkResourceGlobe \
	2DUI_NecromancerResourceGlobe 2DUI_WitchDoctorResourceGlobe 2DUI_WizardResourceGlobe; do
	echo "Base/Textures/$n.tex"
done | "$CASC" -dir "$MIRROR" -o "$OUT" 2>&1 | grep -E 'FAIL|hud/' || true

python3 "$ROOT/tools/build_hud_art.py"
