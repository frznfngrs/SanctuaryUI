# The Cookbook: sources and how it's kept current

The Cookbook has two data files:

- `SanctuaryUI/CookingRecipes.lua` is **generated** by `tools/build_cookbook_data.py` from three addons
  on the game install (WowUp keeps them current): AtlasLoot (spells, skill colours, reagents),
  WhatsTraining (how each recipe is learned, ranks) and QuestieDB (names, vendors and their
  coordinates, quest givers, who drops what). Never edit it by hand. It needs the game install, so
  the cloud routine can't run it.
- `SanctuaryUI/CookingData.lua` is **written by hand**: what each dish does in Forever, when the new
  recipes change colour, the route, what to eat, the camp, quests, tall tales and every joke. Its
  facts come from the pages below.

## Local update (after a game patch or an addon update)

    python3 tools/build_cookbook_data.py --report

`--report` lists what the three addons disagree on or lack. A dish the report names for the first
time needs an entry in `D.EFFECTS` (and `D.SKILLUP`, `D.LEARN` when the tables don't know).

## Web sources

| Source | URL | Covers | Last updated (as seen 2026-11-13) |
|---|---|---|---|
| Warcraft Tavern: cooking levelling | https://www.warcrafttavern.com/forever/guides/cooking-leveling/ | ranks, trainers with coordinates, route | no date shown |
| Warcraft Tavern: cooking | https://www.warcrafttavern.com/forever/guides/cooking/ | changes, legacy perks | no date shown |
| Warcraft Tavern: camping objects | https://www.warcrafttavern.com/forever/guides/camping-objects-buffs/ | campfire kits, Cookie's Feast, Iron Oven, blueprints | no date shown |
| Warcraft Tavern: legacy | https://www.warcrafttavern.com/forever/guides/legacy/ | Master Chef, Gourmand and the Professions tree | no date shown |
| wow-professions: cooking levelling | https://www.wow-professions.com/forever/cooking-leveling-guide | route, ranks, Artisan quest | beta-based, no date |
| wow-professions: fishing and cooking | https://www.wow-professions.com/forever/fishing-and-cooking-leveling-guide | the combined route, recipe vendors | no date |
| wow-professions: camping | https://www.wow-professions.com/forever/camping-guide | camp rules, blueprint bosses | no date |
| Wowhead (Forever) | https://www.wowhead.com/forever/profession-leveling-guides/cooking | route with craft counts | 2026-11-03 |
| wow.gg: cooking | https://wow.gg/professions/forever/cooking | ranks, trainers, Merchant's Favor vendors | 2026-11-08 |
| wow.gg: new recipes | https://wow.gg/guides/wow-forever-new-recipes-cooking | recipe list, reagents (its source column is noisy) | 2026-11-08 |
| warcraft.wiki.gg: recipes | https://warcraft.wiki.gg/wiki/Forever_cooking_recipes | new recipes and source types | 2026-11-05 |
| warcraft.wiki.gg: Iron Oven | https://warcraft.wiki.gg/wiki/Iron_Oven | the oven | 2026-11-01 |
| warcraft.wiki.gg: fishing techniques | https://warcraft.wiki.gg/wiki/Forever_fishing_techniques | the +Fishing dishes | 2026-11-02 |
| The Forever Guides | https://theforeverguides.com/professions/cooking/ | old food's new stats, the oven's dishes, perks | 2026-11-05 (beta build) |
| classicwowforever.com | https://classicwowforever.com/professions/cooking/ | new dishes' effects and eat levels | 2026-10-09 |
| timesaver.gg | https://timesaver.gg/tools/wow-forever/professions/cooking | recipe drops, quests, vendors | verified 2026-11-08 |
| kami-labs | https://kami-labs.fr/en/guide-cuisine-wow-forever/ | ranks, trainers, route | data checked 2026-11-10 |
| expcarry | https://expcarry.com/wow-forever-cooking-guide | route without the oven, quest details | 2026-11-10 |
| boostroom | https://boostroom.com/blog/wow-forever-cooking-guide-leveling-1300-best-recipes-food-buffs-and-gold-making | food by role, tea and smoothie values | 2026-11-09 |
| method.gg | https://www.method.gg/wow-forever/list-of-all-consumables-and-enchants-in-wow-forever | top food values | 2026-11-02 (beta-based) |
| foreverchanges.pro | https://foreverchanges.pro/savory-whimsyfin-delight | Whimsyfin pools, the recipe's drop, its forms | 2026-10-02 |

Blocked to automated reading (HTTP 403): Icy Veins, Metaforge, Mobalytics, wowvendor, kingboost.

## Open questions

- Where the recipes for Triage Tea, Sunny Tea, Sage's Tea, Raging Raptor Ribs, Plated Armorfish, Savory
  Stag Sliders and nine of the ten oven dishes are learned (one site says trainers; see Tall tales).
- Blueprint: Expert Campfire's source; Blueprint: Iron Oven's (one guide: Quartermaster Zigris).
- Whether the Happy Camper vendor exists on live realms.
- Whether Sunrise Omelette, Prowler Steak, Filet o' Flank, the two feasts, Darkclaw Bisque and Smoked
  Redgill can be learned at all (`D.GHOSTS`); Holy Salts and Exquisite Spices.
- Spinefin Halibut's reagents.
- Which old dishes got which stat, one by one (the guides list them by meat; `D.EFFECTS` follows that
  and leaves numbers out where no page gives one), and whether old dishes give the 5% kill experience.
- Well Fed stacking: tea or smoothie together with a dish.
- Cookie's Feast's Stamina amount; Clam Linguine's real effect.
- The level needed for Journeyman (1 or 10) and Expert (20?).

## How an update works

1. For each web source, read its "last updated" date. If none is newer than the date above and the
   game hasn't patched, stop.
2. Read the changed pages. Compare with `CookingData.lua`: `D.EFFECTS`, `D.SKILLUP`, `D.LEARN`,
   `D.OVEN`, `D.GHOSTS`, `D.RANKS`, `D.ROUTE`, `D.TABLE`, `D.LEVELING`, `D.CAMP_RULES`, `D.TALENTS`,
   `D.QUESTS`, `D.PANTRY`.
3. Change the book where a fact changed or an open question got answered:
   - two or more sources agree, or one is an official/wiki page: change `CookingData.lua`;
   - only one source says it: add it to `D.TALL_TALES` instead;
   - keep the book's voice: short, plain, a little funny; the same cook who keeps the Angler's journal;
   - dishes are keyed by their English name exactly as `CookingRecipes.lua` spells it.
4. Check the Lua parses: `luac5.1 -p SanctuaryUI/CookingData.lua`.
5. Update the dates in the table above, and the open questions.
6. Open a pull request listing each change with the source that supports it.
