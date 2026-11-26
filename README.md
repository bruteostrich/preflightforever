# Preflight Forever

A standalone flight planner for **World of Warcraft: Forever 1.60.1** (interface **16001**).

Click the floating gryphon button anywhere outdoors to see a continent map and your closest faction-compatible flight point, which is where your flight leaves from. Hover a known destination for route arrows on the map and live details at the bottom of the planner; click its pin or name to queue a flight. When you visit the selected flight master and open its taxi map, Preflight Forever checks the live destination, route, and fare, then starts the flight. A single, unambiguous flight-service gossip option is selected automatically when automatic departure is enabled.

## Install

Install with the CurseForge app, or manually:

1. Exit WoW completely.
2. Extract the PreflightForever zip into the Forever client's `Interface/AddOns` directory (inside your `World of Warcraft/_forever_` folder), replacing the previous PreflightForever files if upgrading.
3. Check that the resulting path is `_forever_/Interface/AddOns/PreflightForever/PreflightForever.toc` (no extra nested `PreflightForever` directory).
4. Start WoW and enable **Preflight Forever** in AddOns.

Bundled route data matches client build **1.60.1.71091**. Fully restart the game after upgrading so the updated addon load order takes effect. Your saved character settings and learned flight points remain intact; an old queue containing an unconfirmed point is cleared.

## Use

- **Left-click** the floating button to open or close the planner; **drag** it to move it.
- The top of the map names the closest flight point and its approximate straight-line distance. It counts flight points you haven't discovered yet and marks them "(undiscovered)": talking to that flight master discovers it, so you can fly out on the same visit. This is the flight-point location name, not necessarily the NPC's personal name.
- Only verified known destinations appear in the list. Unknown and unverified points stay on the map in **red** and cannot be selected; hover them to see their status in the bottom panel.
- Hover a map pin or destination row to update the bottom panel with its name, status, route, and estimated flight time. Route arrows stay visible on the map without a destination tooltip covering them. Bundled flight connections provide an estimated route before visiting a flight master. A current recorded native route takes priority afterward.
- Hover details and arrows clear when you leave the point, close the planner, or filter out the hovered destination. The floating gryphon button retains its help tooltip.
- Click a known pin or destination row to queue a single destination. Selecting another replaces it. The queue banner shows both the chosen departure and destination.
- Visit the **queued departure flight master**. Opening another flight master's map keeps the queue intact.
- Automatic departure is **on by default** and pays the ordinary in-game flight fare. Uncheck **Auto-depart on arrival** for a **Depart now** button instead.
- Hold **Shift while opening the NPC's taxi map** to skip automatic departure for that interaction. If the NPC has a gossip menu, holding Shift also skips its automatic flight-service selection.
- **Right-click** the floating button, click **Clear queue**, or type `/pf clear` to cancel.
- Drag the planner's title bar to move it. **Escape** closes it.

| Command | Action |
| --- | --- |
| `/preflight` or `/pf` | Toggle the planner |
| `/pf clear` | Clear the queued destination |
| `/pf auto` | Toggle automatic departure |
| `/pf reset` | Restore both frame positions |
| `/pf status` | Print the queued route |
| `/pf debug` | Print map, discovery, and native route-comparison diagnostics |

## What the preview can know

The preview uses the client's remote API for flight-point locations. Forever can incorrectly report every point as discovered, so its discovery flags alone no longer unlock destinations. **Gold** marks the closest flight point (your departure) and the selected destination, **green** marks verified known destinations, and **red** marks unknown or unverified points. Unverified does not mean the character has never discovered the point; it means Preflight Forever lacks reliable evidence.

When you open a flight master's normal map, its actual node states correct both false positives and false negatives in the remote data. These positive and negative corrections persist per character and take precedence over later remote flags. A subsequent flight-master visit can change them again. Nodes omitted from a snapshot are left unchanged. Saved observations from older versions are preserved on upgrade.

Discovery priority is a real flight-master observation, then a confirmed **Forever Dungeon Journal** record. The journal import accepts validated version-2 entries with exact, unambiguous full names on the current continent and retains their provenance in Preflight Forever. This lets characters with existing journal records plan immediately. Missing journal names are never saved as negative observations, and the journal is not modified. Without either source, open a real flight master's map once to establish a verified list. Upgrading discards unproven discovery entries cached by 0.2.2 while preserving settings, measured flights, and verified records.

Hover arrows first use the ordered route hops returned by the native taxi API, saved for that departure master. Otherwise they use **286 bundled directed ordinary flight connections** from the installed Forever build, **1.60.1.71091**, restricted to verified known points. A direct connection takes priority; if none exists, the preview searches for the shortest flown-distance connection through intermediate points. These previews remain labeled **Estimated route** because the game's exact multi-hop selection rules are not publicly documented for Forever. If the graph cannot connect the endpoints, no line is invented. Estimated routes never become native observations. Route availability and fare are always rechecked against the NPC's live map before departure.

Recorded routes are tied to the known flight points and client build present when captured. If either changes, Preflight Forever prefers a fresh estimate until you revisit that departure master. When no estimate is available, an older usable record is labeled **Previously recorded**. Your measured time remains associated with its exact stop sequence. Each native visit also compares the bundled preview against the actual hop sequence; `/pf debug` reports matching, differing, and unavailable estimates. These comparisons measure observed cases, not accuracy across every possible route.

Travel times start with **882 bundled normal-speed timings** from [InFlight's compatible Classic Era + Forever database](https://github.com/LudiusMaximus/InFlight/blob/4b2b3baed78b13c129405330e5abbdc0c0d6b8fd/Defaults.lua). The bottom panel identifies database estimates, complete route-leg estimates, or your recorded flight time. Preflight Forever measures both manually selected and queued flights, and prefers your completed route's timing thereafter. It normalizes the Frequent Flier perk so estimates adjust when your flight speed changes. Times remain estimates; unknown timings are shown as not recorded rather than made up. Flights interrupted by a reload, world transition, early landing, unknown state, or speed change are not recorded. The bundled data's MIT license and attribution are included in `THIRD_PARTY_NOTICES.txt` in the addon folder.

The planner is a separate window using Blizzard's map art and clickable flight pins. It does not reopen or modify Blizzard's live taxi window remotely. Locations or maps that the client cannot expose cannot be planned; try outdoors or visit a flight master to populate the character's cache. The closest point uses world-space distance on your current continent, so terrain, caves, and walking paths can make another master easier to reach.

Preflight Forever validates the current source, destination ID, reachability, slot, ordinary fare, available money, and travel state immediately before departure. Special-currency flights and map-transition nodes require manual selection. It never uses a saved taxi slot. Queues remain pending if the client blocks departure or flight is not confirmed, and are cleared only when the client reports that you are on a taxi. Character settings and queues persist on logout or `/reload` through `PreflightDB`.

## Route research and accuracy

The connection data now comes from the Forever [TaxiNodes](https://wago.tools/db2/TaxiNodes/csv?build=1.60.1.71091), [TaxiPath](https://wago.tools/db2/TaxiPath/csv?build=1.60.1.71091), and [TaxiPathNode](https://wago.tools/db2/TaxiPathNode/csv?build=1.60.1.71091) tables for build **1.60.1.71091**, rather than a Classic baseline with Forever additions. The graph preserves direction: a connection from A to B does not imply the reverse connection. The ordinary-flight graph excludes the two class-only Nighthaven services; they still exist in the game. Regeneration changed 22 flown-distance weights compared with the previous bundled data. Data attribution is recorded in `THIRD_PARTY_NOTICES.txt` in the addon folder.

Direct-flight priority is supported by two independent client-research sources: [ClassicAPI's reconstruction of vanilla flight selection](https://github.com/brues-code/ClassicAPI/blob/master/src/taxi/Map.cpp#L410) and [TrinityCore's taxi routing implementation](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/game/Entities/Taxi/TaxiPathGraph.cpp#L198). Both choose an available direct connection before searching through intermediate points. These are historical reverse-engineering and emulator sources, not Blizzard's published Forever routing algorithm. Multi-hop weighting differs between client generations, so the preview's distance search remains an estimate; it does not assume the cheapest fare or fewest stops reproduces the game.

For exact observed sequences, Preflight Forever uses the same hop APIs as [Forever's native flight-map renderer](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_FlightMap/FM_FlightPathDataProvider.lua#L76): `GetNumRoutes` and `TaxiGetNodeSlot`. [Forever's documented remote taxi API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TaxiMapDocumentation.lua) supplies point information, not a remotely computed route between arbitrary points. Map lines therefore connect flight points as the native interface does; they do not trace every bend of the airborne flight.

The installed addon has no addon or library dependencies. API signatures were checked against the [Forever taxi API source](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TaxiMapDocumentation.lua), [native remote flight-point provider](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedMapDataProviders/FlightPointDataProvider.lua), [map API source](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua), [map tile renderer](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvasDetailLayer.lua), [flight-map provider](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_FlightMap/FM_FlightPathDataProvider.lua), and [gossip API source](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/GossipInfoDocumentation.lua).

## License

Preflight Forever is released under the MIT License; see `LICENSE.txt` in the addon folder. Bundled third-party data keeps its own attribution in `THIRD_PARTY_NOTICES.txt`.
