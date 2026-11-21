#!/usr/bin/env python3
"""Build Rock Bottom's tables (SanctuaryUI/MiningNodes.lua, SanctuaryUI/MiningRecipes.lua).

Sources:
  * GatherLite (github.com/Wuild/GatherLite, MIT, by Wuild): which object IDs make each vein, its
    skill colours (scripts/nodes.lua), and the Forever node coordinates imported from Wowhead
    (plugins/database/data/forever.lua). Fetched at the commit pinned below, cached locally.
  * QuestieDB on the game install: object, item and NPC names, where the mining people stand,
    and zone names (the baked TOC store, decoded by build_cookbook_data.questie).
  * WhatsTraining (Crafting/Recipes/Camelot/Mining.lua): every smelt, rank and how it's learned.
  * AtlasLoot (Data/Profession.lua, profession 7): what goes into each smelt.

The book's words (quips, the route, the tales, what each vein yields) live in
SanctuaryUI/MiningData.lua and are written by hand; this tool never touches them.

  * tools/mining-finds/*.txt: players' shared finds ("RB1:" strings from Rock Bottom's Export,
    sent in on the mining finds issue form). A find is taken when its vein already grows on that
    map and it isn't on a known spot; it then ships as an ordinary spot.

  python3 tools/build_mining_data.py [--wow "<World of Warcraft/_forever_>"] [--gatherlite DIR] [--report]

Coordinates are packed per zone as a string of 6 digits a point (x then y, thousandths of the
map), decoded only when a map is drawn. Points of one vein closer than MERGE on a map are one.
"""
from __future__ import annotations

import argparse
import re
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_cookbook_data import DEFAULT_WOW, lua_value, q, questie, zone_names, dungeon_names, lines_between  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FINDS = ROOT / "tools" / "mining-finds"
DATA = ROOT / "SanctuaryUI" / "MiningData.lua"
NODES_OUT = ROOT / "SanctuaryUI" / "MiningNodes.lua"
RECIPES_OUT = ROOT / "SanctuaryUI" / "MiningRecipes.lua"
GATHERLITE = "Wuild/GatherLite"
GATHERLITE_COMMIT = "4ace5b625a1ee724ca912262509f641b4f35992a"  # 2026-11-15
GATHERLITE_FILES = ("scripts/nodes.lua", "plugins/database/data/forever.lua")
CACHE = Path.home() / ".cache" / "sanctuaryui" / ("gatherlite-" + GATHERLITE_COMMIT[:12])
MINING = 7  # AtlasLoot's profession number
MERGE = 0.004  # points nearer than this (a fraction of the map) are the same spot

# Names Questie has no row for, by GatherLite's key.
NAMES = {"poor_copper_vein": "Poor Copper Vein"}

# Reagents AtlasLoot doesn't carry yet (Forever's), from the spells' Wowhead Forever tooltips
# (November 2026): spell -> [(item, count)].
FIX_NEEDS = {
    1230161: [(2835, 1), (2840, 1)],  # Lodestone: Rough Stone, Copper Bar
    1249637: [(249426, 2), (3857, 1)],  # Smelt Azerothium: Pitchblende, Coal
    1306126: [(248815, 1)],  # Smelt Heavy Thorium: Heavy Thorium Ore (at a Molten Foundry)
}

# Skill colours where warcraft.wiki.gg's Forever_mining_techniques differs from GatherLite:
# key -> (orange, yellow, green, grey).
FIX_LEVELS = {
    "rich_thorium_vein": (275, 300, 325, 375),
}

# Mining people Questie lists that aren't really there (template rows) or teach nothing.
NOT_PEOPLE = {2222, 4999, 12035, 12044, 1254, 1256}


def gatherlite(folder: Path | None) -> dict[str, str]:
    out = {}
    for rel in GATHERLITE_FILES:
        path = (folder / rel) if folder else (CACHE / rel)
        if not path.exists():
            if folder:
                raise SystemExit(f"{path} is missing")
            url = f"https://raw.githubusercontent.com/{GATHERLITE}/{GATHERLITE_COMMIT}/{rel}"
            print(f"fetching {url}", file=sys.stderr)
            path.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(url, timeout=60) as r:
                path.write_bytes(r.read())
        out[rel] = path.read_text(encoding="utf8", errors="replace")
    return out


def ore_nodes(text: str):
    """GatherLite's ore rows, in its order: key, ids, colours, aliases."""
    rx = re.compile(r'InsertObject\("ore",\s*\{([^}]*)\},\s*"(\w+)",\s*"[^"]*",\s*\{([^}]*)\}(?:,\s*\{([^}]*)\})?')
    nodes = []
    for m in rx.finditer(text):
        nodes.append({
            "ids": [int(x) for x in m.group(1).split(",") if x.strip()],
            "key": m.group(2),
            "levels": [int(x) for x in m.group(3).split(",") if x.strip()],
            "aliases": re.findall(r'"(\w+)"', m.group(4) or ""),
        })
    return nodes


def points(text: str) -> dict[int, dict[int, list[tuple[float, float]]]]:
    """forever.lua: [objectID][uiMapID] = { x, y, ... }."""
    out: dict[int, dict[int, list]] = {}
    obj = None
    for line in text.split("\n"):
        m = re.match(r"^    \[(\d+)\] = \{", line)
        if m:
            obj = int(m.group(1))
            out[obj] = {}
            continue
        m = re.match(r"^        \[(\d+)\] = \{", line)
        if m and obj is not None:
            zone = int(m.group(1))
            out[obj][zone] = []
            continue
        if obj is not None and out[obj]:
            zone = list(out[obj])[-1]
            nums = [float(x) for x in re.findall(r"\d+(?:\.\d+)?", line)]
            out[obj][zone].extend(nums)
    for obj, zones in out.items():
        for zone, nums in zones.items():
            zones[zone] = list(zip(nums[0::2], nums[1::2]))
    return out


def merge(spots):
    kept = []
    for x, y in sorted(spots):
        if not any(abs(x - a) < MERGE and abs(y - b) < MERGE for a, b in kept[-40:]):
            kept.append((x, y))
    return kept


def pack(spots) -> str:
    return "".join("%03d%03d" % (min(999, round(x * 1000)), min(999, round(y * 1000))) for x, y in spots)


def rb_sum(text: str) -> str:
    """MiningShare.lua's checksum."""
    a, b = 1, 0
    for ch in text.encode("utf8"):
        a = (a + ch) % 65521
        b = (b + a) % 65521
    return "%04x" % ((b * 65536 + a) % 65536)


def shared_finds(notes: list[str]):
    """Every find in tools/mining-finds: [(code, map, x, y, file)]."""
    out = []
    if not FINDS.is_dir():
        return out
    for path in sorted(FINDS.glob("*.txt")):
        text = path.read_text(encoding="utf8", errors="replace")
        for body, s in re.findall(r"RB1:([a-z0-9.;]*):([0-9a-fA-F]{4})", text):
            if rb_sum(body) != s.lower():
                notes.append(f"{path.name}: a string's checksum doesn't match, skipped")
                continue
            for part in body.split(";"):
                m = re.fullmatch(r"([a-z]{2})\.(\d+)\.(\d+)\.(\d+)", part)
                if m:
                    out.append((m.group(1), int(m.group(2)), int(m.group(3)) / 1000, int(m.group(4)) / 1000, path.name))
    return out


def codes() -> dict[str, str]:
    """MiningData.lua's D.CODE: code -> vein key."""
    text = DATA.read_text(encoding="utf8")
    block = text[text.index("D.CODE = {"):]
    block = block[:block.index("}")]
    return {code: key for key, code in re.findall(r'(\w+) = "([a-z]{2})"', block)}


def map_names(addons: Path) -> dict[int, str]:
    """uiMapID -> zone name, from Questie's area table (the zone rows, not sub-zones)."""
    names = {}
    path = addons / "QuestieDB" / "support" / "Forever" / "Zones" / "areaIdToUiMapId.lua"
    for line in path.read_text(encoding="utf8", errors="replace").split("\n"):
        m = re.match(r"\s*\[(\d+)\]\s*=\s*(\d+),\s*--\s*(.+?)\s*$", line)
        if m and "->" not in m.group(3):
            names.setdefault(int(m.group(2)), m.group(3))
    return names


def smelt_reagents(addons: Path):
    prof = addons / "AtlasLootContinued" / "Data" / "Profession.lua"
    rx = re.compile(r"\[(\d+)\]\s*=\s*\{\s*(nil|\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*\{([^}]*)\},\s*\{([^}]*)\}(?:,\s*(\d+))?\s*\}")
    out = {}
    for start in (r"PROFESSION_DATA\.CLASSIC = \{", r"PROFESSION_DATA\.FOREVER = \{"):
        for line in lines_between(prof, start):
            m = rx.search(line)
            if m and int(m.group(3)) == MINING:
                out[int(m.group(1))] = {
                    "skill": int(m.group(4)), "yellow": int(m.group(5)), "grey": int(m.group(6)),
                    "needs": list(zip([int(x) for x in m.group(7).split(",") if x.strip()],
                                      [int(x) for x in m.group(8).split(",") if x.strip()])),
                    "makes": int(m.group(9) or 1),
                }
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wow", type=Path, default=DEFAULT_WOW)
    ap.add_argument("--gatherlite", type=Path, help="a GatherLite checkout to read instead of the pinned download")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    addons = args.wow / "Interface" / "AddOns"
    for need in ("AtlasLootContinued", "WhatsTraining", "QuestieDB"):
        if not (addons / need).is_dir():
            print(f"{need} isn't installed under {addons}", file=sys.stderr)
            return 1
    notes: list[str] = []
    gl = gatherlite(args.gatherlite)
    nodes = ore_nodes(gl["scripts/nodes.lua"])
    for n in nodes:
        if n["key"] in FIX_LEVELS:
            n["levels"] = list(FIX_LEVELS[n["key"]])
    spots = points(gl["plugins/database/data/forever.lua"])
    db = questie(addons / "QuestieDB" / "QuestieDB_Forever.toc")
    objects, items, npcs = db["Object"], db["Item"], db["Npc"]
    maps = map_names(addons)
    zones = zone_names(addons)
    dungeons = dungeon_names(addons)

    # --- veins -------------------------------------------------------------------------
    rows, packed, used_maps = [], {}, set()
    total = 0
    by_code = codes()
    shared = defaultdict(list)  # (key, map) -> [(x, y)]
    for code, zone, x, y, name in shared_finds(notes):
        key = by_code.get(code)
        if not key:
            notes.append(f"{name}: unknown vein code {code}")
            continue
        shared[(key, zone)].append((x, y))
    merged_in = 0
    for node in nodes:
        name = NAMES.get(node["key"])
        for i in node["ids"]:
            if not name and isinstance(objects.get(i, {}).get(1), str):
                name = objects[i][1]
        if not name:
            name = node["key"].replace("_", " ").title()
            notes.append(f"no name for {node['key']}: guessed {name}")
        by_map = defaultdict(list)
        for i in node["ids"]:
            for zone, list_ in spots.get(i, {}).items():
                by_map[zone].extend(list_)
        zones_out = {}
        for zone, list_ in sorted(by_map.items()):
            known = merge(list_)
            extra = [p for p in shared.get((node["key"], zone), [])
                     if not any(abs(p[0] - a) < MERGE * 1.5 and abs(p[1] - b) < MERGE * 1.5 for a, b in known)]
            kept = merge(list_ + extra)
            merged_in += len(kept) - len(known)
            if kept:
                zones_out[zone] = pack(kept)
                used_maps.add(zone)
                total += len(kept)
        node["name"] = name
        node["count"] = sum(len(s) // 6 for s in zones_out.values())
        packed[node["key"]] = zones_out
        rows.append(node)
        if not zones_out:
            notes.append(f"{name}: no coordinates")
    grows = {(n["key"], z) for n in rows for z in packed[n["key"]]}
    for (key, zone), finds in sorted(shared.items()):
        if (key, zone) not in grows:
            notes.append(f"{len(finds)} shared {key} finds on map {zone} left out: it doesn't grow there")
    for zone in sorted(used_maps):
        if zone not in maps:
            notes.append(f"map {zone} has no name")

    w = []
    w.append("SanctuaryUI = SanctuaryUI or {}")
    w.append("local ns = SanctuaryUI")
    w.append("ns.MiningData = ns.MiningData or {}")
    w.append("local D = ns.MiningData")
    w.append("")
    w.append("-- GENERATED by tools/build_mining_data.py. Don't edit by hand: run the tool again.")
    w.append(f"-- Node coordinates and skill colours: GatherLite (github.com/{GATHERLITE}, commit {GATHERLITE_COMMIT[:12]}),")
    w.append("-- MIT licensed, Copyright (c) 2019 Wuild; its Forever database is imported from Wowhead.")
    w.append(f"-- Players' shared finds (tools/mining-finds): {merged_in} spots. Names: QuestieDB.")
    w.append("--")
    w.append("-- D.VEINS, in GatherLite's order: key, name, ids (object IDs), skill (to mine it), yellow, green,")
    w.append("--   grey (the skill-up colours; absent where only the minimum is published), also (other names the")
    w.append("--   node goes by: starter and ooze-covered kinds), points (spots known).")
    w.append("-- D.SPOTS[key][uiMapID] = \"xxxyyy...\": 6 digits a spot, thousandths of the map.")
    w.append("-- D.MAPS[uiMapID] = zone name.")
    w.append("")
    w.append("D.VEINS = {")
    for n in rows:
        lv = n["levels"]
        parts = [f"key = {q(n['key'])}", f"name = {q(n['name'])}", "ids = { " + ", ".join(map(str, n["ids"])) + " }", f"skill = {lv[0]}"]
        if len(lv) == 4:
            parts += [f"yellow = {lv[1]}", f"green = {lv[2]}", f"grey = {lv[3]}"]
        also = sorted({a.replace("_", " ").title() for a in n["aliases"]} - {n["name"]})
        if also:
            parts.append("also = { " + ", ".join(q(a) for a in also) + " }")
        parts.append(f"points = {n['count']}")
        w.append("\t{ " + ", ".join(parts) + " },")
    w.append("}")
    w.append("")
    w.append("D.MAPS = {")
    for zone in sorted(used_maps):
        w.append(f"\t[{zone}] = {q(maps.get(zone, 'Map ' + str(zone)))},")
    w.append("}")
    w.append("")
    w.append("D.SPOTS = {")
    for n in rows:
        if not packed[n["key"]]:
            continue
        w.append(f"\t{n['key']} = {{")
        for zone, s in packed[n["key"]].items():
            w.append(f"\t\t[{zone}] = \"{s}\",")
        w.append("\t},")
    w.append("}")
    NODES_OUT.write_text("\n".join(w) + "\n", encoding="utf8")

    # --- smelting, ranks, people ---------------------------------------------------------
    learned = []
    for line in (addons / "WhatsTraining" / "Crafting" / "Recipes" / "Camelot" / "Mining.lua").read_text(encoding="utf8", errors="replace").split("\n"):
        if re.match(r"\s*\{ spell = \d+", line):
            learned.append(lua_value(line))
    reagents = smelt_reagents(addons)
    used_items: dict[int, str] = {}

    def item(i):
        name = items.get(i, {}).get(1)
        if not name:
            notes.append(f"no name for item {i}")
            return None
        used_items[i] = name
        return name

    ranks, smelts = [], []
    for row in learned:
        if row.get("rank"):
            ranks.append(row)
            continue
        product = row.get("creates")
        if not product or not item(product):
            notes.append(f"smelt {row.get('spell')}: no product")
            continue
        al = reagents.get(row["spell"], {})
        needs = [(i, c) for i, c in (FIX_NEEDS.get(row["spell"]) or al.get("needs", [])) if item(i)]
        if not al and row["spell"] not in FIX_NEEDS:
            notes.append(f"{used_items[product]} ({row['spell']}): not in AtlasLoot, no reagents")
        teach = row.get("teach")
        if teach:
            item(teach)
        smelts.append({**row, "needs": needs, "yellow": al.get("yellow"), "grey": al.get("grey"),
                       "makes": max(al.get("makes", 1), row.get("count", 1))})

    people = {}
    for n, r in npcs.items():
        title = r.get(14) or ""
        if not isinstance(title, str) or n in NOT_PEOPLE:
            continue
        if not re.search(r"Min(ing|er)|Smelter", title):
            continue
        spawns = r.get(7) or {}
        if isinstance(spawns, list):
            spawns = {i + 1: v for i, v in enumerate(spawns) if v}
        if not spawns:
            notes.append(f"{r.get(1)} ({n}): no spawn, left out")
            continue
        zone = r.get(9) if r.get(9) in spawns else next(iter(spawns))
        spot = (spawns.get(zone) or [[0, 0]])[0]
        where = zones.get(zone, "")
        if spot[0] < 0 or zone in dungeons:
            where, spot = dungeons.get(zone) or where, [0, 0]
        side = {"A": "A", "H": "H", "AH": "N"}.get(r.get(13) or "", "N")
        kind = "trainer" if re.search(r"Trainer|^Miner$", title) else "smelter" if "Smelter" in title else "supplies"
        people[n] = (r[1], where, round(spot[0], 1), round(spot[1], 1), side, title, kind)

    w = []
    w.append("SanctuaryUI = SanctuaryUI or {}")
    w.append("local ns = SanctuaryUI")
    w.append("ns.MiningData = ns.MiningData or {}")
    w.append("local D = ns.MiningData")
    w.append("")
    w.append("-- GENERATED by tools/build_mining_data.py from WhatsTraining, AtlasLoot and QuestieDB on the game")
    w.append("-- install. Don't edit by hand: fix a fact in MiningData.lua or run the tool again.")
    w.append("--")
    w.append("-- D.SMELTS, by skill: spell, item (what it makes), skill, yellow/grey (absent where unknown), makes,")
    w.append("--   needs { item, count }, how (trainer, quest, drop), cost (copper), teach (the item that teaches")
    w.append("--   it), quests { id, side }, auto (known from the start).")
    w.append("")
    w.append("D.SMELTS = {")
    for s in sorted(smelts, key=lambda s: (s.get("skill", 0), s["spell"])):
        parts = [f"spell = {s['spell']}", f"item = {s['creates']}", f"skill = {s.get('skill', 1)}"]
        if s.get("yellow"):
            parts += [f"yellow = {s['yellow']}", f"grey = {s['grey']}"]
        if s["makes"] > 1:
            parts.append(f"makes = {s['makes']}")
        parts.append("needs = { " + ", ".join(f"{{ {i}, {c} }}" for i, c in s["needs"]) + " }")
        parts.append("how = { " + ", ".join(q(x) for x in s.get("source", [])) + " }")
        if s.get("cost"):
            parts.append(f"cost = {s['cost']}")
        if s.get("teach"):
            parts.append(f"teach = {s['teach']}")
        if s.get("quests"):
            parts.append("quests = { " + ", ".join(f"{{ {qid}, {q({'Alliance': 'A', 'Horde': 'H'}.get(f, 'N'))} }}" for qid, f in s["quests"]) + " }")
        if s.get("autoLearned"):
            parts.append("auto = true")
        w.append("\t{ " + ", ".join(parts) + " },")
    w.append("}")
    w.append("")
    w.append("-- Ranks from the trainer: name, skill needed, spell, cost (copper).")
    w.append("D.RANK_SPELLS = {")
    for r in ranks:
        w.append(f"\t{{ {q(r['rank'])}, {r['skill']}, {r['spell']}, {r.get('cost', 0)} }},")
    w.append("}")
    w.append("")
    w.append("-- Mining people: name, zone, x, y, side (A, H, N for both), title, kind (trainer, supplies, smelter).")
    w.append("D.NPC = {")
    for n in sorted(people):
        p = people[n]
        w.append(f"\t[{n}] = {{ {q(p[0])}, {q(p[1])}, {p[2]}, {p[3]}, {q(p[4])}, {q(p[5])}, {q(p[6])} }},")
    w.append("}")
    w.append("")
    w.append("-- Item names the smelts use.")
    w.append("D.ITEM = {")
    for i in sorted(used_items):
        w.append(f"\t[{i}] = {q(used_items[i])},")
    w.append("}")
    RECIPES_OUT.write_text("\n".join(w) + "\n", encoding="utf8")

    print(f"{merged_in} spots from shared finds")
    print(f"{len(rows)} veins, {total} spots on {len(used_maps)} maps; {len(smelts)} smelts, {len(ranks)} ranks, {len(people)} people")
    if args.report or notes:
        for n in notes:
            print("  " + n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
