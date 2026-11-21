# Shared mining finds

Rock Bottom (SanctuaryUI/Mining.lua) logs a **find** when you mine a vein more than about 0.6% of the map from every spot it knows. Options > Rock Bottom > Sharing finds > **Export my finds** turns them into one line, `RB1:<finds>:<checksum>`.

Players send those lines in on the **Mining finds** issue form (`.github/ISSUE_TEMPLATE/mining-finds.yml`). To ship them:

1. Save each issue's string(s) as a `.txt` file here, named after the issue (`issue-123.txt`). One file can hold several strings.
2. Run `python3 tools/build_mining_data.py --report`.
3. It checks each string's checksum, drops finds on a known spot, and drops a vein on a map where it doesn't already grow (the guard against mistakes and made-up finds). The rest become ordinary spots in `SanctuaryUI/MiningNodes.lua`; the header says how many.
4. Close the issue with the version that carries them.

A find is `code.map.x.y`: the vein's two-letter code (`D.CODE` in `SanctuaryUI/MiningData.lua`), the uiMapID, and x and y in thousandths of the map.
