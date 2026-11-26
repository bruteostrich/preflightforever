local ns = {}
assert(loadfile("Model.lua"))("PreflightForever", ns)
local M = ns.Model
local passed = 0

local function test(name, run)
    local ok, err = pcall(run)
    if not ok then
        error(name .. ": " .. tostring(err), 0)
    end
    passed = passed + 1
    print("ok - " .. name)
end

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function fixture()
    return { sourceID = 10, destinationID = 20, mapID = 1415 }, {
        sourceID = 10, mapID = 1415,
        nodes = {
            { id = 10, slot = 2, state = "CURRENT", name = "Origin" },
            { id = 20, slot = 7, state = "REACHABLE", cost = 100, name = "Destination" },
            { id = 30, slot = 1, state = "UNREACHABLE", cost = 10 },
        },
    }, { inCombat = false, onTaxi = false, dead = false, money = 500 }
end

local function rejected(queue, live, context, contains)
    local node, reason = M.ResolveQueue(queue, live, context)
    equal(node, nil)
    assert(type(reason) == "string" and #reason > 0)
    if contains then
        assert(string.find(reason, contains, 1, true), reason)
    end
end

test("queue records stable IDs and names, never a slot", function()
    local queue = assert(M.NewQueue({ id = 10, name = "Origin", slot = 2 },
        { id = 20, name = "Destination", slot = 7 }, 1415, 123))
    equal(queue.sourceID, 10)
    equal(queue.destinationID, 20)
    equal(queue.sourceName, "Origin")
    equal(queue.destinationName, "Destination")
    equal(queue.mapID, 1415)
    equal(queue.createdAt, 123)
    equal(queue.slot, nil)
end)

test("queue rejects invalid and identical IDs", function()
    for _, value in ipairs({ 0, -1, 1.5, "10", math.huge }) do
        equal(M.NewQueue({ id = value }, { id = 20 }, 1415, 1), nil)
        equal(M.NewQueue({ id = 10 }, { id = value }, 1415, 1), nil)
        equal(M.NewQueue({ id = 10 }, { id = 20 }, value, 1), nil)
    end
    equal(M.NewQueue(nil, { id = 20 }, 1415, 1), nil)
    equal(M.NewQueue({ id = 10 }, { id = 10 }, 1415, 1), nil)
    equal(M.NewQueue({ id = 10 }, { id = 20, transition = true }, 1415, 1), nil)
end)

test("resolves the fresh slot even when ordering changes", function()
    local q, live, context = fixture()
    equal(assert(M.ResolveQueue(q, live, context)).slot, 7)
    live.nodes[2].slot = 12
    live.nodes[1], live.nodes[2] = live.nodes[2], live.nodes[1]
    equal(assert(M.ResolveQueue(q, live, context)).slot, 12)
end)

test("requires the selected origin and flight map", function()
    local q, live, context = fixture()
    live.sourceID = 99
    rejected(q, live, context, "departure")
    live.sourceID = 10
    live.mapID = 1414
    rejected(q, live, context, "different flight map")
end)

test("fails closed with missing queue or live information", function()
    local q, live, context = fixture()
    rejected(nil, live, context)
    rejected({}, live, context)
    rejected(q, nil, context)
    rejected(q, {}, context)
    rejected(q, live, nil)
end)

test("rejects absent or duplicate destination IDs", function()
    local q, live, context = fixture()
    q.destinationID = 99
    rejected(q, live, context, "does not offer")
    q.destinationID = 20
    live.nodes[#live.nodes + 1] = { id = 20, slot = 9, state = "REACHABLE", cost = 100 }
    rejected(q, live, context, "ambiguous")
end)

test("rejects unreachable, unknown, and current destinations", function()
    local q, live, context = fixture()
    for _, state in ipairs({ "UNREACHABLE", "CURRENT", "UNKNOWN", "" }) do
        live.nodes[2].state = state
        rejected(q, live, context, "not reachable")
    end
    live.nodes[2].state = nil
    rejected(q, live, context, "not reachable")
end)

test("rejects map transitions and special fares", function()
    local q, live, context = fixture()
    live.nodes[2].transition = true
    rejected(q, live, context, "Map transitions")
    live.nodes[2].transition = false
    live.nodes[2].special = true
    rejected(q, live, context, "special flight")
end)

test("checks current money and handles a free flight", function()
    local q, live, context = fixture()
    context.money = 99
    rejected(q, live, context, "enough money")
    context.money = 100
    assert(M.ResolveQueue(q, live, context))
    context.money, live.nodes[2].cost = 0, 0
    assert(M.ResolveQueue(q, live, context))
end)

test("rejects invalid fares, balances, and slots", function()
    for _, invalid in ipairs({ -1, "100", math.huge, 0 / 0 }) do
        local q, live, context = fixture()
        live.nodes[2].cost = invalid
        rejected(q, live, context, "fare")
        live.nodes[2].cost = 100
        context.money = invalid
        rejected(q, live, context, "money")
    end
    for _, invalid in ipairs({ 0, -1, 1.5, "7", math.huge }) do
        local q, live, context = fixture()
        live.nodes[2].slot = invalid
        rejected(q, live, context, "slot")
    end
    local q, live, context = fixture()
    live.nodes[2].cost = nil
    rejected(q, live, context, "fare")
end)

test("requires known safe combat, taxi, and life states", function()
    for _, key in ipairs({ "inCombat", "onTaxi", "dead" }) do
        local q, live, context = fixture()
        context[key] = true
        rejected(q, live, context)
        context[key] = nil
        rejected(q, live, context)
    end
end)

test("nearest master uses world distance and filters faction and instance", function()
    local player = { instanceID = 0, worldX = 100, worldY = 200 }
    local nodes = {
        { id = 1, instanceID = 0, worldX = 100, worldY = 200, faction = 1 },
        { id = 2, instanceID = 1, worldX = 100, worldY = 200, faction = 2 },
        { id = 3, instanceID = 0, worldX = 103, worldY = 204, faction = 0 },
        { id = 4, instanceID = 0, worldX = 110, worldY = 200, faction = 2 },
        { id = 5, instanceID = 0, worldX = 100, worldY = 201, faction = 2, transition = true },
    }
    for _, node in ipairs(nodes) do node.learned = true end
    local nearest, distance = M.FindNearest(nodes, player, 2)
    equal(nearest.id, 3)
    equal(distance, 5)
end)

test("nearest master refuses missing or malformed world positions", function()
    local player = { instanceID = 0, worldX = 0, worldY = 0 }
    local nodes = {
        { id = 1, instanceID = 0, x = 0, y = 0, faction = 2 },
        { id = 2, instanceID = 0, worldX = math.huge, worldY = 0, faction = 2 },
        { id = 3, instanceID = 0, worldX = 0 / 0, worldY = 0, faction = 2 },
    }
    for _, node in ipairs(nodes) do node.learned = true end
    equal(M.FindNearest(nodes, player, 2), nil)
    equal(M.FindNearest(nodes, {}, 2), nil)
    equal(M.FindNearest(nodes, nil, 2), nil)
    equal(M.FindNearest(nil, player, 2), nil)
end)

test("nearest distance ties are deterministic", function()
    local player = { instanceID = 0, worldX = 0, worldY = 0 }
    local a = { id = 20, instanceID = 0, worldX = 3, worldY = 4, learned = true }
    local b = { id = 10, instanceID = 0, worldX = -3, worldY = -4, learned = true }
    equal(M.FindNearest({ a, b }, player, 2).id, 10)
    equal(M.FindNearest({ b, a }, player, 2).id, 10)
end)

test("snapshot learns only current and reachable real nodes", function()
    local _, live = fixture()
    live.nodes[4] = { id = 40, state = "REACHABLE", transition = true }
    live.nodes[5] = { id = 50, state = "UNKNOWN" }
    local db = { queue = { destinationID = 999 } }
    assert(M.RecordSnapshot(db, live, 123))
    equal(db.learned[10], true)
    equal(db.learned[20], true)
    equal(db.learned[30], false)
    equal(db.observed[10], true)
    equal(db.observed[20], true)
    equal(db.observed[30], false)
    equal(db.learned[40], nil)
    equal(db.learned[50], nil)
    equal(db.maps[1415].nodes[40], nil)
    equal(db.maps[1415].origins[10].reachable[20], true)
    equal(db.maps[1415].origins[10].reachable[10], nil)
    equal(db.maps[1415].origins[10].seenAt, 123)
    equal(db.queue.destinationID, 999)
end)

test("snapshot merges location data without persisting live slots or prices", function()
    local _, live = fixture()
    live.nodes[2].x, live.nodes[2].y = 0.25, 0.75
    live.nodes[2].instanceID, live.nodes[2].worldX, live.nodes[2].worldY = 0, 150, 250
    live.nodes[2].faction = 2
    local db = {}
    assert(M.RecordSnapshot(db, live, 1))
    local saved = db.maps[1415].nodes[20]
    equal(saved.id, 20)
    equal(saved.name, "Destination")
    equal(saved.x, 0.25)
    equal(saved.y, 0.75)
    equal(saved.instanceID, 0)
    equal(saved.worldX, 150)
    equal(saved.worldY, 250)
    equal(saved.faction, 2)
    equal(saved.slot, nil)
    equal(saved.cost, nil)
    equal(saved.state, nil)
    live.nodes[2] = { id = 20, name = "New name", state = "UNREACHABLE", slot = 42, cost = 999 }
    assert(M.RecordSnapshot(db, live, 2))
    equal(saved.name, "New name")
    equal(saved.x, 0.25)
    equal(saved.worldX, 150)
    equal(saved.slot, nil)
    equal(saved.cost, nil)
    equal(db.learned[20], false)
    equal(db.observed[20], false)
    equal(db.maps[1415].origins[10].reachable[20], nil)
end)

test("native visits correct both remote positive and negative discovery", function()
    local _, live = fixture()
    local db = { learned = { [20] = true, [30] = false }, observed = { [20] = true, [30] = false } }
    live.nodes[2].state, live.nodes[3].state = "UNREACHABLE", "REACHABLE"
    M.RecordSnapshot(db, live, 1)
    equal(db.learned[20], false)
    equal(db.observed[20], false)
    equal(db.learned[30], true)
    equal(db.observed[30], true)
    live.nodes[2].state, live.nodes[3].state = "REACHABLE", "UNREACHABLE"
    M.RecordSnapshot(db, live, 2)
    equal(db.learned[20], true)
    equal(db.observed[20], true)
    equal(db.learned[30], false)
    equal(db.observed[30], false)
end)

test("omitted points invalid states and transitions do not erase observations", function()
    local _, live = fixture()
    local db = { learned = { [20] = true, [30] = false, [40] = true, [99] = true },
        observed = { [20] = true, [30] = false, [40] = true, [99] = true } }
    live.nodes[2].state, live.nodes[3].state = "UNKNOWN", nil
    live.nodes[4] = { id = 40, state = "UNREACHABLE", transition = true }
    live.nodes[5] = { id = -1, state = "UNREACHABLE" }
    M.RecordSnapshot(db, live, 1)
    for _, id in ipairs({ 20, 40, 99 }) do
        equal(db.learned[id], true)
        equal(db.observed[id], true)
    end
    equal(db.learned[30], false)
    equal(db.observed[30], false)
    equal(db.learned[-1], nil)
    equal(db.observed[-1], nil)
end)

test("initialization migrates native proofs without promoting a provisional cache", function()
    local route = { duration = 123 }
    local maps = { [1415] = { origins = { [10] = { reachable = { [20] = true, [30] = false },
        routes = { [20] = route } } } } }
    local queue = { sourceID = 10, destinationID = 20 }
    local db = { maps = maps, learned = { [40] = true }, queue = queue }
    equal(M.InitializeKnowledge(db), true)
    equal(db.observed[10], true)
    equal(db.observed[20], true)
    equal(db.learned[10], true)
    equal(db.learned[20], true)
    equal(db.observed[30], nil)
    equal(db.observed[40], nil)
    equal(db.learned[40], nil)
    equal(db.maps, maps)
    equal(db.maps[1415].origins[10].routes[20], route)
    equal(route.duration, 123)
    equal(db.queue, queue)
end)

test("initialization retains proven imports and discards the old all-known cache", function()
    local db = { learned = { [10] = true, [20] = true, [30] = true, [40] = false },
        importedKnown = {
            [20] = { source = "ForeverDungeonJournal", schema = 2, name = "Known, Zone" },
            [30] = { source = "ForeverDungeonJournal", schema = 2, name = "Corrected, Zone" },
            [40] = true,
            [50] = { source = "Remote", schema = 2, name = "Unverified, Zone" },
            [60] = { source = "ForeverDungeonJournal", schema = 1, name = "Old, Zone" },
            [70] = { source = "ForeverDungeonJournal", schema = 2, name = "" },
            ["80"] = { source = "ForeverDungeonJournal", schema = 2, name = "Invalid, Zone" },
        }, observed = { [30] = false } }
    for _ = 1, 2 do
        M.InitializeKnowledge(db)
        equal(db.learned[10], nil)
        equal(db.learned[20], true)
        equal(db.learned[30], false)
        equal(db.observed[20], nil, "Imports retain their separate provenance")
        equal(db.importedKnown[20].source, "ForeverDungeonJournal")
        for _, id in ipairs({ 40, 50, 60, 70, "80" }) do
            equal(db.learned[id], nil)
            equal(db.importedKnown[id], nil)
        end
    end
end)

test("explicit native corrections override older positive snapshots on every reload", function()
    local db = { maps = { [1415] = { origins = {
        [10] = { reachable = { [20] = true, [30] = true } },
        [50] = { reachable = {} },
    } } }, learned = { [10] = true, [20] = true, [40] = false },
        observed = { [10] = false, [20] = false, [40] = true } }
    for _ = 1, 2 do
        M.InitializeKnowledge(db)
        equal(db.observed[10], false)
        equal(db.observed[20], false)
        equal(db.learned[10], false)
        equal(db.learned[20], false)
        equal(db.learned[30], true)
        equal(db.learned[40], true)
        equal(db.observed[50], true)
    end
end)

test("knowledge initialization and recording repair malformed containers", function()
    equal(M.InitializeKnowledge(nil), false)
    local db = { maps = "invalid", learned = false, observed = 1 }
    equal(M.InitializeKnowledge(db), true)
    equal(type(db.maps), "table")
    equal(type(db.learned), "table")
    equal(type(db.observed), "table")
    equal(type(db.importedKnown), "table")
    db.maps = { [-1] = { origins = { [7] = { reachable = { [8] = true } } } },
        [1415] = { origins = { ["10"] = { reachable = { [20] = true } },
            [11] = "invalid", [12] = { reachable = "invalid" },
            [13] = { reachable = { ["14"] = true, [0] = true, [15] = "true" } },
        } } }
    M.InitializeKnowledge(db)
    equal(db.observed[7], nil)
    equal(db.observed[10], nil)
    equal(db.observed[11], nil)
    equal(db.observed[12], nil)
    equal(db.observed[13], true)
    equal(db.observed[14], nil)
    equal(db.observed[15], nil)
    equal(db.observed[0], nil)
    local _, live = fixture()
    db.learned, db.observed = "invalid", "invalid"
    M.RecordSnapshot(db, live, 1)
    equal(db.observed[20], true)
    equal(db.observed[30], false)
end)

test("recording updates the current snapshot without promoting unrelated old origins", function()
    local _, live = fixture()
    local db = { maps = { [1415] = { origins = { [77] = { reachable = { [88] = true } } } } },
        learned = { [88] = true }, observed = {} }
    M.RecordSnapshot(db, live, 1)
    equal(db.observed[77], nil)
    equal(db.observed[88], nil)
    equal(db.learned[88], true)
    equal(db.observed[20], true)
end)

test("snapshots keep separate origin and map observations", function()
    local _, live = fixture()
    local db = {}
    M.RecordSnapshot(db, live, 1)
    live.sourceID = 99
    M.RecordSnapshot(db, live, 2)
    equal(db.maps[1415].origins[10].seenAt, 1)
    equal(db.maps[1415].origins[99].seenAt, 2)
    live.mapID = 1414
    M.RecordSnapshot(db, live, 3)
    equal(db.maps[1415].origins[99].seenAt, 2)
    equal(db.maps[1414].origins[99].seenAt, 3)
end)

test("invalid snapshots do not damage existing saved data", function()
    local db = { queue = { destinationID = 20 } }
    equal(M.RecordSnapshot(db, {}, 0), false)
    equal(db.maps, nil)
    equal(db.queue.destinationID, 20)
end)

test("nearest departure includes undiscovered points but not transitions", function()
    local player = { instanceID = 0, worldX = 0, worldY = 0 }
    local unknown = { id = 1, instanceID = 0, worldX = 0, worldY = 0 }
    local locked = { id = 2, instanceID = 0, worldX = 1, worldY = 0, learned = true, locked = true }
    local known = { id = 3, instanceID = 0, worldX = 2, worldY = 0, learned = true }
    local transition = { id = 4, instanceID = 0, worldX = 0, worldY = 0, learned = true, transition = true }
    equal(M.FindNearest({ known, locked, unknown, transition }, player, 2), unknown)
    equal(M.FindNearest({ known, locked }, player, 2), locked)
    equal(M.FindNearest({ transition }, player, 2), nil)
end)

test("planning requires a known destination but accepts an undiscovered departure", function()
    local source, destination = { id = 10, learned = true }, { id = 20, learned = true }
    equal(M.CanPlan(source, destination), true)
    for _, field in ipairs({ "learned", "locked", "transition" }) do
        local blocked = { id = 20, learned = true }
        if field == "learned" then blocked.learned = false else blocked[field] = true end
        equal(M.CanPlan(source, blocked), false)
        blocked.id = 10
        equal(M.CanPlan(blocked, destination), field ~= "transition")
    end
    equal(M.CanPlan({ id = 10 }, destination), true)
    equal(M.CanPlan(nil, destination), false)
    equal(M.CanPlan({ name = "No ID" }, destination), false)
    equal(M.CanPlan(source, nil), false)
    equal(M.CanPlan(source, source), false)
    equal(M.CanPlan(source, { id = 20 }), false)
end)

local function routeFixture()
    local _, live = fixture()
    live.nodes[2].route = {
        mapID = 1415, sourceID = 10, destinationID = 20, key = "10:15:20",
        timingKey = "0.10:0.20:0.30:0.40:0.50:0.60",
        points = {
            { id = 10, x = 0.1, y = 0.2, name = "Origin", slot = 2 },
            { id = 15, x = 0.3, y = 0.4, name = "Stop", slot = 3 },
            { id = 20, x = 0.5, y = 0.6, name = "Destination", slot = 7 },
        },
    }
    return live
end

test("snapshot caches ordered native hops without transient slots or aliases", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 1)
    local route = assert(M.GetRoute(db, 1415, 10, 20))
    equal(route.key, "10:15:20")
    equal(route.timingKey, live.nodes[2].route.timingKey)
    equal(#route.points, 3)
    equal(route.points[2].id, 15)
    equal(route.points[2].name, "Stop")
    equal(route.points[2].slot, nil)
    live.nodes[2].route.points[2].x = 0.9
    equal(route.points[2].x, 0.3)
    route.points[2].x = 0.8
    equal(M.GetRoute(db, 1415, 10, 20).points[2].x, 0.3)
end)

test("recorded duration is normalized and only attached to the exact route", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 1)
    equal(M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, 1.2), true)
    local route = assert(M.GetRoute(db, 1415, 10, 20))
    equal(route.duration, 120)
    equal(route.durationSource, "Recorded flight")
    equal(M.RecordDuration(db, 1415, 10, 20, "10:20", 500, 1), false)
    equal(M.GetRoute(db, 1415, 10, 20).duration, 120)
    M.RecordSnapshot(db, live, 2)
    equal(M.GetRoute(db, 1415, 10, 20).duration, 120)
end)

test("a native capture can include an unknown intermediate without being stale", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 123)
    equal(db.learned[15], nil)
    local route = assert(M.GetRoute(db, 1415, 10, 20))
    equal(route.stale, false)
    equal(route.recordedAt, 123)
    equal(route.points[2].id, 15)
end)

test("knowledge changes mark older native captures stale without erasing timing", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 1)
    M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, 1)
    M.RecordSnapshot(db, { mapID = 1415, sourceID = 99, nodes = {
        { id = 99, state = "CURRENT", name = "New origin" },
        { id = 30, state = "REACHABLE", name = "Newly discovered" },
    } }, 2)
    local older = assert(M.GetRoute(db, 1415, 10, 20))
    equal(older.stale, true)
    equal(older.staleReason, "knowledge")
    equal(older.duration, 100)
    equal(older.recordedAt, 1)
    equal(db.maps[1415].origins[10].routes[20].stale, nil)
    M.RecordSnapshot(db, live, 3)
    local refreshed = assert(M.GetRoute(db, 1415, 10, 20))
    equal(refreshed.stale, false)
    equal(refreshed.staleReason, nil)
    equal(refreshed.recordedAt, 3)
    equal(refreshed.duration, 100)
end)

test("only effective known IDs affect native capture freshness", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 1)
    db.learned = { [30] = false, [20] = true, [10] = true, [123] = false,
        ["88"] = true, [44] = "true" }
    equal(M.GetRoute(db, 1415, 10, 20).stale, false)
    db.learned[123] = true
    equal(M.GetRoute(db, 1415, 10, 20).stale, true)
    db.learned[123] = false
    equal(M.GetRoute(db, 1415, 10, 20).stale, false)
end)

test("legacy captures without knowledge context are preserved as previously recorded", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 7)
    M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, 1)
    db.maps[1415].origins[10].knowledgeKey = nil
    local route = assert(M.GetRoute(db, 1415, 10, 20))
    equal(route.stale, true)
    equal(route.recordedAt, 7)
    equal(route.duration, 100)
    equal(db.maps[1415].origins[10].knowledgeKey, nil)
end)

test("a changed client build marks recorded routes stale until refreshed", function()
    local db, live = { clientBuild = "1.60.1.71091" }, routeFixture()
    M.RecordSnapshot(db, live, 1)
    M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, 1)
    equal(M.GetRoute(db, 1415, 10, 20).stale, false)
    db.clientBuild = "1.60.1.71092"
    local older = assert(M.GetRoute(db, 1415, 10, 20))
    equal(older.stale, true)
    equal(older.staleReason, "build")
    equal(older.duration, 100)
    M.RecordSnapshot(db, live, 2)
    local refreshed = assert(M.GetRoute(db, 1415, 10, 20))
    equal(refreshed.stale, false)
    equal(refreshed.staleReason, nil)
    equal(refreshed.duration, 100)
    equal(db.maps[1415].origins[10].clientBuild, "1.60.1.71092")
end)

test("a changed path invalidates the old path's timing", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 1)
    M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, 1)
    live.nodes[2].route.points[2].id = 16
    live.nodes[2].route.key = "10:16:20"
    M.RecordSnapshot(db, live, 2)
    equal(M.GetRoute(db, 1415, 10, 20).duration, nil)
    equal(M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, 1), false)
end)

test("route lookup rejects unknown or no-longer-reachable endpoints", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 1)
    db.learned[20] = nil
    equal(M.GetRoute(db, 1415, 10, 20), nil)
    db.learned[20], db.learned[10] = true, nil
    equal(M.GetRoute(db, 1415, 10, 20), nil)
    db.learned[10] = true
    live.nodes[2].state = "UNREACHABLE"
    M.RecordSnapshot(db, live, 2)
    equal(M.GetRoute(db, 1415, 10, 20), nil)
    equal(M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, 1), false)
end)

test("malformed or broken hop geometry is never cached as a route", function()
    local changes = {
        function(route) route.points[1].id = 11 end,
        function(route) route.points[3].id = 21 end,
        function(route) route.points[2].x = nil end,
        function(route) route.points[2].x = math.huge end,
        function(route) route.points[2].y = 0 / 0 end,
        function(route) route.points[2].y = 1.1 end,
        function(route) route.points[2].id = 10; route.key = "10:10:20" end,
        function(route) route.key = "10:20" end,
        function(route) route.points = { route.points[1] } end,
        function(route) route.mapID = 1414 end,
    }
    for _, change in ipairs(changes) do
        local db, live = {}, routeFixture()
        change(live.nodes[2].route)
        M.RecordSnapshot(db, live, 1)
        equal(M.GetRoute(db, 1415, 10, 20), nil)
        equal(db.maps[1415].origins[10].routes[20], nil)
    end
end)

test("invalid duration values and corrupt saved route records are rejected", function()
    local db, live = {}, routeFixture()
    M.RecordSnapshot(db, live, 1)
    for _, bad in ipairs({ -1, 0, "100", math.huge, 0 / 0, 86400 }) do
        equal(M.RecordDuration(db, 1415, 10, 20, "10:15:20", bad, 1), false)
    end
    for _, bad in ipairs({ -1, 0, "1", math.huge, 0 / 0 }) do
        equal(M.RecordDuration(db, 1415, 10, 20, "10:15:20", 100, bad), false)
    end
    equal(M.GetRoute({}, 1415, 10, 20), nil)
    db.maps[1415].origins[10].routes[20].points[2] = false
    equal(M.GetRoute(db, 1415, 10, 20), nil)
end)

test("optional lookup keys and supplied timings are sanitized", function()
    local db, live = {}, routeFixture()
    live.nodes[2].route.duration, live.nodes[2].route.durationSource = 99, "Database estimate"
    live.nodes[2].route.timingKey = "0.10::0.20:0.30:0.40:0.50:0.60"
    M.RecordSnapshot(db, live, 1)
    local route = assert(M.GetRoute(db, 1415, 10, 20))
    equal(route.duration, 99)
    equal(route.durationSource, "Database estimate")
    equal(route.timingKey, nil)
    live.nodes[2].route = nil
    M.RecordSnapshot(db, live, 2)
    equal(M.GetRoute(db, 1415, 10, 20), nil)
end)

print(string.format("%d model tests passed", passed))
