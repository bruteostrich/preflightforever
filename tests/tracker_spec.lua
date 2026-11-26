local tests, passed = {}, 0
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.001,
        tostring(actual) .. " is not close to " .. tostring(expected))
end
local function test(name, callback) tests[#tests + 1] = { name, callback } end

local function harness(noHook)
    local h = { now = 0, timers = {}, timerID = 0, hooks = {},
        context = { onTaxi = false, dead = false }, factor = 1,
        db = {}, saved = 0, preview = { mapID = 1415,
            player = { instanceID = 0, worldX = 1000, worldY = 500 } } }
    local ns = {}
    h.ns = ns
    h.live = { mapID = 1415, sourceID = 10, nodes = {
        { id = 10, slot = 1, name = "Origin", state = "CURRENT" },
        { id = 20, slot = 2, name = "Destination", state = "REACHABLE", route = {
            key = "10:20", points = {
                { id = 10, x = 0.1, y = 0.2, instanceID = 0, worldX = 100, worldY = 200 },
                { id = 20, x = 0.6, y = 0.4, instanceID = 0, worldX = 1000, worldY = 500 },
            },
        } },
    } }
    GetTime = function() return h.now end
    C_Timer = { After = function(delay, callback)
        h.timerID = h.timerID + 1
        h.timers[#h.timers + 1] = { at = h.now + delay, id = h.timerID, callback = callback }
    end }
    if noHook then
        hooksecurefunc = nil
    else
        hooksecurefunc = function(name, callback)
            equal(name, "TakeTaxiNode")
            h.hooks[#h.hooks + 1] = callback
        end
    end
    ns.API = {
        Context = function() return h.context end,
        GetPreview = function() return h.preview end,
        GetFlightSpeedFactor = function() return h.factor end,
    }
    assert(loadfile("Model.lua"))("PreflightForever", ns)
    local record = ns.Model.RecordDuration
    ns.Model.RecordDuration = function(...)
        h.saved = h.saved + 1
        return record(...)
    end
    ns.Model.RecordSnapshot(h.db, h.live, 0)
    assert(loadfile("Tracker.lua"))("PreflightForever", ns)
    h.T = ns.Tracker
    h.T.Init(h.db)
    h.T.SetSnapshot(h.live)
    function h:advance(delta)
        local untilTime, callbacks = self.now + delta, 0
        while true do
            table.sort(self.timers, function(a, b)
                return a.at == b.at and a.id < b.id or a.at < b.at
            end)
            local timer = self.timers[1]
            if not timer or timer.at > untilTime + 0.0000001 then break end
            table.remove(self.timers, 1)
            self.now = timer.at
            callbacks = callbacks + 1
            assert(callbacks < 40000, "unbounded timer loop")
            timer.callback()
        end
        self.now = untilTime
    end
    function h:take(slot)
        for _, hook in ipairs(self.hooks) do hook(slot or 2) end
    end
    function h:duration()
        return self.ns.Model.GetRoute(self.db, 1415, 10, 20).duration
    end
    function h:fly(seconds)
        self.context.onTaxi = true
        self:advance(0.2)
        self:advance(seconds - 0.2)
        self.context.onTaxi = false
        self:advance(0.2)
    end
    return h
end

test("native flight is measured only after confirmed takeoff and endpoint landing", function()
    local h = harness()
    h:take()
    equal(h:duration(), nil)
    h:fly(10)
    near(h:duration(), 10)
    equal(h.saved, 1)
    h:advance(1)
    equal(h.saved, 1)
end)

test("explicit departure works without a secure hook", function()
    local h = harness(true)
    equal(#h.hooks, 0)
    equal(h.T.BeforeTake(h.live, 2), true)
    h:fly(5)
    near(h:duration(), 5)
end)

test("own pre-call and native posthook share one measurement", function()
    local h = harness()
    h.T.BeforeTake(h.live, 2)
    h:take()
    equal(#h.timers, 1)
    h:fly(5)
    equal(h.saved, 1)
end)

test("map closure immediately before native posthook keeps that flight snapshot", function()
    local h = harness()
    h.T.CloseInteraction()
    h:take()
    h:fly(5)
    near(h:duration(), 5)
end)

test("closed interaction expires and cannot start a new native measurement", function()
    local h = harness()
    h.T.CloseInteraction()
    h:advance(0.6)
    h:take()
    h:fly(5)
    equal(h.saved, 0)
end)

test("rejected requests and never-started flights do not teach timings", function()
    local h = harness()
    h.T.BeforeTake(h.live, 2)
    h.T.CancelPending()
    h:fly(5)
    equal(h.saved, 0)
    h.T.BeforeTake(h.live, 2)
    h:advance(3.5)
    h:fly(5)
    equal(h.saved, 0)
end)

test("early landing at another flight point is ignored", function()
    local h = harness()
    h:take()
    h.preview.player.worldX = 400
    h:fly(5)
    equal(h.saved, 0)
end)

test("landing must use the same canonical map and world instance", function()
    local h = harness()
    h:take()
    h.preview.mapID = 1414
    h:fly(5)
    equal(h.saved, 0)
    h = harness()
    h:take()
    h.preview.player.instanceID = 1
    h:fly(5)
    equal(h.saved, 0)
end)

test("landing tolerance accepts the NPC vicinity but rejects farther positions", function()
    local h = harness()
    h:take()
    h.preview.player.worldX = 1175
    h:fly(5)
    near(h:duration(), 5)
    h = harness()
    h:take()
    h.preview.player.worldX = 1176
    h:fly(5)
    equal(h.saved, 0)
end)

test("unknown taxi status and death never establish a completed flight", function()
    local h = harness()
    h:take()
    h.context.onTaxi = nil
    h:advance(0.2)
    h:fly(5)
    equal(h.saved, 0)
    h = harness()
    h:take()
    h.context.dead = true
    h:fly(5)
    equal(h.saved, 0)
end)

test("a world transition invalidates a pending or active measurement", function()
    local h = harness()
    h:take()
    h.context.onTaxi = true
    h:advance(1)
    h.T.Reset()
    h.context.onTaxi = false
    h:advance(1)
    equal(h.saved, 0)
    h:take()
    equal(#h.timers, 0)
end)

test("speed is normalized and a changing speed invalidates the measurement", function()
    local h = harness()
    h.factor = 1.2
    h:take()
    h:fly(10)
    near(h:duration(), 12)
    h = harness()
    h:take()
    h.context.onTaxi = true
    h:advance(1)
    h.factor = 1.2
    h:advance(1)
    h.context.onTaxi = false
    h:advance(0.2)
    equal(h.saved, 0)
end)

test("route cache changes prevent recording a duration against different hops", function()
    local h = harness()
    h:take()
    h.db.maps[1415].origins[10].routes[20].key = "10:30:20"
    h:fly(5)
    equal(h.db.maps[1415].origins[10].routes[20].duration, nil)
end)

test("two-hour limit terminates measurements without saving", function()
    local h = harness()
    h:take()
    h.context.onTaxi = true
    h:advance(7201)
    h.context.onTaxi = false
    h:advance(0.2)
    equal(h.saved, 0)
    equal(#h.timers, 0)
end)

test("bad slots, missing route geography, and special flights are ignored", function()
    local h = harness()
    equal(h.T.BeforeTake(h.live, 99), false)
    h.live.nodes[2].special = true
    equal(h.T.BeforeTake(h.live, 2), false)
    h.live.nodes[2].special = false
    h.live.nodes[2].route.points[2].worldX = nil
    equal(h.T.BeforeTake(h.live, 2), false)
    equal(#h.timers, 0)
end)

test("initialization installs a secure hook only once", function()
    local h = harness()
    h.T.Init(h.db)
    equal(#h.hooks, 1)
end)

test("countdown starts at takeoff from this route's recorded time and ends on landing", function()
    local h = harness()
    h:take()
    h:fly(100)
    near(h:duration(), 100)
    h.factor = 2
    h:take()
    equal(h.T.Remaining(), nil)
    h.context.onTaxi = true
    h:advance(0.2)
    near(h.T.Remaining(), 50)
    h:advance(20)
    near(h.T.Remaining(), 30)
    h:advance(40)
    equal(h.T.Remaining(), 0)
    h.context.onTaxi = false
    h:advance(0.2)
    equal(h.T.Remaining(), nil)
end)

test("countdown falls back to the InFlight estimate and is absent without any time", function()
    local h = harness()
    h.ns.API.Faction = function() return 1 end
    h.estimate = 90
    h.ns.Timings = { Lookup = function(faction, mapID, sourceID, destinationID, route)
        h.lookup = { faction, mapID, sourceID, destinationID, route.key }
        return h.estimate
    end }
    h:take()
    h.context.onTaxi = true
    h:advance(0.2)
    near(h.T.Remaining(), 90)
    equal(table.concat(h.lookup, ","), "1,1415,10,20,10:20")
    h.context.onTaxi = false
    h:advance(0.2)
    equal(h.T.Remaining(), nil)
    h.estimate = nil
    h:take()
    h.context.onTaxi = true
    h:advance(0.2)
    equal(h.T.Remaining(), nil)
end)

for _, entry in ipairs(tests) do
    local ok, reason = pcall(entry[2])
    assert(ok, entry[1] .. ": " .. tostring(reason))
    passed = passed + 1
end
print("Tracker checks passed: " .. passed)
