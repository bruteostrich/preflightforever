local ns = {}
assert(loadfile("Model.lua"))("PreflightForever", ns)
assert(loadfile("API.lua"))("PreflightForever", ns)
local A = ns.API
local tests, passed = {}, 0
local calls, remote, live, names, kinds, costs, options, routes
local secret = {}

local function equal(actual, expected, message)
    assert(actual == expected, (message or "Unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function near(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        tostring(actual) .. " not close to " .. tostring(expected))
end

local function vector(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

local function find(nodes, id)
    for _, node in ipairs(nodes) do if node.id == id then return node end end
end

local function reset()
    ForeverDungeonJournalCharacterDB = nil
    calls = { remote = {}, all = {}, flights = {}, gossip = {} }
    remote = {
        { nodeID = 1, name = "Departure", faction = 2, position = vector(0.15, 0.13), isUndiscovered = false },
        { nodeID = 2, name = "Destination", faction = 2, position = vector(0.4, 0.2), isUndiscovered = false },
        { nodeID = 3, name = "Undiscovered", faction = 0, position = vector(0.6, 0.3), isUndiscovered = true },
        { nodeID = 4, name = "Enemy", faction = 1, position = vector(0.15, 0.13), isUndiscovered = false },
    }
    live = {
        { nodeID = 1, name = "Departure", slotIndex = 1, state = 0, position = vector(0.075, 0.065) },
        { nodeID = 2, name = "Destination", slotIndex = 2, state = 1, position = vector(0.2, 0.1) },
    }
    names, kinds, costs = { "Departure", "Destination" }, { "CURRENT", "REACHABLE" }, { 0, 99 }
    routes = { [2] = { { 1, 2 } } }
    options = { { gossipOptionID = 42, icon = 132057, status = 0 } }
    CreateVector2D = vector
    issecretvalue = function(value) return value == secret end
    UnitFactionGroup = function() return "Alliance" end
    InCombatLockdown = function() return false end
    UnitOnTaxi = function() return false end
    UnitIsDeadOrGhost = function() return false end
    GetMoney = function() return 500 end
    IsShiftKeyDown = function() return false end
    IsPlayerSpell = function() return false end
    GetPlayerFacing = function() return 1.25 end
    GetTaxiMapID = function() return 1463 end
    NumTaxiNodes = function() return #names end
    TaxiNodeName = function(slot) return names[slot] end
    TaxiNodeGetType = function(slot) return kinds[slot] end
    TaxiNodeCost = function(slot) return costs[slot] end
    TaxiNodePosition = function(slot) return live[slot].position:GetXY() end
    GetNumRoutes = function(slot) return routes[slot] and #routes[slot] or 0 end
    TaxiGetNodeSlot = function(slot, hop, source)
        return routes[slot][hop][source and 1 or 2]
    end
    TakeTaxiNode = function(slot) calls.flights[#calls.flights + 1] = slot end
    C_Map = {
        GetBestMapForUnit = function() return 1421 end,
        GetMapInfo = function(mapID)
            if mapID == 1421 then return { mapID = mapID, parentMapID = 1415, mapType = 3, name = "Zone" } end
            if mapID == 1415 then return { mapID = mapID, parentMapID = 947, mapType = 2, name = "Continent" } end
        end,
        GetPlayerMapPosition = function(mapID)
            if mapID == 1421 then return vector(0.5, 0.6) end
            error("Player position should be obtained from the zone first")
        end,
        GetWorldPosFromMapPos = function(mapID, pos)
            if mapID == 1421 then return 0, vector(pos.x * 100 + 100, pos.y * 100 + 200) end
            if mapID == 1415 then return 0, vector(pos.x * 1000, pos.y * 2000) end
            if mapID == 1463 then return 0, vector(pos.x * 2000, pos.y * 4000) end
        end,
        GetMapPosFromWorldPos = function(instanceID, pos, mapID)
            equal(instanceID, 0, "World instance zero must remain valid")
            if mapID == 1415 then return mapID, vector(pos.x / 1000, pos.y / 2000) end
        end,
    }
    C_TaxiMap = {
        GetTaxiNodesForMap = function(mapID)
            calls.remote[#calls.remote + 1] = mapID
            return remote
        end,
        GetAllTaxiNodes = function(mapID)
            calls.all[#calls.all + 1] = mapID
            return live
        end,
    }
    C_GossipInfo = {
        GetOptions = function() return options end,
        SelectOption = function(id) calls.gossip[#calls.gossip + 1] = id end,
    }
end

local function test(name, fn) tests[#tests + 1] = { name, fn } end

test("preview queries only the continent and projects the zone player", function()
    local preview = assert(A.GetPreview({}))
    equal(preview.mapID, 1415)
    equal(preview.mapName, "Continent")
    equal(calls.remote[1], 1415)
    equal(#calls.remote, 1)
    equal(preview.player.instanceID, 0)
    near(preview.player.worldX, 150)
    near(preview.player.worldY, 260)
    near(preview.player.x, 0.15)
    near(preview.player.y, 0.13)
    equal(#preview.nodes, 3, "Opposite faction is excluded")
end)

test("remote positives remain unverified without a character-specific proof", function()
    local db = {}
    local preview = assert(A.GetPreview(db))
    equal(find(preview.nodes, 1).learned, false)
    equal(find(preview.nodes, 2).learned, false)
    equal(find(preview.nodes, 2).locked, true)
    equal(find(preview.nodes, 2).unverified, true)
    equal(find(preview.nodes, 2).knowledgeSource, "unverified")
    equal(find(preview.nodes, 3).locked, true)
    equal(find(preview.nodes, 3).knowledgeSource, "remote-unknown")
    equal(db.learned[2], nil)
    equal(db.learned[3], nil)
    equal(preview.needsFlightSync, true)
    equal(preview.verifiedKnownCount, 0)
    equal(preview.remoteKnownCount, 2)
    equal(preview.unverifiedCount, 2)
    assert(preview.warning:find("unreliable", 1, true))
    equal(#calls.all, 0)
    equal(#calls.flights, 0)
end)

test("an all-known remote response cannot pollute verified knowledge", function()
    for _, node in ipairs(remote) do node.isUndiscovered = false end
    local db = { learned = { [1] = true, [2] = true, [3] = true } }
    for _ = 1, 2 do
        local preview = assert(A.GetPreview(db))
        equal(preview.verifiedKnownCount, 0)
        equal(preview.remoteKnownCount, 3)
        equal(preview.unverifiedCount, 3)
        for _, node in ipairs(preview.nodes) do
            equal(node.locked, true)
            equal(db.learned[node.id], nil)
        end
        equal(next(db.importedKnown), nil)
        equal(db.observed, nil)
    end
end)

test("an explicitly all-unknown remote map is not mistaken for missing discovery data", function()
    for _, node in ipairs(remote) do node.isUndiscovered = true end
    local preview = assert(A.GetPreview({}))
    for _, node in ipairs(preview.nodes) do equal(node.locked, true) end
    equal(preview.needsFlightSync, false)
    equal(preview.warning, nil)
end)

test("missing secret and nonboolean discovery flags cannot invent known points", function()
    for _, value in ipairs({ secret, 0, 1, "false", {} }) do
        remote[2].isUndiscovered = value
        local db = {}
        equal(find(assert(A.GetPreview(db)).nodes, 2).learned, false)
        equal(db.learned[2], nil, "Unavailable discovery must not persist as a false observation")
    end
    for _, node in ipairs(remote) do node.isUndiscovered = nil end
    local preview = assert(A.GetPreview({}))
    equal(preview.needsFlightSync, true)
    assert(preview.warning:find("verify", 1, true))
end)

test("old mixed discovery cache is not evidence in either direction", function()
    local db = { learned = { [2] = false, [3] = true } }
    local preview = assert(A.GetPreview(db))
    equal(find(preview.nodes, 2).learned, false)
    equal(find(preview.nodes, 3).learned, false)
    equal(db.learned[2], nil)
    equal(db.learned[3], nil)
end)

test("a real flight-master visit corrects a remote false positive across refresh and reload", function()
    local db = {}
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = { destination = true } }
    equal(find(assert(A.GetPreview(db)).nodes, 2).learned, true)
    kinds[2] = "DISTANT"
    assert(ns.Model.RecordSnapshot(db, assert(A.GetLive()), 100))
    equal(db.observed[2], false)
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = { destination = true } }
    for _ = 1, 2 do
        local preview = assert(A.GetPreview(db))
        equal(find(preview.nodes, 2).learned, false)
        equal(find(preview.nodes, 2).locked, true)
        equal(preview.importedKnownCount, 0)
    end
    -- Reloaded SavedVariables preserve false, rather than falling through
    -- Lua's `or` to the optimistic remote flag or stale journal cache.
    local reloaded = { observed = { [1] = true, [2] = false }, learned = { [2] = true } }
    equal(find(assert(A.GetPreview(reloaded)).nodes, 2).learned, false)
    equal(reloaded.learned[2], false)
end)

test("a later real visit can replace a negative correction with a learned point", function()
    remote[2].isUndiscovered = true
    local db = { observed = { [2] = false }, learned = { [2] = false } }
    assert(ns.Model.RecordSnapshot(db, assert(A.GetLive()), 200))
    equal(db.observed[2], true)
    equal(find(assert(A.GetPreview(db)).nodes, 2).learned, true)
    kinds[2] = "DISTANT"
    assert(ns.Model.RecordSnapshot(db, assert(A.GetLive()), 300))
    equal(find(assert(A.GetPreview(db)).nodes, 2).learned, false)
end)

test("unknown or omitted native states do not erase earlier corrections", function()
    local db = { observed = { [2] = false, [7] = true }, learned = { [2] = false, [7] = true } }
    assert(ns.Model.RecordSnapshot(db, { mapID = 1415, sourceID = 1, nodes = {
        { id = 1, name = "Departure", state = "CURRENT" },
        { id = 2, name = "Destination" },
    } }, 100))
    equal(db.observed[2], false)
    equal(db.observed[7], true)
    equal(find(assert(A.GetPreview(db)).nodes, 2).learned, false)
end)

test("trusted journal knowledge replaces an unproven cache when remote discovery is unavailable", function()
    remote[1].isUndiscovered, remote[2].isUndiscovered, remote[3].isUndiscovered = nil, secret, nil
    local db = { learned = { [1] = true, [2] = false } }
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = { destination = true } }
    local preview = assert(A.GetPreview(db))
    equal(find(preview.nodes, 1).learned, false)
    equal(find(preview.nodes, 2).learned, true)
    equal(preview.importedKnownCount, 1)
    equal(preview.needsFlightSync, true)
end)

test("journal positives override incorrect remote flags but not a native negative correction", function()
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = {
        departure = true, destination = true, undiscovered = true,
    } }
    local db = { observed = { [2] = false } }
    local preview = assert(A.GetPreview(db))
    equal(preview.importedKnownCount, 2)
    equal(find(preview.nodes, 1).learned, true)
    equal(find(preview.nodes, 1).knowledgeSource, "dungeon-journal")
    equal(find(preview.nodes, 2).learned, false)
    equal(find(preview.nodes, 2).knowledgeSource, "flight-master")
    equal(find(preview.nodes, 3).learned, true)
    equal(find(preview.nodes, 3).knowledgeSource, "dungeon-journal")
    equal(db.observed[1], nil)
    equal(db.observed[3], nil)
end)

test("an empty cache imports confirmed character flight names and persists stable IDs", function()
    remote[1].name, remote[2].name = "Departure, Zone One", "Destination, Zone Two"
    remote[1].isUndiscovered, remote[2].isUndiscovered = nil, nil
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = {
        ["departure, zone one"] = true, ["destination, zone two"] = true,
    } }
    local db = {}
    local preview = assert(A.GetPreview(db))
    equal(preview.importedKnownCount, 2)
    equal(preview.needsFlightSync, false)
    equal(preview.warning, nil)
    equal(db.learned[1], true)
    equal(db.learned[2], true)
    equal(db.importedKnown[2].source, "ForeverDungeonJournal")
    equal(db.importedKnown[2].schema, 2)
    equal(db.importedKnown[2].name, "Destination, Zone Two")
    equal(find(preview.nodes, 2).locked, false)
    equal(find(preview.nodes, 3).locked, true)
    equal(ForeverDungeonJournalCharacterDB.flightPoints["destination, zone two"], true)
    ForeverDungeonJournalCharacterDB = nil
    remote[1].isUndiscovered, remote[2].isUndiscovered = true, true
    ns.Model.InitializeKnowledge(db)
    local later = assert(A.GetPreview(db))
    equal(later.importedKnownCount, 0)
    equal(find(later.nodes, 2).learned, true, "Imported observations survive without the other addon")
end)

test("journal import rejects old unknown or malformed schemas and nontrue values", function()
    for _, node in ipairs(remote) do node.isUndiscovered = nil end
    for _, version in ipairs({ 1, 3, "2" }) do
        ForeverDungeonJournalCharacterDB = { flightPointsVersion = version, flightPoints = { destination = true } }
        equal(find(assert(A.GetPreview({})).nodes, 2).locked, true)
    end
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = true }
    equal(find(assert(A.GetPreview({})).nodes, 2).locked, true)
    ForeverDungeonJournalCharacterDB.flightPoints = { destination = false, departure = 1, undiscovered = "true" }
    equal(assert(A.GetPreview({})).importedKnownCount, 0)
    ForeverDungeonJournalCharacterDB.flightPoints = { destination = secret }
    equal(assert(A.GetPreview({})).importedKnownCount, 0)
end)

test("journal names must match the full localized name without prefix or zone stripping", function()
    remote[2].name = "Destination, Zone Two"
    remote[2].isUndiscovered = nil
    for _, key in ipairs({ "destination", "destination, zone", " destination, zone two", "Destination, Zone Two" }) do
        ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = { [key] = true } }
        equal(find(assert(A.GetPreview({})).nodes, 2).locked, true)
    end
end)

test("duplicate compatible names cannot import an ambiguous flight ID", function()
    remote[2].isUndiscovered = nil
    remote[5] = { nodeID = 20, name = "DESTINATION", faction = 2, position = vector(0.7, 0.6) }
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = { destination = true } }
    local db = { learned = { [1] = true } }
    local preview = assert(A.GetPreview(db))
    equal(preview.importedKnownCount, 0)
    equal(find(preview.nodes, 2).locked, true)
    equal(find(preview.nodes, 20).locked, true)
    equal(find(preview.nodes, 1).learned, false, "A legacy mixed cache is not a native observation")
end)

test("persisted imports require recognized provenance", function()
    for _, entry in ipairs({ true, "ForeverDungeonJournal", {},
        { source = "Remote", schema = 2, name = "Destination" },
        { source = "ForeverDungeonJournal", schema = 1, name = "Destination" },
        { source = "ForeverDungeonJournal", schema = 2, name = "" } }) do
        local db = { importedKnown = { [2] = entry } }
        equal(find(assert(A.GetPreview(db)).nodes, 2).learned, false)
    end
end)

test("journal import cannot learn opposite faction invalid IDs or transition nodes", function()
    remote[5] = { nodeID = 0, name = "Invalid", faction = 2, position = vector(0.7, 0.6) }
    remote[6] = { nodeID = 21, name = "Transition", faction = 2, position = vector(0.7, 0.6), isMapLayerTransition = true }
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = {
        enemy = true, invalid = true, transition = true,
    } }
    local db = {}
    local preview = assert(A.GetPreview(db))
    equal(preview.importedKnownCount, 0)
    equal(db.learned[4], nil)
    equal(db.learned[0], nil)
    equal(db.learned[21], nil)
end)

test("journal import works with a confirmed cached point when remote API is absent", function()
    C_TaxiMap = nil
    ForeverDungeonJournalCharacterDB = { flightPointsVersion = 2, flightPoints = { ["cached stop, zone"] = true } }
    local db = { maps = { [1415] = { nodes = {
        [7] = { id = 7, name = "Cached stop, Zone", x = 0.4, y = 0.2, faction = 2 },
        [8] = { id = 8, name = "Cached stop, Zone", x = 0.7, y = 0.6, faction = 1 },
    } } } }
    local preview = assert(A.GetPreview(db))
    equal(preview.importedKnownCount, 1)
    equal(db.learned[7], true)
    equal(db.learned[8], nil)
end)

test("cache preserves confirmed positions and authoritative observed IDs", function()
    remote[2].isUndiscovered = true
    local db = { observed = { [2] = true }, learned = { [2] = true }, maps = { [1415] = { nodes = {
        [2] = { id = 2, name = "Old destination", x = 0.1, y = 0.1, instanceID = 0, worldX = 100, worldY = 200 },
        [8] = { id = 8, name = "Cached stop", x = 0.7, y = 0.8, instanceID = 0, worldX = 700, worldY = 1600 },
        [9] = { id = 9, name = "Cached enemy", faction = 1 },
    } } } }
    local preview = assert(A.GetPreview(db))
    local destination = assert(find(preview.nodes, 2))
    equal(destination.name, "Destination")
    equal(destination.learned, true)
    equal(destination.locked, false)
    near(destination.x, 0.1)
    near(destination.worldX, 100)
    assert(find(preview.nodes, 8))
    assert(not find(preview.nodes, 9))
end)

test("cached nodes remain available if remote API is absent", function()
    C_TaxiMap = nil
    local preview = assert(A.GetPreview({ maps = { [1415] = { nodes = {
        [7] = { id = 7, name = "Cached", x = 0.4, y = 0.2 },
    } } } }))
    equal(#preview.nodes, 1)
    equal(preview.nodes[1].id, 7)
end)

test("live taxi positions convert into canonical continent coordinates", function()
    local snapshot = assert(A.GetLive())
    equal(snapshot.mapID, 1415)
    equal(snapshot.taxiMapID, 1463)
    equal(calls.all[1], 1463)
    equal(snapshot.sourceID, 1)
    local destination = assert(find(snapshot.nodes, 2))
    equal(destination.state, "REACHABLE")
    equal(destination.slot, 2)
    equal(destination.cost, 99)
    equal(destination.instanceID, 0)
    near(destination.worldX, 400)
    near(destination.worldY, 400)
    near(destination.x, 0.4)
    near(destination.y, 0.2)
end)

test("live routes capture ordered native hops as stable IDs and canonical positions", function()
    live[3] = { nodeID = 3, name = "Middle stop", slotIndex = 3, state = 2, position = vector(0.15, 0.08) }
    names[3], kinds[3], costs[3] = "Middle stop", "DISTANT", 0
    routes[2] = { { 1, 3 }, { 3, 2 } }
    local route = assert(find(assert(A.GetLive()).nodes, 2).route)
    equal(route.key, "1:3:2")
    equal(route.mapID, 1415)
    equal(route.sourceID, 1)
    equal(route.destinationID, 2)
    equal(#route.points, 3)
    equal(route.points[2].id, 3)
    near(route.points[2].x, 0.3)
    near(route.points[2].y, 0.16)
    equal(route.points[2].slot, nil, "Session slots must never appear in cached route points")
    equal(route.timingKey, "0.07:0.07:0.15:0.08:0.20:0.10")
end)

test("missing route APIs or incomplete coordinate conversion omit the route", function()
    GetNumRoutes = nil
    equal(find(assert(A.GetLive()).nodes, 2).route, nil)
    GetNumRoutes = function() return 1 end
    C_Map.GetMapPosFromWorldPos = function() return nil end
    equal(find(assert(A.GetLive()).nodes, 2).route, nil)
end)

test("route capture rejects disconnected paths and wrong endpoints", function()
    routes[2] = { { 1, 2 }, { 1, 2 } }
    equal(find(assert(A.GetLive()).nodes, 2).route, nil)
    routes[2] = { { 2, 1 } }
    equal(find(assert(A.GetLive()).nodes, 2).route, nil)
    routes[2] = { { 1, 99 } }
    equal(find(assert(A.GetLive()).nodes, 2).route, nil)
end)

test("unreachable and special flights have no hover route", function()
    kinds[2] = "UNREACHABLE"
    equal(find(assert(A.GetLive()).nodes, 2).route, nil)
    kinds[2], live[2].useSpecialIcon = "REACHABLE", true
    equal(find(assert(A.GetLive()).nodes, 2).route, nil)
end)

test("Frequent Flier speed is captured without inventing a duration", function()
    IsPlayerSpell = function(spellID) equal(spellID, 1225490); return true end
    local route = assert(find(assert(A.GetLive()).nodes, 2).route)
    equal(A.GetFlightSpeedFactor(), 1.2)
    equal(route.speedFactor, 1.2)
    equal(route.duration, nil)
    IsPlayerSpell = function() return secret end
    equal(A.GetFlightSpeedFactor(), 1)
end)

test("failed taxi projection omits positions without inventing coordinates", function()
    C_Map.GetMapPosFromWorldPos = function() return nil end
    local snapshot = assert(A.GetLive())
    equal(snapshot.nodes[1].x, nil)
    equal(snapshot.nodes[1].y, nil)
    equal(snapshot.sourceID, 1)
end)

test("live slots override stale raw reachability and reject name mismatch", function()
    kinds[2] = "DISTANT"
    local snapshot = assert(A.GetLive())
    equal(find(snapshot.nodes, 2).state, "UNREACHABLE")
    names[2] = "Different destination"
    snapshot = assert(A.GetLive())
    assert(not find(snapshot.nodes, 2))
end)

test("multiple current sources prevent departure", function()
    kinds[2] = "CURRENT"
    local snapshot = A.GetLive()
    equal(snapshot, nil)
end)

test("duplicate modern IDs are rejected instead of hidden", function()
    live[3] = { nodeID = 2, name = "Destination", slotIndex = 3, state = 1, position = vector(0.2, 0.1) }
    names[3], kinds[3], costs[3] = "Destination", "REACHABLE", 99
    equal(A.GetLive(), nil)
end)

test("special cost text marks a live destination special", function()
    live[2].specialIconCostString = "One travel token"
    local snapshot = assert(A.GetLive())
    equal(find(snapshot.nodes, 2).special, true)
end)

test("legacy fallback requires an unambiguous name and projected position", function()
    C_TaxiMap.GetAllTaxiNodes = nil
    local snapshot = assert(A.GetLive())
    equal(snapshot.sourceID, 1)
    equal(find(snapshot.nodes, 2).slot, 2)
    remote[5] = { nodeID = 20, name = "Destination", faction = 2, position = vector(0.4, 0.2) }
    snapshot = assert(A.GetLive())
    assert(not find(snapshot.nodes, 2))
    assert(not find(snapshot.nodes, 20))
end)

test("missing mapping APIs fail with an explanation", function()
    C_Map = nil
    local preview, reason = A.GetPreview({})
    equal(preview, nil)
    assert(type(reason) == "string")
    equal(A.GetLive(), nil)
end)

test("secret identifiers and positions are excluded safely", function()
    remote[2].nodeID = secret
    remote[3].position = secret
    local preview = assert(A.GetPreview({}))
    equal(#preview.nodes, 1)
end)

test("context distinguishes ordinary nil false from unavailable flags", function()
    UnitOnTaxi = function() return nil end
    equal(A.Context().onTaxi, false)
    UnitOnTaxi = nil
    equal(A.Context().onTaxi, nil)
    UnitOnTaxi = function() error("unavailable") end
    equal(A.Context().onTaxi, nil)
    UnitOnTaxi = function() return secret end
    equal(A.Context().onTaxi, nil)
end)

test("facing is a finite readable angle or nil", function()
    equal(A.Facing(), 1.25)
    for _, value in ipairs({ secret, 0 / 0, math.huge, "north" }) do
        GetPlayerFacing = function() return value end
        equal(A.Facing(), nil)
    end
    GetPlayerFacing = function() error("unavailable") end
    equal(A.Facing(), nil)
    GetPlayerFacing = nil
    equal(A.Facing(), nil)
end)

test("take submits the current slot and does not imply flight started", function()
    local destination = assert(find(assert(A.GetLive()).nodes, 2))
    equal(A.Take(destination), true)
    equal(calls.flights[1], 2)
    equal(A.Context().onTaxi, false)
end)

test("take rechecks changed slots, names, and prices", function()
    local destination = assert(find(assert(A.GetLive()).nodes, 2))
    kinds[2] = "UNREACHABLE"
    equal(A.Take(destination), false)
    kinds[2], names[2] = "REACHABLE", "Wrong destination"
    equal(A.Take(destination), false)
    names[2], costs[2] = "Destination", 501
    equal(A.Take(destination), false)
    costs[2] = nil
    equal(A.Take(destination), false)
    equal(#calls.flights, 0)
end)

test("take blocks unknown and secret travel status", function()
    local destination = assert(find(assert(A.GetLive()).nodes, 2))
    UnitOnTaxi = nil
    equal(A.Take(destination), false)
    UnitOnTaxi = function() return secret end
    equal(A.Take(destination), false)
    equal(#calls.flights, 0)
end)

test("take blocks special flights and reports native call failures", function()
    local destination = assert(find(assert(A.GetLive()).nodes, 2))
    destination.special = true
    equal(A.Take(destination), false)
    destination.special = false
    TakeTaxiNode = function() error("protected") end
    local ok, reason = A.Take(destination)
    equal(ok, false)
    assert(type(reason) == "string")
end)

test("gossip chooses one available flight icon by option ID", function()
    options[2] = { gossipOptionID = 99, icon = 999, status = 0 }
    equal(A.OpenTaxiGossip(), true)
    equal(calls.gossip[1], 42)
end)

test("gossip ignores ambiguous, unavailable, hidden and overridden choices", function()
    options[2] = { gossipOptionID = 88, icon = 132057, status = 0 }
    equal(A.OpenTaxiGossip(), false)
    options[2], options[1].status = nil, 1
    equal(A.OpenTaxiGossip(), false)
    options[1].status, options[1].gossipOptionID = 0, nil
    equal(A.OpenTaxiGossip(), false)
    options[1].gossipOptionID, options[1].overrideIconID = 42, 999
    equal(A.OpenTaxiGossip(), false)
    equal(#calls.gossip, 0)
end)

test("gossip respects Shift and unknown character status", function()
    IsShiftKeyDown = function() return true end
    equal(A.OpenTaxiGossip(), false)
    IsShiftKeyDown, UnitIsDeadOrGhost = function() return false end, nil
    equal(A.OpenTaxiGossip(), false)
    equal(#calls.gossip, 0)
end)

test("client build identity is available for native route freshness", function()
    GetBuildInfo = function() return "1.60.1", "71091", "Nov 24 2026", 16001 end
    equal(A.GetBuildKey(), "1.60.1.71091")
    GetBuildInfo = function() return "1.60.1", secret end
    equal(A.GetBuildKey(), nil)
    GetBuildInfo = nil
    equal(A.GetBuildKey(), nil)
end)

for _, entry in ipairs(tests) do
    reset()
    local ok, reason = pcall(entry[2])
    assert(ok, entry[1] .. ": " .. tostring(reason))
    passed = passed + 1
end
print("API checks passed: " .. passed)
