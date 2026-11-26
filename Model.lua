local _, ns = ...
local Model = {}
ns.Model = Model

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function identifier(value)
    return finite(value) and value > 0 and value == math.floor(value)
end

local function timestamp(value)
    return finite(value) and value >= 0 and value or 0
end

local function nodeName(node)
    if type(node.name) == "string" and node.name ~= "" then
        return node.name
    end
    return "Flight point #" .. tostring(node.id)
end

local function importedKnowledge(entry)
    return type(entry) == "table" and entry.source == "ForeverDungeonJournal"
        and entry.schema == 2 and type(entry.name) == "string" and entry.name ~= ""
end

-- Older saves kept native observations inside each origin's route snapshot.
-- Rebuild effective knowledge from proofs, never from the old mixed cache:
-- 0.2.2 could fill that cache with incorrect remote "known" flags.
function Model.InitializeKnowledge(db)
    if type(db) ~= "table" then return false end
    db.maps = type(db.maps) == "table" and db.maps or {}
    db.learned = {}
    db.observed = type(db.observed) == "table" and db.observed or {}
    local imports = type(db.importedKnown) == "table" and db.importedKnown or {}
    db.importedKnown = {}
    for id, entry in pairs(imports) do
        if identifier(id) and importedKnowledge(entry) then
            db.importedKnown[id] = { source = entry.source, schema = entry.schema, name = entry.name }
            db.learned[id] = true
        end
    end
    local function recover(id)
        if identifier(id) and type(db.observed[id]) ~= "boolean" then
            db.observed[id] = true
        end
    end
    for mapID, map in pairs(db.maps) do
        if identifier(mapID) and type(map) == "table" and type(map.origins) == "table" then
            for sourceID, origin in pairs(map.origins) do
                if identifier(sourceID) and type(origin) == "table" and type(origin.reachable) == "table" then
                    recover(sourceID)
                    for destinationID, reachable in pairs(origin.reachable) do
                        if reachable == true then recover(destinationID) end
                    end
                end
            end
        end
    end
    -- Reconcile both directions before a saved queue is restored. In
    -- particular, an explicit false must survive older positive snapshots.
    for id, known in pairs(db.observed) do
        if identifier(id) and type(known) == "boolean" then db.learned[id] = known end
    end
    return true
end

-- Compare world-space distances. Normalized map positions are not comparable
-- across maps, and even one map can have differently scaled horizontal axes.
-- Undiscovered points count: talking to that flight master discovers it, and
-- the flight can leave from there on the same visit.
function Model.FindNearest(nodes, player, faction)
    if type(nodes) ~= "table" or type(player) ~= "table"
        or not finite(player.instanceID) or not finite(player.worldX)
        or not finite(player.worldY) then
        return nil
    end

    local nearest, nearestSquared
    for _, node in ipairs(nodes) do
        if type(node) == "table" and identifier(node.id) and not node.transition
            and (node.faction == nil or node.faction == 0 or node.faction == faction)
            and node.instanceID == player.instanceID
            and finite(node.worldX) and finite(node.worldY) then
            local dx = node.worldX - player.worldX
            local dy = node.worldY - player.worldY
            local distanceSquared = dx * dx + dy * dy
            if finite(distanceSquared) and (nearestSquared == nil
                or distanceSquared < nearestSquared
                or (distanceSquared == nearestSquared and node.id < nearest.id)) then
                nearest, nearestSquared = node, distanceSquared
            end
        end
    end

    if nearest then
        return nearest, math.sqrt(nearestSquared)
    end
end

-- The adapter resolves verified discovery from native observations/imports.
-- Destinations must be known; the departure may be undiscovered, since it is
-- learned on arrival. Departure is checked live at the flight master.
function Model.CanPlan(source, destination)
    if type(source) ~= "table" or not identifier(source.id) then
        return false, "No departure flight master is available here."
    end
    if type(destination) ~= "table" or not identifier(destination.id)
        or destination.learned ~= true or destination.locked then
        return false, "Discover that flight point first."
    end
    if source.id == destination.id then
        return false, "Choose a destination different from the departure flight master."
    end
    if source.transition or destination.transition then
        return false, "Map transitions cannot be queued as flights."
    end
    return true
end

function Model.NewQueue(source, destination, mapID, now)
    if type(source) ~= "table" or not identifier(source.id) then
        return nil, "The departure flight master is not available."
    end
    if type(destination) ~= "table" or not identifier(destination.id) then
        return nil, "The destination is not available."
    end
    if not identifier(mapID) then
        return nil, "The flight map is not available."
    end
    if source.id == destination.id then
        return nil, "Choose a destination different from the departure flight master."
    end
    if source.transition or destination.transition then
        return nil, "Map transitions cannot be queued as flights."
    end

    return {
        sourceID = source.id,
        destinationID = destination.id,
        sourceName = nodeName(source),
        destinationName = nodeName(destination),
        mapID = mapID,
        createdAt = timestamp(now),
    }
end

-- Slots, reachability and prices must come from the currently open taxi map.
-- Saved slots are deliberately never used: the server may reorder them.
function Model.ResolveQueue(queue, live, context)
    if type(queue) ~= "table" then
        return nil, "No flight is queued."
    end
    if not identifier(queue.sourceID) or not identifier(queue.destinationID)
        or not identifier(queue.mapID) or queue.sourceID == queue.destinationID then
        return nil, "The queued flight is incomplete; choose a destination again."
    end
    if type(live) ~= "table" or type(live.nodes) ~= "table"
        or not identifier(live.sourceID) or not identifier(live.mapID) then
        return nil, "Waiting for flight master information."
    end
    if queue.mapID ~= live.mapID then
        return nil, "This flight master is on a different flight map."
    end
    if queue.sourceID ~= live.sourceID then
        return nil, "Visit the queued departure flight master."
    end
    if type(context) ~= "table" then
        return nil, "Waiting for your character's travel status."
    end
    if context.inCombat ~= false then
        return nil, "Cannot depart while in combat or while combat status is unavailable."
    end
    if context.onTaxi ~= false then
        return nil, "Cannot depart while already flying or while flight status is unavailable."
    end
    if context.dead ~= false then
        return nil, "Cannot depart while dead or while life status is unavailable."
    end

    local destination
    for _, node in ipairs(live.nodes) do
        if type(node) == "table" and node.id == queue.destinationID then
            if destination then
                return nil, "The destination is ambiguous on this flight map."
            end
            destination = node
        end
    end
    if not destination then
        return nil, "This flight master does not offer the queued destination."
    end
    if destination.state ~= "REACHABLE" then
        return nil, "The queued destination is not reachable from this flight master."
    end
    if destination.transition then
        return nil, "Map transitions cannot be queued as flights."
    end
    if destination.special then
        return nil, "Choose this special flight manually at the flight master."
    end
    if not identifier(destination.slot) then
        return nil, "Waiting for the destination's current flight slot."
    end
    if not finite(destination.cost) or destination.cost < 0 then
        return nil, "Waiting for the current flight fare."
    end
    if not finite(context.money) or context.money < 0 then
        return nil, "Waiting for your available money."
    end
    if destination.cost > context.money then
        return nil, "You do not have enough money for this flight."
    end
    return destination
end

local function duration(value)
    return finite(value) and value > 0 and value < 86400 and value or nil
end

local function timingKey(value, pointCount)
    if type(value) ~= "string" or #value > 2000 then return nil end
    local parts = {}
    for part in value:gmatch("[^:]+") do
        local coordinate = tonumber(part)
        if not part:match("^%d%.%d%d$") or not coordinate or coordinate < 0 or coordinate > 1 then return nil end
        parts[#parts + 1] = part
    end
    if #parts ~= pointCount * 2 or table.concat(parts, ":") ~= value then return nil end
    return value
end

local function copyRoute(route, sourceID, destinationID)
    if type(route) ~= "table" or type(route.points) ~= "table"
        or not identifier(sourceID) or not identifier(destinationID)
        or sourceID == destinationID or #route.points < 2 or #route.points > 100 then
        return nil
    end
    local result, keys, seen = { points = {} }, {}, {}
    for index, point in ipairs(route.points) do
        if type(point) ~= "table" or not identifier(point.id) or seen[point.id]
            or not finite(point.x) or not finite(point.y)
            or point.x < 0 or point.x > 1 or point.y < 0 or point.y > 1 then
            return nil
        end
        seen[point.id] = true
        keys[index] = tostring(point.id)
        local saved = { id = point.id, x = point.x, y = point.y, name = nodeName(point) }
        for _, field in ipairs({ "worldX", "worldY", "instanceID" }) do
            if finite(point[field]) then saved[field] = point[field] end
        end
        result.points[index] = saved
    end
    if #result.points ~= #route.points or result.points[1].id ~= sourceID
        or result.points[#result.points].id ~= destinationID then
        return nil
    end
    result.key = table.concat(keys, ":")
    if route.key ~= result.key then return nil end
    result.sourceID, result.destinationID = sourceID, destinationID
    if identifier(route.mapID) then result.mapID = route.mapID end
    result.timingKey = timingKey(route.timingKey, #result.points)
    result.duration = duration(route.duration)
    if result.duration and type(route.durationSource) == "string" and route.durationSource ~= "" then
        result.durationSource = route.durationSource
    end
    return result
end

local function routeOrigin(db, mapID, sourceID)
    if type(db) ~= "table" or not identifier(mapID) or not identifier(sourceID)
        or type(db.maps) ~= "table" then return nil end
    local map = db.maps[mapID]
    if type(map) ~= "table" or type(map.origins) ~= "table" then return nil end
    local origin = map.origins[sourceID]
    if type(origin) ~= "table" or type(origin.routes) ~= "table"
        or type(origin.reachable) ~= "table" then return nil end
    return origin
end

local function knowledgeKey(db)
    local ids = {}
    for id, known in pairs(type(db.learned) == "table" and db.learned or {}) do
        if identifier(id) and known == true then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for index, id in ipairs(ids) do ids[index] = tostring(id) end
    return table.concat(ids, ":")
end

-- The caller receives a copy; hover rendering must not mutate saved geometry.
function Model.GetRoute(db, mapID, sourceID, destinationID)
    local origin = routeOrigin(db, mapID, sourceID)
    if not origin or not identifier(destinationID) or origin.reachable[destinationID] ~= true
        or type(db.learned) ~= "table" or db.learned[sourceID] ~= true
        or db.learned[destinationID] ~= true then return nil end
    local route = copyRoute(origin.routes[destinationID], sourceID, destinationID)
    if route and route.mapID and route.mapID ~= mapID then return nil end
    if route then
        -- A capture remains evidence of a past route, but newly known points
        -- can change the client's chosen connections. Retain the geometry and
        -- timing while allowing the UI to identify an older network snapshot.
        local knowledgeChanged = origin.knowledgeKey ~= knowledgeKey(db)
        local buildChanged = type(db.clientBuild) == "string" and db.clientBuild ~= ""
            and origin.clientBuild ~= db.clientBuild
        route.stale = knowledgeChanged or buildChanged
        route.staleReason = buildChanged and "build" or (knowledgeChanged and "knowledge" or nil)
        route.recordedAt = timestamp(origin.seenAt)
    end
    return route
end

-- Timings are normalized to ordinary flight speed, so a speed perk does not
-- permanently contaminate the estimate seen after that perk changes.
function Model.RecordDuration(db, mapID, sourceID, destinationID, key, seconds, speedFactor)
    if not duration(seconds) or not finite(speedFactor) or speedFactor <= 0 then return false end
    local normalized = duration(seconds * speedFactor)
    if not normalized then return false end
    local route = Model.GetRoute(db, mapID, sourceID, destinationID)
    if not route or route.key ~= key then return false end
    route.duration, route.durationSource = normalized, "Recorded flight"
    local origin = routeOrigin(db, mapID, sourceID)
    origin.routes[destinationID] = copyRoute(route, sourceID, destinationID)
    return true
end

local function mergeNode(saved, node)
    saved.id = node.id
    if type(node.name) == "string" and node.name ~= "" then
        saved.name = node.name
    end
    for _, key in ipairs({ "x", "y", "worldX", "worldY", "instanceID" }) do
        if finite(node[key]) then
            saved[key] = node[key]
        end
    end
    if node.faction == 0 or node.faction == 1 or node.faction == 2 then
        saved.faction = node.faction
    end
    if type(node.transition) == "boolean" then
        saved.transition = node.transition
    end
    -- Remove transient fields if an earlier development build persisted them.
    saved.slot, saved.slotIndex, saved.cost, saved.state, saved.special = nil, nil, nil, nil, nil
end

-- This function is only called with a snapshot read at a real flight master.
-- Reachability is a per-origin observation, not a permanent promise of a route.
function Model.RecordSnapshot(db, live, now)
    if type(db) ~= "table" or type(live) ~= "table"
        or not identifier(live.mapID) or not identifier(live.sourceID)
        or type(live.nodes) ~= "table" then
        return false
    end
    db.maps = type(db.maps) == "table" and db.maps or {}
    db.learned = type(db.learned) == "table" and db.learned or {}
    db.observed = type(db.observed) == "table" and db.observed or {}
    local map = db.maps[live.mapID]
    if type(map) ~= "table" then
        map = {}
        db.maps[live.mapID] = map
    end
    map.nodes = type(map.nodes) == "table" and map.nodes or {}
    map.origins = type(map.origins) == "table" and map.origins or {}
    local previousOrigin = map.origins[live.sourceID]
    local previousRoutes = type(previousOrigin) == "table" and previousOrigin.routes
    local origin = { reachable = {}, routes = {}, seenAt = timestamp(now) }
    if type(db.clientBuild) == "string" and db.clientBuild ~= "" then origin.clientBuild = db.clientBuild end
    map.origins[live.sourceID] = origin
    for _, node in ipairs(live.nodes) do
        if type(node) == "table" and identifier(node.id) and not node.transition then
            local saved = map.nodes[node.id]
            if type(saved) ~= "table" then
                saved = {}
                map.nodes[node.id] = saved
            end
            mergeNode(saved, node)
            if node.state == "CURRENT" or node.state == "REACHABLE" then
                db.learned[node.id] = true
                db.observed[node.id] = true
            elseif node.state == "UNREACHABLE" then
                -- A false observation must be retained, not deleted: an
                -- incorrect remote positive must not resurrect this point.
                db.learned[node.id] = false
                db.observed[node.id] = false
            end
            if node.state == "REACHABLE" then
                origin.reachable[node.id] = true
                local route = copyRoute(node.route, live.sourceID, node.id)
                if route and (not route.mapID or route.mapID == live.mapID) then
                    local previous = type(previousRoutes) == "table"
                        and copyRoute(previousRoutes[node.id], live.sourceID, node.id)
                    if previous and previous.key == route.key and previous.duration then
                        route.duration, route.durationSource = previous.duration, previous.durationSource
                    end
                    origin.routes[node.id] = route
                end
            end
        end
    end
    -- Record this only after every native knowledge correction was applied.
    -- Global IDs conservatively catch new points absent from old map caches.
    origin.knowledgeKey = knowledgeKey(db)
    return true
end
