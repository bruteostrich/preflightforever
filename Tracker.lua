local _, ns = ...
local T = {}
ns.Tracker = T
local A, M = ns.API, ns.Model
local db, snapshot, closedAt, interactionOpen, active
local generation, hookInstalled = 0, false

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function clock()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    if ok and finite(value) then return value end
end

local function speed()
    if type(A.GetFlightSpeedFactor) ~= "function" then return nil end
    local ok, value = pcall(A.GetFlightSpeedFactor)
    if ok and finite(value) and value > 0 then return value end
end

function T.CancelPending()
    generation = generation + 1
    active = nil
end

function T.Reset()
    T.CancelPending()
    snapshot, closedAt, interactionOpen = nil, nil, false
end

local function arrived(flight)
    local ok, preview = pcall(A.GetPreview, db)
    if not ok or type(preview) ~= "table" or preview.mapID ~= flight.mapID then return false end
    local player = preview.player
    if type(player) ~= "table" or player.instanceID ~= flight.instanceID
        or not finite(player.worldX) or not finite(player.worldY) then return false end
    local dx, dy = player.worldX - flight.worldX, player.worldY - flight.worldY
    return dx * dx + dy * dy <= 175 * 175
end

local function poll(token)
    local flight = active
    if not flight or token ~= generation then return end
    local now = clock()
    if not now or now < flight.requestedAt or now - flight.requestedAt > 7200
        or speed() ~= flight.speedFactor then
        T.CancelPending()
        return
    end
    local ok, context = pcall(A.Context)
    if not ok or type(context) ~= "table" or type(context.onTaxi) ~= "boolean" then
        -- Unknown status cannot establish either takeoff or landing.
        T.CancelPending()
        return
    end
    if context.onTaxi then
        flight.startedAt = flight.startedAt or now
    elseif flight.startedAt then
        local seconds = now - flight.startedAt
        T.CancelPending()
        if context.dead == false and seconds >= 1 and seconds <= 7200 and arrived(flight) then
            M.RecordDuration(db, flight.mapID, flight.sourceID, flight.destinationID,
                flight.key, seconds, flight.speedFactor)
        end
        return
    elseif now - flight.requestedAt >= 3 then
        T.CancelPending()
        return
    end
    C_Timer.After(0.2, function() poll(token) end)
end

-- Expected time in the air at the current speed, chosen like the planner's
-- preview: this exact route's recorded time first, then the InFlight estimate.
local function expectedSeconds(live, node, route, factor)
    local recorded = M.GetRoute(db, live.mapID, live.sourceID, node.id)
    local seconds = recorded and recorded.key == route.key and recorded.duration or nil
    if not seconds and type(ns.Timings) == "table" and type(ns.Timings.Lookup) == "function" then
        local faction = type(A.Faction) == "function" and A.Faction() or nil
        local ok, value = pcall(ns.Timings.Lookup, faction, live.mapID, live.sourceID, node.id, route)
        if ok then seconds = value end
    end
    if finite(seconds) and seconds > 0 then return seconds / factor end
end

-- Seconds left on the current flight, or nil when no timed flight is in the
-- air: not yet airborne, already landed, or no time to count down from.
function T.Remaining()
    local flight, now = active, clock()
    if not flight or not flight.expected or not flight.startedAt or not now then return nil end
    return math.max(0, flight.expected - (now - flight.startedAt))
end

function T.BeforeTake(live, slot)
    if type(db) ~= "table" or type(live) ~= "table" or type(live.nodes) ~= "table"
        or not finite(slot) or slot < 1 or slot ~= math.floor(slot)
        or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false end
    local now, factor = clock(), speed()
    if not now or not factor then return false end
    local node
    for _, candidate in ipairs(live.nodes) do
        if candidate.slot == slot then
            if node then return false end
            node = candidate
        end
    end
    if not node or node.state ~= "REACHABLE" or node.special or node.transition then return false end
    local route = node.route
    if type(route) ~= "table" or type(route.key) ~= "string" or type(route.points) ~= "table" then return false end
    local first, last = route.points[1], route.points[#route.points]
    if type(first) ~= "table" or type(last) ~= "table" or first.id ~= live.sourceID or last.id ~= node.id
        or not finite(last.instanceID) or not finite(last.worldX) or not finite(last.worldY) then return false end
    if active and active.mapID == live.mapID and active.sourceID == live.sourceID
        and active.destinationID == node.id and active.key == route.key then
        -- The explicit call before Preflight's departure and the secure
        -- posthook refer to the same attempt; keep one timer and start time.
        return true
    end
    T.CancelPending()
    active = { mapID = live.mapID, sourceID = live.sourceID, destinationID = node.id,
        key = route.key, requestedAt = now, speedFactor = factor,
        instanceID = last.instanceID, worldX = last.worldX, worldY = last.worldY,
        expected = expectedSeconds(live, node, route, factor) }
    local token = generation
    C_Timer.After(0.2, function() poll(token) end)
    return true
end

function T.SetSnapshot(live)
    snapshot = type(live) == "table" and live or nil
    closedAt, interactionOpen = nil, snapshot ~= nil
end

function T.CloseInteraction()
    closedAt, interactionOpen = clock(), false
end

function T.Init(database)
    db = database
    T.Reset()
    if not hookInstalled and type(hooksecurefunc) == "function" then
        local ok = pcall(hooksecurefunc, "TakeTaxiNode", function(slot)
            local now = clock()
            -- Native TakeTaxiNode can synchronously close the map before
            -- its secure posthook runs. Keep that snapshot for this call.
            local justClosed = now and closedAt and now >= closedAt and now - closedAt <= 0.5
            if snapshot and (interactionOpen or justClosed) then T.BeforeTake(snapshot, slot) end
        end)
        hookInstalled = ok
    end
end
