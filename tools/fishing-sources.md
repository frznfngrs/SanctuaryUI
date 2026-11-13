# Angler's journal: sources and update routine

The fishing journal's book is `SanctuaryUI/FishingData.lua`. This file lists where its facts come from, the
"last updated" date each source showed when the book was last brought in line with it, and the steps
an update follows. The weekly routine reads and updates this file.

## Sources

| Source | URL | Covers | Last updated (as seen) |
|---|---|---|---|
| wow-professions: how to fish | https://www.wow-professions.com/forever/how-to-fish | lures, poles, vendors, trainers | 2026-11 (beta-based) |
| wow-professions: leveling | https://www.wow-professions.com/forever/fishing-leveling-guide | route per skill and faction, zone thresholds | 2026-11 (beta-based) |
| wow-professions: trainers | https://www.wow-professions.com/forever/fishing-trainers | trainers, Expert book, Artisan quest | 2026-11 |
| wow-professions: camping | https://www.wow-professions.com/forever/camping-guide | Fish Bowl, Fishing Rack, Fishing Hut | 2026-11 |
| Warcraft Tavern: fishing | https://www.warcrafttavern.com/forever/guides/fishing/ | equipment, lures, food, talents, tournament | 2026-11 |
| Warcraft Tavern: camping objects | https://www.warcrafttavern.com/forever/guides/camping-objects-buffs/ | camp objects, blueprints | 2026-11 |
| warcraft.wiki.gg: Forever fishing techniques | https://warcraft.wiki.gg/wiki/Forever_fishing_techniques | poles, lures, food, camps, skill ranks | 2026-11-02 |
| warcraft.wiki.gg: Extravagant Extravaganza Coin | https://warcraft.wiki.gg/wiki/Extravagant_Extravaganza_Coin | Jang's coin prizes | 2026-11-03 |
| method.gg | https://www.method.gg/wow-forever/fishing-in-wow-forever-leveling-guide-fishing-items-trainers | zone thresholds, fish per zone, poles | 2026-11-03 |
| wow.gg | https://wow.gg/professions/forever/fishing | zone thresholds, camps, talents, trainers | 2026-11-08 |
| Wowhead (Forever) | https://www.wowhead.com/forever/guide/professions/fishing/overview-leveling | guide (body is JavaScript-rendered) | 2026-11-10 |

Blocked to automated reading (HTTP 403): Icy Veins, Metaforge, Mobalytics, wowvendor.

Local, checked by `tools/fishing_audit.py` (not available to the cloud routine): the journal's field notes in
the saved variables, and AtlasLoot's Forever fishing/cooking tables in the game's AddOns folder.

## Open questions

- The Riverglades' skill band.
- Where the Fishing Hut blueprint (273119) drops.
- How the Chef's Knife's Unique Fish work.
- The Ravaged Fishing Pole's (285094) source; the Darkwood Fishing Pole (6366, listed by AtlasLoot for Forever).
- Item IDs of Jang's other prizes (Master Angler's Fishing Hat, Empty Fish Bucket, Bitter Baitling).
- Briny Seafood Stew (Cooking 200) and Clam Linguine (Cooking 275): new Forever recipes; where they're learned.

## How an update works

1. For each source, read its "last updated" date. If none is newer than the date above, stop: nothing to do.
2. Read the changed sources fully. Compare their facts with `FishingData.lua`: zone thresholds, fish per zone,
   trainers and coordinates, poles, lures, food, gear, camp objects, the Extravaganza and Jang's prizes,
   quests, recipes, and anything new in Forever.
3. Change the book where a fact changed or an open question got answered:
   - two or more sources agree, or one is an official/wiki page: change `FishingData.lua`;
   - only one source says it: add it to `D.TALL_TALES` instead;
   - keep the book's voice: short, plain, a little funny; lore woven into existing lines, never boxed;
   - add item IDs only when a page shows them.
4. Check the Lua parses: `luac5.1 -p SanctuaryUI/FishingData.lua`.
5. Update the dates in the table above, and the open questions.
6. Open a pull request listing each change with the source that supports it.
