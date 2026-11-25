local _, ns = ...
local Routes = {}
ns.Routes = Routes

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function id(value)
    return finite(value) and value > 0 and value == math.floor(value)
end

local function point(node, faction, instanceID)
    if type(node) ~= "table" or not id(node.id) or node.learned ~= true
        or node.locked or node.transition or node.special then return nil end
    if node.faction ~= nil and node.faction ~= 0 and node.faction ~= faction then return nil end
    if not finite(node.x) or not finite(node.y)
        or node.x < 0 or node.x > 1 or node.y < 0 or node.y > 1 then return nil end
    if instanceID ~= nil and node.instanceID ~= instanceID then return nil end
    return { id = node.id, name = node.name, x = node.x, y = node.y,
        instanceID = node.instanceID, worldX = node.worldX, worldY = node.worldY }
end

-- This is a preview, not a claim about the server's chosen route. The
-- character's known points restrict a directed graph of real flight links.
-- Prefer a direct connection before searching: client observations in
-- ClassicAPI and TrinityCore agree that a single destination selection
-- takes that flight even when a multi-hop journey would be shorter.
-- Forever's exact multi-hop weights are not exposed to addons, so those
-- remain shortest-flown-distance estimates, not a replica of its solver.
-- A later native snapshot takes precedence at the call site. Estimated
-- routes are never saved as observations or used to select a taxi slot.
function Routes.Estimate(preview, sourceID, destinationID)
    if type(preview) ~= "table" or not id(preview.mapID) or type(preview.nodes) ~= "table"
        or not id(sourceID) or not id(destinationID) or sourceID == destinationID
        or type(ns.RouteEdges) ~= "table" then return nil end
    local instanceID = type(preview.player) == "table" and preview.player.instanceID
    if not finite(instanceID) then instanceID = nil end
    local points, seen = {}, {}
    for _, node in ipairs(preview.nodes) do
        if type(node) == "table" and id(node.id) then
            -- Even one duplicate ID makes its identity ambiguous.
            if seen[node.id] then
                points[node.id] = nil
            else
                points[node.id] = point(node, preview.faction, instanceID)
                seen[node.id] = true
            end
        end
    end
    if not points[sourceID] or not points[destinationID] then return nil end
    local graph = {}
    for i = 1, #ns.RouteEdges - 2, 3 do
        local from, to, distance = ns.RouteEdges[i], ns.RouteEdges[i + 1], ns.RouteEdges[i + 2]
        if id(from) and id(to) and from ~= to and points[from] and points[to]
            and finite(distance) and distance > 0 then
            graph[from] = graph[from] or {}
            if not graph[from][to] or distance < graph[from][to] then graph[from][to] = distance end
        end
    end
    local direct = graph[sourceID] and graph[sourceID][destinationID]
    local distances, previous, visited = { [sourceID] = 0 }, {}, {}
    if direct then
        distances[destinationID], previous[destinationID] = direct, sourceID
    end
    while not direct do
        local current, best
        for candidate, distance in pairs(distances) do
            if not visited[candidate] and (not best or distance < best
                or (distance == best and candidate < current)) then
                current, best = candidate, distance
            end
        end
        if not current then return nil end
        if current == destinationID then break end
        visited[current] = true
        for nextID, length in pairs(graph[current] or {}) do
            local total = best + length
            if not visited[nextID] and finite(total)
                and (not distances[nextID] or total < distances[nextID]
                    or (total == distances[nextID] and current < previous[nextID])) then
                distances[nextID], previous[nextID] = total, current
            end
        end
    end
    local ordered, ids, cursor = {}, {}, destinationID
    while cursor do
        table.insert(ordered, 1, points[cursor])
        table.insert(ids, 1, tostring(cursor))
        if cursor == sourceID then break end
        cursor = previous[cursor]
    end
    if #ordered < 2 or ordered[1].id ~= sourceID then return nil end
    return { mapID = preview.mapID, sourceID = sourceID, destinationID = destinationID,
        points = ordered, key = table.concat(ids, ":"), estimated = true,
        direct = direct ~= nil, dataBuild = ns.RouteDataBuild,
        routeSource = "Estimated route from bundled flight links", distance = distances[destinationID] }
end

-- Compare predictions to the actual stop chains supplied at a flight
-- master. This is diagnostic evidence only; it never replaces native hops.
function Routes.Compare(preview, live)
    if type(preview) ~= "table" or type(live) ~= "table" or preview.mapID ~= live.mapID
        or not id(live.sourceID) or type(live.nodes) ~= "table" then return nil end
    local report = { sourceID = live.sourceID, mapID = live.mapID, dataBuild = ns.RouteDataBuild,
        matched = 0, different = 0, unavailable = 0, compared = 0, differences = {} }
    for _, node in ipairs(live.nodes) do
        if type(node) == "table" and node.state == "REACHABLE" and type(node.route) == "table"
            and type(node.route.key) == "string" then
            local estimated = Routes.Estimate(preview, live.sourceID, node.id)
            report.compared = report.compared + 1
            if not estimated then
                report.unavailable = report.unavailable + 1
            elseif estimated.key == node.route.key then
                report.matched = report.matched + 1
            else
                report.different = report.different + 1
            end
            if not estimated or estimated.key ~= node.route.key then
                report.differences[node.id] = { native = node.route.key, estimated = estimated and estimated.key or nil }
            end
        end
    end
    return report
end
