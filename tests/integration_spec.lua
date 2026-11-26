local passed = 0

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
    local ok, err = pcall(run)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("ok - " .. name)
end

local function liveMap(slot)
    return {
        mapID = 1415, sourceID = 10,
        nodes = {
            { id = 10, name = "Origin", slot = 2, state = "CURRENT", x = 0.2, y = 0.2,
                instanceID = 0, worldX = 0, worldY = 0, faction = 2 },
            { id = 20, name = "Destination", slot = slot or 7, state = "REACHABLE", cost = 100,
                x = 0.8, y = 0.8, instanceID = 0, worldX = 100, worldY = 100, faction = 2 },
        },
    }
end

local function harness(options)
    options = options or {}
    local h = {
        now = 0, nextTimer = 0, timers = {}, messages = {}, takes = {}, frames = {},
        shift = false, liveReads = 0, renderCount = 0, showCount = 0, hideCount = 0,
        gossipCount = 0, live = liveMap(),
        context = { inCombat = false, onTaxi = false, dead = false, money = 500 },
    }
    local ns = {}
    h.ns = ns
    PreflightDB = options.db
    SlashCmdList = {}
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) h.messages[#h.messages + 1] = message end }
    time = function() return math.floor(h.now) end
    IsShiftKeyDown = function() return h.shift end
    C_Timer = {
        After = function(delay, callback)
            h.nextTimer = h.nextTimer + 1
            h.timers[#h.timers + 1] = { at = h.now + delay, id = h.nextTimer, callback = callback }
        end,
    }
    CreateFrame = function()
        local frame = { scripts = {}, registered = {} }
        function frame:SetScript(name, callback) self.scripts[name] = callback end
        function frame:RegisterEvent(name) self.registered[name] = true end
        function frame:UnregisterEvent(name) self.registered[name] = nil end
        h.frames[#h.frames + 1] = frame
        return frame
    end
    h.preview = {
        mapID = 1415, mapName = "Eastern Kingdoms", nodes = liveMap().nodes,
        player = { instanceID = 0, worldX = 1, worldY = 1 }, faction = 2,
    }
    for _, node in ipairs(h.preview.nodes) do node.learned = true end
    ns.API = {
        GetBuildKey = function() return "1.60.1:71091:16001" end,
        GetPreview = function() return h.preview end,
        GetLive = function()
            h.liveReads = h.liveReads + 1
            if h.getLive then return h.getLive(h.liveReads) end
            return h.live
        end,
        Context = function() return h.context end,
        Take = function(node)
            h.takes[#h.takes + 1] = node.slot
            if h.take then return h.take(node) end
            return true
        end,
        OpenTaxiGossip = function() h.gossipCount = h.gossipCount + 1 end,
    }
    ns.UI = {
        Init = function() h.initialized = true end,
        Render = function(preview, origin, distance, reason)
            h.renderCount = h.renderCount + 1
            h.render = { preview = preview, origin = origin, distance = distance, reason = reason }
        end,
        Toggle = function() h.toggled = not h.toggled end,
        Show = function() h.showCount = h.showCount + 1 end,
        Hide = function() h.hideCount = h.hideCount + 1 end,
        ResetPosition = function() h.reset = true end,
    }
    assert(loadfile("Model.lua"))("PreflightForever", ns)
    assert(loadfile("Main.lua"))("PreflightForever", ns)
    function h:event(name, arg)
        self.ns.events.scripts.OnEvent(self.ns.events, name, arg)
    end
    function h:advance(delta)
        local stop = self.now + delta
        local callbacks = 0
        while true do
            table.sort(self.timers, function(a, b)
                if a.at == b.at then return a.id < b.id end
                return a.at < b.at
            end)
            local timer = self.timers[1]
            if not timer or timer.at > stop + 0.0000001 then break end
            table.remove(self.timers, 1)
            self.now = timer.at
            callbacks = callbacks + 1
            assert(callbacks < 1000, "timer loop did not terminate")
            timer.callback()
        end
        self.now = stop
    end
    function h:queue()
        self.ns.Refresh()
        self.ns.Queue(self.preview.nodes[2])
        assert(self.ns.db.queue, "fixture could not queue destination")
        return self.ns.db.queue
    end
    function h:said(fragment)
        for _, message in ipairs(self.messages) do
            if string.find(message, fragment, 1, true) then return true end
        end
        return false
    end
    function h:useRemotePreview(journal)
        -- Exercise the real preview adapter and controller together. Travel
        -- remains stubbed: these checks never stand in for a live client test.
        ForeverDungeonJournalCharacterDB = journal
        for _, node in ipairs(self.live.nodes) do
            node.worldX, node.worldY = node.x * 1000, node.y * 1000
        end
        issecretvalue = nil
        UnitFactionGroup = function() return "Alliance" end
        CreateVector2D = function(x, y) return { x = x, y = y } end
        C_Map = {
            GetBestMapForUnit = function() return 1415 end,
            GetMapInfo = function() return { mapType = 2, name = "Eastern Kingdoms" } end,
            GetPlayerMapPosition = function() return { x = 0.21, y = 0.21 } end,
            GetWorldPosFromMapPos = function(_, position)
                return 0, { x = position.x * 1000, y = position.y * 1000 }
            end,
            GetMapPosFromWorldPos = function(_, position, mapID)
                return mapID, { x = position.x / 1000, y = position.y / 1000 }
            end,
        }
        C_TaxiMap = { GetTaxiNodesForMap = function()
            return {
                { nodeID = 10, name = "Origin", position = { x = 0.2, y = 0.2 }, faction = 2, isUndiscovered = false },
                { nodeID = 20, name = "Destination", position = { x = 0.8, y = 0.8 }, faction = 2, isUndiscovered = false },
                { nodeID = 30, name = "Unverified", position = { x = 0.5, y = 0.5 }, faction = 2, isUndiscovered = false },
            }
        end }
        local mocked = ns.API
        assert(loadfile("API.lua"))("PreflightForever", ns)
        ns.API.GetLive, ns.API.Context, ns.API.Take, ns.API.OpenTaxiGossip =
            mocked.GetLive, mocked.Context, mocked.Take, mocked.OpenTaxiGossip
        -- Main captures the API table at load time; keep that identity and
        -- replace only preview so its actual discovery logic is exercised.
        mocked.GetPreview = ns.API.GetPreview
        ns.API = mocked
        ns.Refresh()
        self.preview = ns.preview
    end
    h:event("ADDON_LOADED", "AnotherAddon")
    equal(ns.db, nil)
    h:event("ADDON_LOADED", "PreflightForever")
    return h
end

test("known selection queues without reading a live map or taking a flight", function()
    local h = harness()
    assert(h.initialized)
    equal(next(h.ns.db.learned), nil)
    equal(next(h.ns.db.observed), nil)
    local queue = h:queue()
    equal(queue.sourceID, 10)
    equal(queue.destinationID, 20)
    equal(h.liveReads, 0)
    equal(#h.takes, 0)
    h.ns.Depart()
    equal(#h.takes, 0)
    h:advance(5)
    equal(#h.takes, 0)
end)

test("native visits correct stale verified destinations without automatic departure", function()
    for _, mode in ipairs({ "no queue", "shift", "manual" }) do
        local h = harness({ db = { importedKnown = {
            [10] = { source = "ForeverDungeonJournal", schema = 2, name = "Origin" },
            [20] = { source = "ForeverDungeonJournal", schema = 2, name = "Destination" },
        } } })
        local queue
        if mode ~= "no queue" then queue = h:queue() end
        h.shift = mode == "shift"
        h.ns.db.autoDepart = mode ~= "manual"
        h.live.nodes[2].state = "UNREACHABLE"
        h:event("TAXIMAP_OPENED")
        h:advance(0.2)
        equal(h.ns.db.observed[10], true)
        equal(h.ns.db.observed[20], false)
        equal(h.ns.db.learned[20], false)
        equal(h.ns.db.queue, queue)
        equal(#h.takes, 0)
    end
end)

test("the final live read corrects knowledge before an unreachable flight is rejected", function()
    local h = harness()
    local queue = h:queue()
    h.getLive = function(read)
        local live = liveMap()
        if read >= 2 then live.nodes[2].state = "UNREACHABLE" end
        return live
    end
    h:event("TAXIMAP_OPENED")
    h:advance(0.2)
    equal(h.liveReads, 2)
    equal(#h.takes, 0)
    equal(h.ns.db.observed[20], false)
    equal(h.ns.db.learned[20], false)
    equal(h.ns.live.nodes[2].state, "UNREACHABLE")
    equal(h.ns.db.queue, queue)
    assert(h:said("not reachable"))
    h:event("TAXIMAP_CLOSED")
    local reloaded = harness({ db = h.ns.db })
    equal(reloaded.ns.db.observed[20], false)
    equal(reloaded.ns.db.learned[20], false)
    equal(reloaded.ns.db.queue, nil)
end)

test("a native visit can replace an earlier negative correction with learned status", function()
    local h = harness({ db = { observed = { [20] = false }, learned = { [20] = false } } })
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(h.ns.db.observed[20], true)
    equal(h.ns.db.learned[20], true)
    equal(#h.takes, 0)
end)

test("node status changes refresh an open taxi interaction without starting a flight", function()
    local h = harness()
    assert(h.ns.events.registered.TAXI_NODE_STATUS_CHANGED)
    h:queue()
    h:event("TAXI_NODE_STATUS_CHANGED")
    equal(h.liveReads, 0)
    h.live.nodes[2].state = "UNREACHABLE"
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(h.ns.db.observed[20], false)
    h.live.nodes[2].state = "REACHABLE"
    h:event("TAXI_NODE_STATUS_CHANGED")
    equal(h.ns.db.observed[20], true)
    equal(h.ns.db.learned[20], true)
    equal(#h.takes, 0)
    h:event("TAXIMAP_CLOSED")
    local reads = h.liveReads
    h.live.nodes[2].state = "UNREACHABLE"
    h:event("TAXI_NODE_STATUS_CHANGED")
    equal(h.liveReads, reads)
    equal(h.ns.db.observed[20], true)
    equal(#h.takes, 0)
end)

test("load migration honors a negative correction over an older reachable route and queue", function()
    local h = harness({ db = {
        version = 2, learned = { [10] = true, [20] = true }, observed = { [20] = false },
        maps = { [1415] = { origins = { [10] = { reachable = { [20] = true } } } } },
        queue = { sourceID = 10, destinationID = 20, mapID = 1415 },
    } })
    equal(h.ns.db.version, 4)
    equal(h.ns.db.observed[10], true)
    equal(h.ns.db.observed[20], false)
    equal(h.ns.db.learned[20], false)
    equal(h.ns.db.queue, nil)
end)

test("opening the exact source revalidates the destination's newest slot", function()
    local h = harness()
    h:queue()
    h.getLive = function(read) return liveMap(read == 1 and 7 or 12) end
    h:event("TAXIMAP_OPENED")
    equal(#h.takes, 0)
    h:advance(0.1)
    equal(#h.takes, 1)
    equal(h.takes[1], 12)
    equal(h.liveReads, 2)
    assert(h.ns.db.queue, "queue must survive until taxi travel is confirmed")
    equal(h.ns.db.learned[10], true)
    equal(h.ns.db.learned[20], true)
end)

test("a different departure master retains the queue without travel", function()
    local h = harness()
    local queue = h:queue()
    h.live.sourceID = 99
    h:event("TAXIMAP_OPENED")
    h:advance(2)
    equal(#h.takes, 0)
    equal(h.ns.db.queue, queue)
    assert(h:said("departure flight master"))
end)

test("insufficient funds retain the queue without travel", function()
    local h = harness()
    local queue = h:queue()
    h.context.money = 99
    h:event("TAXIMAP_OPENED")
    h:advance(2)
    equal(#h.takes, 0)
    equal(h.ns.db.queue, queue)
    assert(h:said("enough money"))
end)

test("holding Shift at interaction time suppresses departure after release", function()
    local h = harness()
    local queue = h:queue()
    h.shift = true
    h:event("TAXIMAP_OPENED")
    h.shift = false
    h:advance(2)
    equal(#h.takes, 0)
    equal(h.ns.db.queue, queue)
    assert(h:said("skipped"))
end)

test("late flight data is retried and taken once it becomes available", function()
    local h = harness()
    h:queue()
    h.getLive = function(read)
        if read <= 2 then return nil, "Still loading" end
        return liveMap()
    end
    h:event("TAXIMAP_OPENED")
    h:advance(0.2)
    equal(#h.takes, 0)
    h:advance(0.1)
    equal(#h.takes, 1)
    equal(h.liveReads, 4)
end)

test("closing the map cancels pending data retries", function()
    local h = harness()
    local queue = h:queue()
    h.getLive = function() return nil, "Still loading" end
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(h.liveReads, 1)
    h:event("TAXIMAP_CLOSED")
    h.getLive = function() return liveMap() end
    h:advance(2)
    equal(h.liveReads, 1)
    equal(#h.takes, 0)
    equal(h.ns.db.queue, queue)
end)

test("unavailable flight data eventually stops retrying with the queue intact", function()
    local h = harness()
    local queue = h:queue()
    h.getLive = function() return nil, "Still loading" end
    h:event("TAXIMAP_OPENED")
    h:advance(5)
    assert(h.liveReads > 1 and h.liveReads <= 12)
    equal(#h.takes, 0)
    equal(h.ns.db.queue, queue)
    equal(#h.timers, 0)
    assert(h:said("Still loading"))
end)

test("confirmation mode waits for explicit Depart", function()
    local h = harness({ db = { autoDepart = false } })
    h:queue()
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(#h.takes, 0)
    equal(h.showCount, 1)
    h.ns.Depart()
    equal(#h.takes, 1)
    assert(h:said("Depart now"))
end)

test("a changed fare on the final read prevents departure", function()
    local h = harness()
    local queue = h:queue()
    h.getLive = function(read)
        local live = liveMap()
        if read >= 2 then live.nodes[2].cost = 1000 end
        return live
    end
    h:event("TAXIMAP_OPENED")
    h:advance(1)
    equal(#h.takes, 0)
    equal(h.ns.db.queue, queue)
    assert(h:said("enough money"))
end)

test("a rejected flight request preserves the queue", function()
    local h = harness()
    local queue = h:queue()
    h.take = function() return false, "Client refused this flight" end
    h:event("TAXIMAP_OPENED")
    h:advance(1)
    equal(#h.takes, 1)
    equal(h.ns.db.queue, queue)
    equal(h.ns.attempt, nil)
    assert(h:said("Client refused this flight"))
end)

test("an unconfirmed accepted request times out without consuming the queue", function()
    local h = harness()
    local queue = h:queue()
    h:event("TAXIMAP_OPENED")
    h:advance(4)
    equal(#h.takes, 1)
    equal(h.ns.db.queue, queue)
    equal(h.ns.attempt, nil)
    equal(#h.timers, 0)
    assert(h:said("not confirmed"))
end)

test("unknown taxi status does not confirm a departure", function()
    local h = harness()
    local queue = h:queue()
    h.take = function() h.context.onTaxi = nil; return true end
    h:event("TAXIMAP_OPENED")
    h:advance(4)
    equal(#h.takes, 1)
    equal(h.ns.db.queue, queue)
    equal(h.ns.attempt, nil)
end)

test("confirmed taxi travel consumes the queue exactly once", function()
    local h = harness()
    h:queue()
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    h.context.onTaxi = true
    h:event("PLAYER_CONTROL_LOST")
    equal(h.ns.db.queue, nil)
    equal(h.ns.attempt, nil)
    equal(h.hideCount, 1)
    h:event("PLAYER_CONTROL_LOST")
    h:advance(4)
    equal(#h.takes, 1)
    equal(h.hideCount, 1)
end)

test("map closure after Take does not discard delayed travel confirmation", function()
    local h = harness()
    h:queue()
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    h:event("TAXIMAP_CLOSED")
    h.context.onTaxi = true
    h:advance(0.2)
    equal(h.ns.db.queue, nil)
    equal(h.ns.attempt, nil)
    equal(#h.takes, 1)
end)

test("duplicate opened events cannot start an in-flight attempt twice", function()
    local h = harness()
    h:queue()
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(#h.takes, 1)
    h.context.onTaxi = true
    h:advance(0.2)
    equal(h.ns.db.queue, nil)
    equal(#h.takes, 1)
end)

test("a newer interaction invalidates the previous scheduled read", function()
    local h = harness()
    h:queue()
    h:event("TAXIMAP_OPENED")
    h:event("TAXIMAP_CLOSED")
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(h.liveReads, 2)
    equal(#h.takes, 1)
end)

test("clear command cancels a queued departure before its pending timer", function()
    local h = harness()
    h:queue()
    h:event("TAXIMAP_OPENED")
    SlashCmdList.PREFLIGHT("  clear ")
    h:advance(1)
    equal(h.ns.db.queue, nil)
    equal(h.ns.attempt, nil)
    equal(#h.takes, 0)
    assert(h:said("cleared"))
end)

test("clear command invalidates confirmation polling after an attempted flight", function()
    local h = harness()
    h:queue()
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    SlashCmdList.PREFLIGHT("clear")
    h.context.onTaxi = true
    h:advance(4)
    equal(h.ns.db.queue, nil)
    equal(h.ns.attempt, nil)
    equal(h.hideCount, 0)
    equal(#h.takes, 1)
end)

test("world transition cancels a pending interaction without losing the queue", function()
    local h = harness()
    local queue = h:queue()
    h:event("TAXIMAP_OPENED")
    h:event("PLAYER_ENTERING_WORLD")
    h:advance(1)
    equal(#h.takes, 0)
    equal(h.ns.db.queue, queue)
    equal(h.ns.taxiOpen, false)
end)

test("gossip automation only runs for an active automatic queue", function()
    local h = harness()
    h:event("GOSSIP_SHOW")
    equal(h.gossipCount, 0)
    h:queue()
    h.shift = true
    h:event("GOSSIP_SHOW")
    equal(h.gossipCount, 0)
    h.shift = false
    h.ns.db.autoDepart = false
    h:event("GOSSIP_SHOW")
    equal(h.gossipCount, 0)
    h.ns.db.autoDepart = true
    h:event("GOSSIP_SHOW")
    equal(h.gossipCount, 1)
end)

test("auto command changes departure behavior and survives saved variables", function()
    local db = { autoDepart = false }
    local h = harness({ db = db })
    equal(h.ns.db.autoDepart, false)
    SlashCmdList.PREFLIGHT("auto")
    equal(db.autoDepart, true)
    SlashCmdList.PREFLIGHT("auto")
    equal(db.autoDepart, false)
end)

test("corrupt saved queues are discarded safely during addon loading", function()
    for _, queue in ipairs({ "invalid", {}, { sourceID = 10, destinationID = 10, mapID = 1415 },
        { sourceID = "10", destinationID = 20, mapID = 1415 },
        { sourceID = 10, destinationID = 20, mapID = -1 } }) do
        local h = harness({ db = { queue = queue, maps = "invalid", learned = false } })
        equal(h.ns.db.queue, nil)
        equal(type(h.ns.db.maps), "table")
        equal(type(h.ns.db.learned), "table")
        SlashCmdList.PREFLIGHT("status")
        assert(h:said("No flight queued"))
        h.ns.Refresh()
    end
end)

test("valid saved IDs survive reload with sanitized display names and no saved slots", function()
    local h = harness({ db = { observed = { [10] = true, [20] = true }, queue = { sourceID = 10, destinationID = 20, mapID = 1415,
        sourceName = {}, destinationName = false, createdAt = "invalid", slot = 99 } } })
    equal(h.ns.db.queue.sourceID, 10)
    equal(h.ns.db.queue.destinationID, 20)
    equal(h.ns.db.queue.sourceName, "Flight point #10")
    equal(h.ns.db.queue.destinationName, "Flight point #20")
    equal(h.ns.db.queue.createdAt, 0)
    equal(h.ns.db.queue.slot, nil)
    SlashCmdList.PREFLIGHT("status")
    assert(h:said("Flight point #20"))
end)

test("unknown destination cannot be queued even through a direct controller call", function()
    local h = harness()
    h.ns.Refresh()
    h.preview.nodes[2].learned = false
    h.ns.Queue(h.preview.nodes[2])
    equal(h.ns.db.queue, nil)
    equal(#h.takes, 0)
    assert(h:said("Discover that flight point"))
    h.preview.nodes[2].learned = true
    h.preview.nodes[2].locked = true
    h.ns.Queue(h.preview.nodes[2])
    equal(h.ns.db.queue, nil)
end)

test("with no known flight points the closest is the departure but nothing can be queued", function()
    local h = harness()
    for _, node in ipairs(h.preview.nodes) do node.learned, node.locked = false, true end
    h.ns.Refresh()
    equal(h.ns.origin.id, 10)
    h.ns.Queue(h.preview.nodes[2])
    equal(h.ns.db.queue, nil)
    assert(h:said("Discover that flight point"))
    equal(#h.takes, 0)
end)

test("an undiscovered closest flight master is the departure and is learned on arrival", function()
    local h = harness()
    h.preview.nodes[1].learned, h.preview.nodes[1].locked = false, true
    local queue = h:queue()
    equal(queue.sourceID, 10)
    equal(h.ns.db.learned[10], nil)
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(#h.takes, 1)
    equal(h.ns.db.learned[10], true)
end)

test("a saved queue from an undiscovered departure survives reload", function()
    local h = harness({ db = { observed = { [20] = true }, queue = { sourceID = 10, destinationID = 20,
        mapID = 1415, sourceName = "Origin", destinationName = "Destination" } } })
    equal(h.ns.db.learned[10], nil)
    equal(h.ns.db.queue.sourceID, 10)
    equal(h.ns.db.queue.destinationID, 20)
end)

test("an old saved queue for unconfirmed endpoints is cleared on reload", function()
    for _, learned in ipairs({ {}, { [10] = true }, { [20] = true }, { [10] = true, [20] = true } }) do
        local h = harness({ db = { learned = learned, queue = {
            sourceID = 10, destinationID = 20, mapID = 1415,
            sourceName = "Origin", destinationName = "Destination",
        } } })
        equal(h.ns.db.queue, nil)
        h:event("TAXIMAP_OPENED")
        h:advance(1)
        equal(#h.takes, 0)
    end
end)

test("all-known remote flags cannot restore a polluted queue or unlock points", function()
    local h = harness({ db = {
        version = 3, learned = { [10] = true, [20] = true, [30] = true },
        queue = { sourceID = 10, destinationID = 20, mapID = 1415 },
    } })
    h:useRemotePreview(nil)
    equal(h.ns.db.queue, nil)
    equal(h.ns.origin.id, 10)
    equal(h.ns.db.lastDiagnostics.known, 0)
    equal(h.ns.db.lastDiagnostics.total, 3)
    for _, node in ipairs(h.ns.preview.nodes) do
        equal(node.learned, false)
        equal(node.locked, true)
        h.ns.Queue(node)
        equal(h.ns.db.queue, nil)
    end
    equal(next(h.ns.db.observed), nil)
    equal(h.liveReads, 0)
    equal(#h.takes, 0)
end)

test("journal-verified endpoints queue immediately while remote-only points remain blocked", function()
    local h = harness()
    h:useRemotePreview({ flightPointsVersion = 2, flightPoints = { origin = true, destination = true } })
    equal(h.ns.origin.id, 10)
    equal(h.ns.db.lastDiagnostics.known, 2)
    local unverified = h.ns.preview.nodes[3]
    equal(unverified.id, 30)
    h.ns.Queue(unverified)
    equal(h.ns.db.queue, nil)
    local queue = h:queue()
    equal(queue.sourceID, 10)
    equal(queue.destinationID, 20)
    equal(h.liveReads, 0)
    equal(#h.takes, 0)
    -- Imports survive a reload even if the optional journal is unavailable.
    local reloaded = harness({ db = h.ns.db })
    reloaded:useRemotePreview(nil)
    equal(reloaded.ns.db.queue.destinationID, 20)
    equal(reloaded.ns.db.lastDiagnostics.known, 2)
end)

test("native correction replaces imported knowledge despite all-known remote flags", function()
    local h = harness({ db = { autoDepart = false } })
    h:useRemotePreview({ flightPointsVersion = 2, flightPoints = { origin = true, destination = true } })
    h.live.nodes[2].state = "UNREACHABLE"
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    equal(h.ns.db.observed[20], false)
    equal(h.ns.preview.nodes[2].learned, false)
    h.ns.Queue(h.ns.preview.nodes[2])
    equal(h.ns.db.queue, nil)
    h.live.nodes[2].state = "REACHABLE"
    h:event("TAXI_NODE_STATUS_CHANGED")
    equal(h.ns.db.observed[20], true)
    equal(h.ns.preview.nodes[2].learned, true)
    h.ns.Queue(h.ns.preview.nodes[2])
    equal(h.ns.db.queue.destinationID, 20)
    equal(#h.takes, 0)
end)

test("native route audits record matches and differences without starting queued travel", function()
    local h = harness({ db = { autoDepart = false } })
    equal(h.ns.db.clientBuild, "1.60.1:71091:16001")
    local source = { id = 10, name = "Origin", x = 0.2, y = 0.2, instanceID = 0, faction = 2, learned = true }
    local destination = { id = 20, name = "Destination", x = 0.8, y = 0.8, instanceID = 0, faction = 2, learned = true }
    local intermediate = { id = 30, name = "Intermediate", x = 0.5, y = 0.5, instanceID = 0, faction = 2, learned = true }
    local matching = { id = 40, name = "Matching", x = 0.3, y = 0.6, instanceID = 0, faction = 2, learned = true }
    for _, node in ipairs({ source, destination, intermediate, matching }) do
        node.worldX, node.worldY = node.x * 1000, node.y * 1000
    end
    h.preview.nodes = { source, destination, intermediate, matching }
    h.preview.player = { instanceID = 0, worldX = 201, worldY = 201 }
    source.state, source.slot = "CURRENT", 2
    destination.state, destination.slot, destination.cost = "REACHABLE", 7, 100
    destination.route = { key = "10:30:20", points = { source, intermediate, destination } }
    intermediate.state, intermediate.slot, intermediate.cost = "REACHABLE", 8, 100
    intermediate.route = { key = "10:30", points = { source, intermediate } }
    matching.state, matching.slot, matching.cost = "REACHABLE", 9, 100
    matching.route = { key = "10:40", points = { source, matching } }
    h.live.nodes = h.preview.nodes
    h.ns.RouteEdges, h.ns.RouteDataBuild = { 10, 20, 100, 10, 40, 100 }, "bundled-build"
    assert(loadfile("Routes.lua"))("PreflightForever", h.ns)
    local compare, comparisons = h.ns.Routes.Compare, 0
    h.ns.Routes.Compare = function(preview, live)
        comparisons = comparisons + 1
        equal(preview, h.ns.preview)
        equal(live, h.ns.live)
        equal(h.ns.db.observed[20], true) -- Snapshot corrections precede comparison.
        assert(h.ns.db.maps[1415].origins[10].routes[20])
        return compare(preview, live)
    end
    local queue = h:queue()
    h:event("TAXIMAP_OPENED")
    h:advance(0.1)
    local audit = h.ns.db.lastRouteAudit
    equal(comparisons, 1)
    equal(audit.clientBuild, "1.60.1:71091:16001")
    equal(audit.dataBuild, "bundled-build")
    equal(audit.seenAt, 0)
    equal(audit.matched, 1)
    equal(audit.different, 1)
    equal(audit.unavailable, 1)
    equal(audit.differences[20].native, "10:30:20")
    equal(audit.differences[20].estimated, "10:20")
    equal(h.ns.db.queue, queue)
    equal(#h.takes, 0)
    destination.route = { key = "10:20", points = { source, destination } }
    h:event("TAXI_NODE_STATUS_CHANGED")
    equal(comparisons, 2)
    equal(h.ns.db.lastRouteAudit.matched, 2)
    equal(h.ns.db.lastRouteAudit.different, 0)
    equal(h.ns.db.queue, queue)
    equal(#h.takes, 0)
    h:event("TAXIMAP_CLOSED")
    h:event("TAXI_NODE_STATUS_CHANGED")
    equal(comparisons, 2)
    SlashCmdList.PREFLIGHT("debug")
    assert(h:said("2 matched"))
    assert(h:said("0 differed"))
    assert(h:said("1 without an estimate"))
    equal(#h.takes, 0)
end)

test("debug report preserves actual tile and knowledge counts without altering a queue", function()
    local h = harness()
    local queue = h:queue()
    h.ns.UI.GetMapDiagnostics = function()
        return { mode = "loading", textureCount = 12, expectedTextures = 12,
            loadedTextures = 11, reason = "Map texture files are still loading." }
    end
    h.preview.nodes[2].learned = false
    SlashCmdList.PREFLIGHT("debug")
    equal(h.ns.db.lastDiagnostics.known, 1)
    equal(h.ns.db.lastDiagnostics.total, 2)
    equal(h.ns.db.lastDiagnostics.art.loadedTextures, 11)
    equal(h.ns.db.queue, queue)
    equal(#h.takes, 0)
    assert(h:said("known 1/2"))
    assert(h:said("tiles 12/12"))
    assert(h:said("still loading"))
    h.preview.needsFlightSync = true
    SlashCmdList.PREFLIGHT("debug")
    assert(h:said("synchronize known destinations"))
end)

print(string.format("%d controller integration tests passed", passed))
