#!/usr/bin/env python3
"""Check the angler's journal (SanctuaryUI/FishingData.lua) against what's actually out there.

Sources, all local:
  * your field notes: the journal's per-character log in SanctuaryUI's saved variables (what you
    caught where, the skill you fished with when fish bit and when they got away, items the book
    doesn't know);
  * AtlasLoot's Forever fishing and cooking tables in the game's AddOns folder (WowUp keeps them
    current).

Prints a Markdown report of disagreements and candidates. It changes nothing.

  python3 tools/fishing_audit.py [--wow "<World of Warcraft/_forever_ folder>"] [--account NAME]

Needs lua5.1 (apt install lua5.1) to read the Lua files as the game does.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOOK = ROOT / "SanctuaryUI" / "FishingData.lua"
DEFAULT_WOW = Path("/mnt/d/Games/World of Warcraft/_forever_")
ESCAPE_GAP = 95

# Prints one tab-separated record per line: the book's items and zones, then every character's
# field notes. Arguments: the book, then the saved-variables file.
DUMP = r"""
local book, saved = ...
SanctuaryUI = {}
dofile(book)
local D = SanctuaryUI.FishingData
local function out(...) print(table.concat({ ... }, "\t")) end
local function clean(s) return (tostring(s or ""):gsub("[\t\n]", " ")) end
for key, f in pairs(D.FISH) do out("FISH", key, f.id or "", clean(f.name)) end
for _, list in ipairs({ D.POLES, D.LURES, D.FOOD, D.GEAR }) do
  for _, r in ipairs(list) do if r[2] then out("ITEM", r[2], clean(r[1])) end end
end
for _, c in ipairs(D.CAMP) do out("ITEM", c[2], clean(c[1])) end
for _, c in ipairs(D.EXTRAVAGANZA.coin) do if c[2] then out("ITEM", c[2], clean(c[1])) end end
for name, id in pairs(D.ITEMS) do out("ITEM", id, clean(name)) end
for _, z in ipairs(D.ZONES) do
  local extra = {}
  for _, k in ipairs(z[4] or {}) do extra[#extra + 1] = k end
  out("ZONE", clean(z[1]), z[2] or "", z[3] and "coast" or "inland", table.concat(extra, ","), z.sub and "sub" or "")
end
for band, b in pairs(D.BANDS) do
  for _, kind in ipairs({ "inland", "coast", "pools" }) do
    for _, k in ipairs(b[kind] or {}) do out("BAND", band, kind, k) end
  end
end
if saved and saved ~= "" then
  local ok, err = pcall(dofile, saved)
  if not ok then out("ERROR", clean(err)) return end
  for char, data in pairs((SanctuaryUIDB or {}).char or {}) do
    local f = data.fishing
    if f then
      local field = f.field or {}
      for zone, z in pairs(field.zones or {}) do
        out("FIELD", clean(char), clean(zone), z.catches or 0, z.escapes or 0,
          z.minCatch or "", z.maxCatch or "", z.minEscape or "", z.maxEscape or "")
      end
      for zone, items in pairs(f.zones or {}) do
        for id, n in pairs(items) do out("CATCH", clean(char), clean(zone), id, clean((f.names or {})[id]), n) end
      end
      for id, u in pairs(field.unknown or {}) do
        local where = {}
        for zone, n in pairs(u.zones or {}) do where[#where + 1] = zone .. " x" .. n end
        out("UNKNOWN", clean(char), id, clean(u.name), u.q or "", clean(table.concat(where, "; ")))
      end
    end
  end
end
"""


def run_lua(saved: Path | None) -> list[list[str]]:
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(DUMP)
        script = f.name
    res = subprocess.run(["lua5.1", script, str(BOOK), str(saved) if saved else ""],
                         capture_output=True, text=True)
    Path(script).unlink(missing_ok=True)
    if res.returncode != 0:
        sys.exit("lua5.1 failed:\n" + res.stderr)
    return [line.split("\t") for line in res.stdout.splitlines() if line]


def atlasloot(wow: Path) -> tuple[dict[int, str], dict[str, str]]:
    """AtlasLoot's Forever fishing items {id: name} and its Forever cooking recipes {name: skill}."""
    path = wow / "Interface" / "AddOns" / "AtlasLootContinued_Crafting" / "data-forever.lua"
    if not path.is_file():
        return {}, {}
    text = path.read_text(errors="replace")
    items: dict[int, str] = {}
    m = re.search(r'data\["FishingForever"\]\s*=\s*\{(.*?)\n\}', text, re.S)
    if m:
        for idm in re.finditer(r"\{\s*\d+,\s*(\d+)\s*\},\s*--\s*(.+)", m.group(1)):
            items[int(idm.group(1))] = idm.group(2).strip()
    recipes: dict[str, str] = {}
    for gen in re.finditer(r"BEGIN GENERATED.*?END GENERATED", text, re.S):
        for block in re.finditer(r"\{\s*\d+,\s*\d+\s*\},\s*--(.+?)\s*/\s*(\d+)", gen.group(0)):
            recipes[block.group(1).strip()] = block.group(2)
    return items, recipes


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wow", type=Path, default=DEFAULT_WOW)
    ap.add_argument("--account", help="WTF account folder (default: the first with SanctuaryUI saved)")
    args = ap.parse_args()

    saved = None
    accounts = sorted((args.wow / "WTF" / "Account").glob("*/SavedVariables/SanctuaryUI.lua"))
    for path in accounts:
        if not args.account or path.parts[-3] == args.account:
            saved = path
            break

    rows = run_lua(saved)
    fish_ids, item_ids, zones, bands = {}, {}, {}, defaultdict(set)
    field, catches, unknown = [], defaultdict(lambda: defaultdict(int)), []
    for r in rows:
        kind = r[0]
        if kind == "FISH" and r[2]:
            fish_ids[int(r[2])] = (r[1], r[3])
        elif kind == "ITEM":
            item_ids[int(r[1])] = r[2]
        elif kind == "ZONE":
            zones[r[1]] = {"skill": int(r[2]) if r[2] else None, "coast": r[3] == "coast",
                           "extra": set(filter(None, r[4].split(","))), "sub": r[5] == "sub"}
        elif kind == "BAND":
            bands[(int(r[1]), r[2])].add(r[3])
        elif kind == "FIELD":
            field.append(r[1:])
        elif kind == "CATCH":
            catches[r[2]][(int(r[3]), r[4])] += int(r[5])
        elif kind == "UNKNOWN":
            unknown.append(r[1:])
        elif kind == "ERROR":
            print(f"> Couldn't read the saved variables: {r[1]}\n")

    print("# Angler's journal audit\n")
    print(f"- Book: `{BOOK.relative_to(ROOT)}`")
    print(f"- Field notes: `{saved}`" if saved else "- Field notes: none found (fish a little with the journal loaded, then /reload or log out).")

    # 1. Zone bands against what you saw.
    print("\n## Zone skill bands\n")
    print("A zone's number is where nothing gets away; nothing bites below number - 95. Effective skill = rank + pole/lure/food.\n")
    found = False
    for char, zone, c, e, minc, maxc, mine, maxe in field:
        book = zones.get(zone)
        notes = []
        maxe_i = int(maxe) if maxe else None
        minc_i = int(minc) if minc else None
        if not book:
            notes.append("**not in the book**: add it to D.ZONES")
        elif book["skill"] is None:
            lo = (maxe_i + 1) if maxe_i is not None else None
            notes.append("band unknown in the book; " + (f"the no-getaway number is above {maxe_i}" if maxe_i is not None else "no escapes seen yet")
                         + (f", and fish bit at {minc_i}" if minc_i is not None else ""))
        else:
            if maxe_i is not None and maxe_i >= book["skill"]:
                notes.append(f"**a fish got away at {maxe_i}, at or above the book's {book['skill']}**: the band is higher")
            if minc_i is not None and minc_i < book["skill"] - ESCAPE_GAP:
                notes.append(f"**a fish bit at {minc_i}, below the book's floor {book['skill'] - ESCAPE_GAP}**: the band is lower")
        if notes or not book:
            found = True
        print(f"- {zone} ({char}): {c} caught at {minc or '?'}-{maxc or '?'}, {e} got away at {mine or '-'}-{maxe or '-'}"
              + (f"; book {book['skill']}" if book and book['skill'] else "") + ("; " + "; ".join(notes) if notes else "; agrees"))
    if not field:
        print("- No field notes yet.")

    # 2. Fish caught somewhere the book doesn't list them.
    print("\n## Fish caught where the book doesn't list them\n")
    any_missing = False
    for zone, items in sorted(catches.items()):
        book = zones.get(zone)
        if not book or not book["skill"]:
            continue
        listed = set(book["extra"])
        for kind in ("inland", "pools") + (("coast",) if book["coast"] else ()):
            listed |= bands.get((book["skill"], kind), set())
        for (id_, name), n in sorted(items.items(), key=lambda kv: -kv[1]):
            key = fish_ids.get(id_, (None,))[0]
            if key and key not in listed:
                any_missing = True
                print(f"- {zone}: {name} ({id_}) x{n}: add \"{key}\" to the zone's extras")
    if not any_missing:
        print("- None.")

    # 3. Items the book doesn't know.
    print("\n## Caught items the book doesn't know\n")
    seen = set()
    for char, id_, name, q, where in sorted(unknown, key=lambda u: u[2]):
        if id_ in seen:
            continue
        seen.add(id_)
        print(f"- {name} ({id_}), quality {q or '?'}: {where}")
    if not seen:
        print("- None.")

    # 4. AtlasLoot's Forever fishing table.
    al_items, al_recipes = atlasloot(args.wow)
    print("\n## AtlasLoot (Forever) fishing items missing from the book\n")
    known = set(item_ids) | set(fish_ids)
    missing = [(i, n) for i, n in al_items.items() if i not in known]
    for i, n in sorted(missing, key=lambda x: x[1]):
        print(f"- {n} ({i})")
    if not al_items:
        print("- AtlasLoot's Forever data wasn't found.")
    elif not missing:
        print("- None: the book has every item in AtlasLoot's Forever fishing table.")

    print("\n## AtlasLoot (Forever) new cooking recipes that may use fish\n")
    book_text = BOOK.read_text()
    fishy = [(n, s) for n, s in al_recipes.items()
             if re.search(r"fish|fin\b|salmon|trout|\bcod\b|\beels?\b|lobster|clam|crab|seafood|squid|snapper|whimsy", n, re.I)]
    for n, s in sorted(fishy, key=lambda x: int(x[1])):
        mark = "" if n in book_text else "  (not mentioned in the book)"
        print(f"- {n}, Cooking {s}{mark}")
    if not fishy:
        print("- None found.")


if __name__ == "__main__":
    main()
