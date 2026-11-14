#!/usr/bin/env python3
"""Build the Cookbook's recipe tables (SanctuaryUI/CookingRecipes.lua) from the game install.

Three addons on the Forever client carry current data, and WowUp keeps them fresh:
  * AtlasLootContinued: every cooking recipe's spell, product, skill colours and reagents
    (Data/Profession.lua, Data/Recipe.lua), and the buff group it files each dish under
    (AtlasLootContinued_Crafting/data-forever.lua);
  * WhatsTraining: how each recipe is learned (trainer and cost, vendor, quest, drop), which
    side can learn it, the ranks (Crafting/Recipes/Camelot/Cooking.lua);
  * QuestieDB: names of items, vendors and quests, where the vendors stand, who drops what
    (the baked TOC store: base64 CBOR rows).

The Cookbook's words (quips, routes, what each dish does) live in SanctuaryUI/CookingData.lua and
are written by hand; this tool never touches them. Run it after a game patch:

  python3 tools/build_cookbook_data.py [--wow "<World of Warcraft/_forever_ folder>"] [--report]

It needs nothing beyond Python 3. --report prints what the sources disagree on or lack.
"""
from __future__ import annotations

import argparse
import base64
import re
import struct
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SanctuaryUI" / "CookingRecipes.lua"
FISHING = ROOT / "SanctuaryUI" / "FishingData.lua"
DEFAULT_WOW = Path("/mnt/d/Games/World of Warcraft/_forever_")
COOKING = 6  # AtlasLoot's profession number


# --- QuestieDB's baked store ------------------------------------------------------------

def cbor(b: bytes, i: int = 0):
    ib = b[i]
    mt, ai = ib >> 5, ib & 31
    i += 1
    if mt == 7:
        if ai == 20:
            return False, i
        if ai == 21:
            return True, i
        if ai in (22, 23):
            return None, i
        size = {25: 2, 26: 4, 27: 8}[ai]
        return struct.unpack(">" + {2: "e", 4: "f", 8: "d"}[size], b[i:i + size])[0], i + size
    if ai < 24:
        n = ai
    else:
        size = {24: 1, 25: 2, 26: 4, 27: 8}[ai]
        n = int.from_bytes(b[i:i + size], "big")
        i += size
    if mt == 0:
        return n, i
    if mt == 1:
        return -1 - n, i
    if mt == 2:
        return b[i:i + n].decode("utf8", "replace"), i + n
    if mt == 3:
        return b[i:i + n].decode("utf8", "replace"), i + n
    if mt == 4:
        out = []
        for _ in range(n):
            v, i = cbor(b, i)
            out.append(v)
        return out, i
    if mt == 5:
        out = {}
        for _ in range(n):
            k, i = cbor(b, i)
            v, i = cbor(b, i)
            out[k] = v
        return out, i
    return cbor(b, i)  # a tag: its content


def questie(toc: Path) -> dict[str, dict[int, dict]]:
    """{ "Item" | "Npc" | "Quest" | "Object": { id: { fieldIndex: value } } }"""
    db: dict[str, dict[int, dict]] = {k: {} for k in ("Item", "Npc", "Quest", "Object")}
    rx = re.compile(r"^## X-(Item|Npc|Quest|Object)-(\d+)-(\w+): (.*)$")
    with open(toc, encoding="utf8", errors="replace") as f:
        for line in f:
            m = rx.match(line.rstrip("\n"))
            if not m or m.group(4).startswith("~"):
                continue
            try:
                value, _ = cbor(base64.b64decode(m.group(4)))
            except Exception:
                continue
            row = db[m.group(1)].setdefault(int(m.group(2)), {})
            if m.group(3) == "S":
                if isinstance(value, dict):
                    row.update(value)
            else:
                row[int(m.group(3))] = value
    return db


# --- the addons' Lua tables, read as text -------------------------------------------------

def lines_between(path: Path, start: str, stop: str = r"^\s?\}|^end") -> list[str]:
    out, on = [], False
    for line in path.read_text(encoding="utf8", errors="replace").split("\n"):
        if not on:
            on = re.search(start, line) is not None
            continue
        if re.match(stop, line):
            break
        out.append(line)
    return out


def atlasloot(addons: Path):
    prof = addons / "AtlasLootContinued" / "Data" / "Profession.lua"
    rx = re.compile(r"\[(\d+)\]\s*=\s*\{\s*(nil|\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*\{([^}]*)\},\s*\{([^}]*)\}(?:,\s*(\d+))?\s*\}")
    spells = {}
    for era, start in (("classic", r"PROFESSION_DATA\.CLASSIC = \{"), ("forever", r"PROFESSION_DATA\.FOREVER = \{")):
        for line in lines_between(prof, start):
            m = rx.search(line)
            if m and int(m.group(3)) == COOKING:
                spells[int(m.group(1))] = {
                    "item": None if m.group(2) == "nil" else int(m.group(2)),
                    "skill": int(m.group(4)), "yellow": int(m.group(5)), "grey": int(m.group(6)),
                    "needs": list(zip([int(x) for x in m.group(7).split(",") if x.strip()],
                                      [int(x) for x in m.group(8).split(",") if x.strip()])),
                    "makes": int(m.group(9) or 1), "era": era,
                }
    recipe_items = defaultdict(list)
    rr = re.compile(r"\[(\d+)\]\s*=\s*\{\s*(\d+),\s*(\d+),\s*(\d+)")
    rec = addons / "AtlasLootContinued" / "Data" / "Recipe.lua"
    for start in (r"RECIPE_DATA\.CLASSIC = \{", r"RECIPE_DATA\.FOREVER = \{"):
        for line in lines_between(rec, start):
            m = rr.search(line)
            if m and int(m.group(2)) == COOKING:
                recipe_items[int(m.group(4))].append(int(m.group(1)))
    text = (addons / "AtlasLootContinued_Crafting" / "data-forever.lua").read_text(encoding="utf8", errors="replace")
    block = text[text.index('data["CookingForever"]'):text.index('data["FirstAidForever"]')]
    groups, group = {}, None
    for line in block.split("\n"):
        m = re.search(r"name = (.*),\s*$", line)
        if m:
            group = m.group(1)
            continue
        m = re.search(r"\{\s*\d+,\s*(\d+)\s*\},\s*--\s*(.*?)\s*/\s*\d+", line)
        if m and "Skill" not in (group or ""):
            groups[int(m.group(1))] = group
    return spells, recipe_items, groups


GROUPS = [  # AtlasLoot's heading -> the Cookbook's group key (longest match first)
    ('"Stamina"].." + "', "stamspi"), ("Stamina", "stamina"), ("Intellect", "intellect"), ("Agility", "agility"),
    ("Strength", "strength"), ("Spirit", "spirit"), ("Mana Per 5", "mp5"), ("Health Per 5", "hp5"),
    ("Special", "special"), ("Food", "food"),
]


def lua_value(text: str):
    """A WhatsTraining recipe row's fields we care about, by regex (its rows are flat enough)."""
    row = {}
    for key in ("spell", "skill", "creates", "count", "teach", "cost", "merchantFavor", "level"):
        m = re.search(r"\b%s = (\d+)" % key, text)
        if m:
            row[key] = int(m.group(1))
    for key in ("rank", "side"):
        m = re.search(r'\b%s = "([^"]+)"' % key, text)
        if m:
            row[key] = m.group(1)
    m = re.search(r"\bbound = (true|false)", text)
    if m:
        row["bound"] = m.group(1) == "true"
    row["autoLearned"] = "autoLearned = true" in text
    m = re.search(r"source = \{([^}]*)\}", text)
    row["source"] = re.findall(r'"(\w+)"', m.group(1)) if m else []
    m = re.search(r"vendors = \{(.*?)\} \}", text)
    row["vendors"] = [(int(n), f or None) for n, f in re.findall(r'\{ npc = (\d+), area = \d+(?:, faction = "(\w+)")? \}', text)]
    row["quests"] = [(int(q), f or None) for q, f in re.findall(r'\{ id = (\d+), area = \d+(?:, faction = "(\w+)")?', text)]
    m = re.search(r"reputation = \{ (\d+), (\d+),", text)
    if m:
        row["standing"] = int(m.group(2))
    return row


def whatstraining(addons: Path):
    path = addons / "WhatsTraining" / "Crafting" / "Recipes" / "Camelot" / "Cooking.lua"
    rows = []
    for line in path.read_text(encoding="utf8", errors="replace").split("\n"):
        if re.match(r"\s*\{ spell = \d+", line):
            rows.append(lua_value(line))
    return rows


def zone_names(addons: Path) -> dict[int, str]:
    names = {}
    path = addons / "QuestieDB" / "support" / "Forever" / "Zones" / "areaIdToUiMapId.lua"
    for line in path.read_text(encoding="utf8", errors="replace").split("\n"):
        m = re.match(r"\s*\[(\d+)\]\s*=\s*\d+,\s*--\s*(.+?)\s*$", line)
        if m:
            names[int(m.group(1))] = m.group(2).split(" -> ")[-1].strip()
    return names


def dungeon_names(addons: Path) -> dict[int, str]:
    names = {}
    path = addons / "QuestieDB" / "support" / "Forever" / "Zones" / "dungeons.lua"
    for line in path.read_text(encoding="utf8", errors="replace").split("\n"):
        m = re.match(r'\s*\[(\d+)\]\s*=\s*\{\s*"([^"]+)"', line)
        if m:
            names[int(m.group(1))] = m.group(2)
    return names


# Trainers the guides name whose Questie rows don't say "cook": id -> side. And people Questie
# can't place yet: id -> zone.
EXTRA_TRAINERS = {249968: "A", 244512: "H", 3191: "H"}  # Hnaz Blunderflame, Ortak Lomgok, Cook Torka
PLACED = {256629: "Mount Hyjal"}  # Dala Fairmaw
ALSO = [8125]  # Dirge Quikcleave, the Artisan quest


def fishing_ids() -> set[int]:
    text = FISHING.read_text(encoding="utf8")
    block = text[text.index("D.FISH = {"):text.index("D.ITEMS = {")]
    return {int(x) for x in re.findall(r"\bid = (\d+)", block)}


# --- putting it together ----------------------------------------------------------------

SIDE = {"A": "A", "H": "H", "AH": "N", "Alliance": "A", "Horde": "H"}
STANDING = {4: "Friendly", 5: "Honored", 6: "Revered", 7: "Exalted"}


def q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wow", type=Path, default=DEFAULT_WOW)
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    addons = args.wow / "Interface" / "AddOns"
    for need in ("AtlasLootContinued", "WhatsTraining", "QuestieDB"):
        if not (addons / need).is_dir():
            print(f"{need} isn't installed under {addons}", file=sys.stderr)
            return 1

    spells, recipe_items, groups = atlasloot(addons)
    learned = whatstraining(addons)
    db = questie(addons / "QuestieDB" / "QuestieDB_Forever.toc")
    items, npcs, quests = db["Item"], db["Npc"], db["Quest"]
    zones = zone_names(addons)
    dungeons = dungeon_names(addons)
    fish = fishing_ids()
    notes: list[str] = []

    def item_name(i):
        name = items.get(i, {}).get(1)
        if not name:
            notes.append(f"no name for item {i}")
        return name

    used_npcs: dict[int, tuple] = {}
    used_items: dict[int, str] = {}

    def npc(n, faction=None):
        """Remember an NPC the book points at; False when Questie can't place it."""
        row = npcs.get(n)
        if not row or not row.get(1):
            notes.append(f"no data for npc {n}")
            return False
        spawns = row.get(7) or {}
        if isinstance(spawns, list):  # a dense table: index = zone
            spawns = {i + 1: v for i, v in enumerate(spawns) if v}
        zone = row.get(9) if row.get(9) in spawns else (next(iter(spawns)) if spawns else row.get(9))
        spot = (spawns.get(zone) or [[0, 0]])[0]
        side = SIDE.get(faction) or SIDE.get(row.get(13) or "") or "N"
        where = PLACED.get(n) or zones.get(zone, "")
        if spot[0] < 0 or zone in dungeons or row.get(9) in dungeons:  # inside an instance: no map spot
            where, spot = dungeons.get(row.get(9)) or dungeons.get(zone) or where, [0, 0]
        used_npcs[n] = (row[1], where, round(spot[0], 1), round(spot[1], 1), side, row.get(14) or "")
        return True

    def use(i):
        name = item_name(i)
        if name:
            used_items[i] = name
        return name

    ranks, recipes = [], []
    by_spell = {row["spell"]: row for row in learned}
    for spell in sorted(set(spells) | set(by_spell)):
        al, wt = spells.get(spell), by_spell.get(spell, {})
        if wt.get("rank"):
            ranks.append(wt)
            continue
        if not wt and al and al["era"] == "classic" and spell not in groups:
            continue  # a vanilla row Forever's lists don't carry (TBC leftovers, the campfire)
        product = (al and al["item"]) or wt.get("creates")
        if not product:
            continue
        name = use(product)
        if not name:
            continue
        r = {"spell": spell, "item": product, "name": name}
        r["skill"] = max(1, wt.get("skill", al["skill"] if al else 1))
        if al:
            if al["skill"] != wt.get("skill", al["skill"]) and wt.get("skill", 0) > 1:
                notes.append(f"{name}: skill {al['skill']} (AtlasLoot) vs {wt['skill']} (WhatsTraining)")
            if al["yellow"] > 0:
                r["yellow"], r["grey"] = al["yellow"], al["grey"]
            r["needs"] = [(i, n) for i, n in al["needs"] if use(i)]
            r["makes"] = max(al["makes"], wt.get("count", 1))
            r["new"] = al["era"] == "forever"
        else:
            notes.append(f"{name} ({spell}): no reagents (not in AtlasLoot)")
            r["needs"], r["makes"], r["new"] = [], wt.get("count", 1), spell > 400000
        for key, group in GROUPS:
            if key in (groups.get(spell) or ""):
                r["group"] = group
                break
        r["level"] = items.get(product, {}).get(10)
        r["fish"] = any(i in fish for i, _ in r["needs"])
        # How it's learned.
        how = list(wt.get("source", []))
        teach = wt.get("teach") or (recipe_items.get(spell) or [None])[-1]
        if teach and use(teach):
            r["recipe"] = teach
        if not how and "recipe" not in r:
            how = ["start" if wt.get("autoLearned") or spell in (2538, 2540) else "trainer"]
        r["how"] = how
        if wt.get("cost"):
            r["cost"] = wt["cost"]
        if wt.get("merchantFavor"):
            r["favor"] = wt["merchantFavor"]
        if wt.get("standing"):
            r["standing"] = STANDING.get(wt["standing"], str(wt["standing"]))
        if wt.get("bound"):
            r["bound"] = True
        vendors = wt.get("vendors") or [(n, None) for n in (items.get(teach, {}).get(14) or [])]
        r["vendors"] = [n for n, f in vendors if npc(n, f)]
        if "vendor" in how and not r["vendors"]:
            notes.append(f"{name}: a vendor recipe with no vendor we can place")
        r["quests"] = []
        for quest, faction in wt.get("quests") or []:
            title = quests.get(quest, {}).get(1)
            if title:
                giver = ((quests[quest].get(2) or [[]])[0] or [None])[0]
                r["quests"].append((quest, title, SIDE.get(faction, "N"), giver if giver and npc(giver, faction) else 0))
        sides = {used_npcs[n][4] for n in r["vendors"]} | {s for _, _, s, _ in r["quests"]}
        if wt.get("side"):
            r["side"] = SIDE[wt["side"]]
        elif sides and "N" not in sides and len(sides) == 1 and "drop" not in how and "trainer" not in how:
            r["side"] = sides.pop()
        droppers = items.get(teach, {}).get(2) or []
        if "drop" in how and 0 < len(droppers) <= 4:
            r["drops"] = [n for n in droppers if npc(n)]
        elif "drop" in how and len(droppers) > 4:
            r["world"] = True
        recipes.append(r)
    recipes.sort(key=lambda r: (r["skill"], r["name"]))

    # Where each reagent comes from.
    sources = {}
    for i in sorted({i for r in recipes for i, _ in r["needs"]}):
        row = items.get(i, {})
        vendors, droppers, objects = row.get(14) or [], row.get(2) or [], row.get(3) or []
        if i in fish:
            sources[i] = ("fish",)
        elif len(vendors) > 12:
            sources[i] = ("shop",)
        elif vendors:
            sources[i] = ("vendor", [n for n in vendors[:6] if npc(n)])
        elif droppers:
            # One beast per zone, ordinary ones first, spread over the levels.
            best = {}
            for n in droppers:
                d = npcs.get(n)
                if not d or not d.get(1) or not d.get(7):
                    continue
                spawns = d[7] if isinstance(d[7], dict) else {k + 1: v for k, v in enumerate(d[7]) if v}
                zone = d.get(9) if d.get(9) in spawns else next(iter(spawns), None)
                if zone not in zones or zone in dungeons or zones[zone].startswith("Referenced"):
                    continue
                score = (d.get(6) or 0, -len(spawns.get(zone) or []))
                if zone not in best or score < best[zone][0]:
                    best[zone] = (score, d[1], zones[zone], d.get(4) or 0, d.get(5) or 0)
            # Ordinary beasts, where enough zones have them: no rares, no elites.
            plain = [b for b in best.values() if b[0][0] == 0]
            picks = sorted(plain if len(plain) >= 2 else best.values(), key=lambda b: (b[3], b[1]))
            if len(picks) > 8:
                step = (len(picks) - 1) / 7
                picks = [picks[round(k * step)] for k in range(8)]
            sources[i] = ("drop", [p[1:] for p in picks], len(droppers))
        elif objects:
            sources[i] = ("object",)
    if args.report:
        for i in sorted({i for r in recipes for i, _ in r["needs"]} - set(sources)):
            notes.append(f"no source for reagent {used_items.get(i, i)} ({i})")

    out = []
    w = out.append
    w("SanctuaryUI = SanctuaryUI or {}")
    w("local ns = SanctuaryUI")
    w("ns.CookingData = ns.CookingData or {}")
    w("local D = ns.CookingData")
    w("")
    w("-- GENERATED by tools/build_cookbook_data.py from AtlasLoot, WhatsTraining and QuestieDB on the game")
    w("-- install. Don't edit by hand: fix a fact in CookingData.lua (D.FIX, D.EFFECT) or run the tool again.")
    w("--")
    w("-- D.RECIPES, by skill: spell, item (what it makes), name, skill (to learn), yellow/grey (when it")
    w("--   stops being orange / gives nothing; absent where nobody knows yet), makes, needs { item, count },")
    w("--   group (AtlasLoot's buff group), level (to eat it), fish (a caught fish goes in), new (Forever's),")
    w("--   how (start, trainer, vendor, quest, drop, world_object), recipe (the item that teaches it),")
    w("--   cost (copper, at the trainer), favor (Merchant's Favor), standing, bound, side (only that")
    w("--   faction learns it), vendors (D.NPC ids), quests { id, title, side, giver (a D.NPC id, 0 unknown) }, drops (D.NPC ids), world.")
    w("")
    w("D.RECIPES = {")
    for r in recipes:
        parts = [f"spell = {r['spell']}", f"item = {r['item']}", f"name = {q(r['name'])}", f"skill = {r['skill']}"]
        if "yellow" in r:
            parts += [f"yellow = {r['yellow']}", f"grey = {r['grey']}"]
        if r["makes"] > 1:
            parts.append(f"makes = {r['makes']}")
        parts.append("needs = { " + ", ".join(f"{{ {i}, {n} }}" for i, n in r["needs"]) + (" }" if r["needs"] else "}"))
        for key in ("group",):
            if r.get(key):
                parts.append(f"{key} = {q(r[key])}")
        if r.get("level"):
            parts.append(f"level = {r['level']}")
        for key in ("fish", "new", "bound", "world"):
            if r.get(key):
                parts.append(f"{key} = true")
        parts.append("how = { " + ", ".join(q(h) for h in r["how"]) + (" }" if r["how"] else "}"))
        for key in ("recipe", "cost", "favor"):
            if r.get(key):
                parts.append(f"{key} = {r[key]}")
        for key in ("standing", "side"):
            if r.get(key):
                parts.append(f"{key} = {q(r[key])}")
        if r["vendors"]:
            parts.append("vendors = { " + ", ".join(str(n) for n in r["vendors"]) + " }")
        if r["quests"]:
            parts.append("quests = { " + ", ".join(f"{{ {i}, {q(t)}, {q(s)}, {g} }}" for i, t, s, g in r["quests"]) + " }")
        if r.get("drops"):
            parts.append("drops = { " + ", ".join(str(n) for n in r["drops"]) + " }")
        w("\t{ " + ", ".join(parts) + " },")
    w("}")
    w("")
    w("-- Ranks, as the trainers and books teach them: name, skill needed, level needed, spell, book item.")
    w("D.RANK_SPELLS = {")
    for row in sorted(ranks, key=lambda x: x["skill"]):
        w(f"\t{{ {q(row['rank'])}, {row['skill']}, {row.get('level', 0)}, {row['spell']}, {row.get('teach', 'nil')} }},")
        for n, f in row.get("vendors", []):
            npc(n, f)
    w("}")
    book = next((row for row in ranks if row.get("teach")), None)
    if book:
        use(book["teach"])
        w("D.EXPERT_BOOK = { item = %d, vendors = { %s } }" % (book["teach"], ", ".join(str(n) for n, _ in book["vendors"] if n in used_npcs)))
    trainers = sorted(n for n, row in npcs.items()
                      if (row.get(15) or 0) & 16 and "Cook" in (row.get(14) or "") and npc(n))
    for n, side in EXTRA_TRAINERS.items():
        if npc(n, side):
            trainers.append(n)
    for n in ALSO:
        npc(n)
    w("")
    w("-- Cooking trainers (D.NPC ids).")
    w("D.TRAINERS = { " + ", ".join(str(n) for n in trainers) + " }")
    w("")
    w("-- People the book points at: name, zone, x, y, side (A, H, N for both), title.")
    w("D.NPC = {")
    for n in sorted(used_npcs):
        name, zone, x, y, side, title = used_npcs[n]
        w(f"\t[{n}] = {{ {q(name)}, {q(zone)}, {x}, {y}, {q(side)}, {q(title)} }},")
    w("}")
    w("")
    w("-- Names of every item above, so a page reads before the client has loaded them.")
    w("D.ITEM = {")
    for i in sorted(used_items):
        w(f"\t[{i}] = {q(used_items[i])},")
    w("}")
    w("")
    w("-- Where an ingredient comes from: fish (the Angler's journal knows), shop (innkeepers and trade")
    w("-- vendors everywhere), vendor (a few: D.NPC ids), drop ({ beast, zone, level from, to }, one per zone,")
    w("-- of n that drop it), object (picked or opened).")
    w("D.FROM = {")
    for i, s in sorted(sources.items()):
        if s[0] in ("fish", "shop", "object"):
            w(f"\t[{i}] = {{ kind = {q(s[0])} }},")
        elif s[0] == "vendor":
            w(f"\t[{i}] = {{ kind = \"vendor\", " + ", ".join(str(n) for n in s[1]) + " },")
        else:
            w(f"\t[{i}] = {{ kind = \"drop\", n = {s[2]}, " + ", ".join(f"{{ {q(a)}, {q(b)}, {c}, {d} }}" for a, b, c, d in s[1]) + " },")
    w("}")
    OUT.write_text("\n".join(out) + "\n", encoding="utf8")
    print(f"{OUT.relative_to(ROOT)}: {len(recipes)} recipes, {len(used_npcs)} people, {len(used_items)} items, {len(sources)} ingredient sources")
    if args.report:
        print("\n".join("  " + n for n in sorted(set(notes))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
