local _, ns = ...
local A = {}
ns.API = A

-- Keep client values out of arithmetic, comparisons and saved variables until
-- they have been checked. Some modern clients return secret values in combat.
local function Readable(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return nil end
    end
    return value
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return Readable(a), Readable(b), Readable(c), Readable(d)
end

local function Field(object, key)
    object = Readable(object)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return Readable(value) end
end

local function Number(value)
    value = Readable(value)
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
        return value
    end
end

local function ID(value)
    value = Number(value)
    if value and value > 0 and value == math.floor(value) then return value end
end

local function Name(value)
    value = Readable(value)
    if type(value) == "string" and value ~= "" then return value end
end

local function XY(vector)
    if not vector then return nil end
    local x, y = Call(Field(vector, "GetXY"), vector)
    x, y = Number(x), Number(y)
    if not x or not y then x, y = Number(Field(vector, "x")), Number(Field(vector, "y")) end
    return x, y
end

local function Position(vector)
    local x, y = XY(vector)
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

local function Vector(x, y)
    return Call(CreateVector2D, x, y)
end

local function World(mapID, x, y)
    if not (C_Map and mapID and x and y) then return nil end
    local vector = Vector(x, y)
    if not vector then return nil end
    local instanceID, position = Call(C_Map.GetWorldPosFromMapPos, mapID, vector)
    local wx, wy = XY(position)
    instanceID = Number(instanceID) -- Eastern Kingdoms has instance ID zero.
    if instanceID and wx and wy then return instanceID, wx, wy end
end

local function Project(mapID, instanceID, wx, wy)
    if not (C_Map and mapID and instanceID and wx and wy) then return nil end
    local vector = Vector(wx, wy)
    if not vector then return nil end
    local returnedMap, position = Call(C_Map.GetMapPosFromWorldPos, instanceID, vector, mapID)
    if returnedMap == mapID then return Position(position) end
end

local function Continent()
    if not C_Map then return nil end
    local best = ID(Call(C_Map.GetBestMapForUnit, "player"))
    local mapID, visited = best, {}
    for _ = 1, 20 do
        if not mapID or visited[mapID] then break end
        visited[mapID] = true
        local info = Call(C_Map.GetMapInfo, mapID)
        if not info then break end
        if Number(Field(info, "mapType")) == 2 then
            return mapID, Name(Field(info, "name")), best
        end
        mapID = ID(Field(info, "parentMapID"))
    end
end

local function Player(mapID, bestMapID)
    local position = C_Map and Call(C_Map.GetPlayerMapPosition, bestMapID, "player")
    local x, y = Position(position)
    local instanceID, wx, wy = World(bestMapID, x, y)
    if instanceID then
        local mx, my = Project(mapID, instanceID, wx, wy)
        return { instanceID = instanceID, worldX = wx, worldY = wy, x = mx, y = my }
    end
    -- The zone may lack a player position indoors; only use a continent
    -- position if the client actually supplies one for that same map.
    position = C_Map and Call(C_Map.GetPlayerMapPosition, mapID, "player")
    x, y = Position(position)
    instanceID, wx, wy = World(mapID, x, y)
    if instanceID then
        return { instanceID = instanceID, worldX = wx, worldY = wy, x = x, y = y }
    end
end

function A.Faction()
    local faction = Call(UnitFactionGroup, "player")
    if faction == "Horde" then return 1 end
    if faction == "Alliance" then return 2 end
end

function A.GetBuildKey()
    local version, build = Call(GetBuildInfo)
    version, build = Name(version), Name(build)
    if version and build then return version .. "." .. build end
end

local function Faction(value)
    value = Number(value)
    if value == 0 or value == 1 or value == 2 then return value end
end

local function Coordinates(node, coordinateMapID, displayMapID, position)
    local x, y = Position(position)
    local instanceID, wx, wy = World(coordinateMapID, x, y)
    node.instanceID, node.worldX, node.worldY = instanceID, wx, wy
    if coordinateMapID == displayMapID then
        node.x, node.y = x, y
    elseif instanceID then
        node.x, node.y = Project(displayMapID, instanceID, wx, wy)
    end
end

local function RemoteNodes(mapID, faction)
    local nodes, out = C_TaxiMap and Call(C_TaxiMap.GetTaxiNodesForMap, mapID), {}
    if type(nodes) ~= "table" then return out end
    for _, raw in ipairs(nodes) do
        local id, name = ID(Field(raw, "nodeID")), Name(Field(raw, "name"))
        local side = Faction(Field(raw, "faction"))
        if id and name and (side == 0 or side == faction) and side ~= nil then
            local undiscovered = Field(raw, "isUndiscovered")
            local node = { id = id, name = name, faction = side,
                transition = Field(raw, "isMapLayerTransition") == true }
            -- Only a literal readable boolean is discovery evidence. A
            -- missing/secret value must not be interpreted as discovered.
            if type(undiscovered) == "boolean" then node.remoteKnown = not undiscovered end
            Coordinates(node, mapID, mapID, Field(raw, "position"))
            if node.x and node.y then out[#out + 1] = node end
        end
    end
    return out
end

local function ImportedKnowledge(entry)
    return type(entry) == "table" and Field(entry, "source") == "ForeverDungeonJournal"
        and Field(entry, "schema") == 2 and Name(Field(entry, "name")) ~= nil
end

local function ImportKnownFlights(imports, nodes, observed)
    -- FDJ schema 2 records this character's full localized names only after
    -- a real flight master reports CURRENT or REACHABLE. Older schemas also
    -- accepted remote discovery flags, so they are deliberately not imported.
    local journal = Readable(ForeverDungeonJournalCharacterDB)
    if type(journal) ~= "table" or Field(journal, "flightPointsVersion") ~= 2 then return 0 end
    local found = Field(journal, "flightPoints")
    if type(found) ~= "table" then return 0 end
    local byName = {}
    for _, node in pairs(nodes) do
        local id, name = ID(node.id), Name(node.name)
        if id and name and not node.transition then
            local key = string.lower(name)
            -- A name shared by two points cannot identify a stable taxi ID.
            if byName[key] == nil then byName[key] = id else byName[key] = false end
        end
    end
    local imported = 0
    for key, id in pairs(byName) do
        if id and type(observed[id]) ~= "boolean" and not ImportedKnowledge(imports[id])
            and Field(found, key) == true then
            imports[id] = { source = "ForeverDungeonJournal", schema = 2, name = nodes[id].name }
            imported = imported + 1
        end
    end
    return imported
end

function A.GetPreview(db)
    local mapID, mapName, best = Continent()
    if not mapID then return nil, "Your continent is unavailable here. Try outdoors." end
    local faction = A.Faction()
    if not faction then return nil, "Your faction is not available yet." end
    local player = Player(mapID, best)
    if not player then return nil, "Your position is unavailable here. Try outdoors." end
    db = type(db) == "table" and db or {}
    local byID, out = {}, {}
    local maps = type(db.maps) == "table" and db.maps or {}
    local cached = type(maps[mapID]) == "table" and maps[mapID].nodes
    if type(cached) == "table" then
        for _, old in pairs(cached) do
            if type(old) == "table" and ID(old.id) and Name(old.name)
                and (old.faction == nil or old.faction == 0 or old.faction == faction) then
                local node = {}
                for _, key in ipairs({ "id", "name", "x", "y", "instanceID", "worldX", "worldY", "faction", "transition" }) do
                    node[key] = old[key]
                end
                byID[node.id] = node
            end
        end
    end
    for _, node in ipairs(RemoteNodes(mapID, faction)) do
        local confirmed = byID[node.id]
        if confirmed then
            -- A real flight-master snapshot is stronger geography evidence
            -- than the remote map list, which has differed between builds.
            local x, y = Number(confirmed.x), Number(confirmed.y)
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                node.x, node.y = x, y
            end
            local instanceID = Number(confirmed.instanceID)
            local wx, wy = Number(confirmed.worldX), Number(confirmed.worldY)
            if instanceID and wx and wy then
                node.instanceID, node.worldX, node.worldY = instanceID, wx, wy
            end
        end
        byID[node.id] = node
    end
    local learned = type(db.learned) == "table" and db.learned or {}
    db.learned = learned
    local observed = type(db.observed) == "table" and db.observed or {}
    local imports = type(db.importedKnown) == "table" and db.importedKnown or {}
    db.importedKnown = imports
    local importedKnownCount = ImportKnownFlights(imports, byID, observed)
    local verifiedKnownCount, unverifiedCount, remoteKnownCount = 0, 0, 0
    for id, node in pairs(byID) do
        local known = observed[id]
        if type(known) == "boolean" then
            node.knowledgeSource = "flight-master"
        elseif ImportedKnowledge(imports[id]) then
            known, node.knowledgeSource = true, "dungeon-journal"
        else
            -- Forever can report every remote point as discovered. Keep
            -- those flags for diagnostics, but never turn them into proof.
            -- Missing evidence is not a permanent negative observation.
            known = nil
            node.knowledgeSource = node.remoteKnown == false and "remote-unknown" or "unverified"
        end
        if node.remoteKnown == true and not node.transition then remoteKnownCount = remoteKnownCount + 1 end
        if type(known) == "boolean" and not node.transition then
            learned[id] = known
        else
            learned[id] = nil
        end
        node.learned = known == true and not node.transition
        node.locked = not node.learned
        node.unverified = known == nil and node.remoteKnown ~= false and not node.transition
        if node.learned then verifiedKnownCount = verifiedKnownCount + 1 end
        if node.unverified then unverifiedCount = unverifiedCount + 1 end
        out[#out + 1] = node
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return { mapID = mapID, mapName = mapName or "Flight map", nodes = out, player = player, faction = faction,
        importedKnownCount = importedKnownCount, verifiedKnownCount = verifiedKnownCount,
        unverifiedCount = unverifiedCount, remoteKnownCount = remoteKnownCount,
        needsFlightSync = unverifiedCount > 0,
        warning = unverifiedCount > 0 and "Remote discovery flags are unreliable on Forever. Visit a flight master to verify the remaining points." or nil }
end

local function State(slot, rawState)
    local kind = Call(TaxiNodeGetType, slot)
    if kind == "CURRENT" or kind == "REACHABLE" then return kind end
    if kind == "NONE" or kind == "DISTANT" or kind == "UNREACHABLE" then return "UNREACHABLE" end
    if rawState == 0 then return "CURRENT" end
    if rawState == 1 then return "REACHABLE" end
    if rawState == 2 then return "UNREACHABLE" end
end

local function SlotDetails(node, slot, rawState)
    local liveName = Name(Call(TaxiNodeName, slot))
    if liveName and liveName ~= node.name then return false end
    node.slot, node.slotIndex = slot, slot
    node.rawState, node.state = rawState, State(slot, rawState)
    node.reachable = node.state == "REACHABLE"
    node.learned = node.state == "CURRENT" or node.reachable
    node.cost = Number(Call(TaxiNodeCost, slot))
    return node.state ~= nil
end

local function LegacyNodes(mapID, taxiMapID, faction)
    local count = ID(Call(NumTaxiNodes))
    if not count or count > 1000 then return {} end
    local candidates, out, used = RemoteNodes(mapID, faction), {}, {}
    for slot = 1, count do
        local name = Name(Call(TaxiNodeName, slot))
        local x, y = Call(TaxiNodePosition, slot)
        x, y = Number(x), Number(y)
        local instanceID, wx, wy = World(taxiMapID, x, y)
        local mx, my = Project(mapID, instanceID, wx, wy)
        local match, matches = nil, 0
        if name and mx and my then
            for _, candidate in ipairs(candidates) do
                if candidate.name == name and candidate.x and candidate.y
                    and math.abs(candidate.x - mx) < 0.005 and math.abs(candidate.y - my) < 0.005 then
                    match, matches = candidate, matches + 1
                end
            end
        end
        -- Never use a session slot or a name alone as a persistent node ID.
        if matches == 1 and not used[match.id] and SlotDetails(match, slot) then
            used[match.id] = true
            out[#out + 1] = match
        end
    end
    return out
end

function A.GetFlightSpeedFactor()
    -- Forever's Frequent Flier perk, also used by the installed flight-time
    -- addon, makes normal taxi travel 20% faster.
    return Call(IsPlayerSpell, 1225490) == true and 1.2 or 1
end

local function CaptureRoutes(nodes, sourceID, mapID)
    if type(GetNumRoutes) ~= "function" or type(TaxiGetNodeSlot) ~= "function" then return end
    local bySlot = {}
    for _, node in ipairs(nodes) do
        if bySlot[node.slot] then return end
        bySlot[node.slot] = node
    end
    local function Point(node)
        if not node or node.transition then return nil end
        local x, y = Number(node.x), Number(node.y)
        if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
        return { id = node.id, name = node.name, x = x, y = y,
            instanceID = node.instanceID, worldX = node.worldX, worldY = node.worldY }
    end
    local function TimingKey(slot)
        local x, y = Call(TaxiNodePosition, slot)
        x, y = Number(x), Number(y)
        if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            return string.format("%.2f:%.2f", x, y)
        end
    end
    for _, destination in ipairs(nodes) do
        if destination.state == "REACHABLE" and not destination.transition and not destination.special then
            local count = ID(Call(GetNumRoutes, destination.slot))
            if count and count <= 1000 then
                local points, ids, timingKeys, previousID, valid = {}, {}, {}, nil, true
                local completeTimingKey = true
                for hop = 1, count do
                    local sourceSlot = ID(Call(TaxiGetNodeSlot, destination.slot, hop, true))
                    local destinationSlot = ID(Call(TaxiGetNodeSlot, destination.slot, hop, false))
                    local source, target = Point(bySlot[sourceSlot]), Point(bySlot[destinationSlot])
                    if not source or not target or source.id == target.id
                        or (previousID and previousID ~= source.id)
                        or (not previousID and source.id ~= sourceID) then
                        valid = false
                        break
                    end
                    if not previousID then
                        points[1], ids[1] = source, tostring(source.id)
                        local timingKey = TimingKey(sourceSlot)
                        if timingKey then timingKeys[1] = timingKey else completeTimingKey = false end
                    end
                    points[#points + 1], ids[#ids + 1] = target, tostring(target.id)
                    local timingKey = TimingKey(destinationSlot)
                    if timingKey then timingKeys[#timingKeys + 1] = timingKey else completeTimingKey = false end
                    previousID = target.id
                end
                if valid and previousID == destination.id then
                    destination.route = { mapID = mapID, sourceID = sourceID, destinationID = destination.id,
                        points = points, key = table.concat(ids, ":"), speedFactor = A.GetFlightSpeedFactor() }
                    if completeTimingKey then destination.route.timingKey = table.concat(timingKeys, ":") end
                end
            end
        end
    end
end

function A.GetLive()
    local mapID, mapName = Continent()
    if not mapID then return nil, "The flight master's continent is unavailable." end
    local taxiMapID = ID(Call(GetTaxiMapID))
    if not taxiMapID then return nil, "The flight master's map is not ready." end
    local nodes, sourceID, seen = {}, nil, {}
    local rawNodes = C_TaxiMap and Call(C_TaxiMap.GetAllTaxiNodes, taxiMapID)
    if type(rawNodes) == "table" then
        for _, raw in ipairs(rawNodes) do
            local id, name = ID(Field(raw, "nodeID")), Name(Field(raw, "name"))
            local slot, rawState = ID(Field(raw, "slotIndex")), Number(Field(raw, "state"))
            if id then
                if seen[id] then return nil, "The flight map reported an ambiguous destination." end
                seen[id] = true
            end
            if id and name and slot then
                local specialCost = Name(Field(raw, "specialIconCostString"))
                local node = { id = id, name = name, faction = Faction(Field(raw, "faction")),
                    transition = Field(raw, "isMapLayerTransition") == true,
                    special = Field(raw, "useSpecialIcon") == true or specialCost ~= nil,
                    specialCost = specialCost }
                Coordinates(node, taxiMapID, mapID, Field(raw, "position"))
                if SlotDetails(node, slot, rawState) then
                    nodes[#nodes + 1] = node
                end
            end
        end
    end
    if #nodes == 0 then nodes = LegacyNodes(mapID, taxiMapID, A.Faction()) end
    for _, node in ipairs(nodes) do
        if node.state == "CURRENT" and not node.transition then
            if sourceID and sourceID ~= node.id then return nil, "The flight map reported multiple departure points." end
            sourceID = node.id
        end
    end
    if not sourceID then return nil, "The flight master's departure point is not ready." end
    CaptureRoutes(nodes, sourceID, mapID)
    return { mapID = mapID, mapName = mapName, taxiMapID = taxiMapID, sourceID = sourceID, nodes = nodes }
end

function A.Context()
    local function Flag(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, ...)
        if not ok then return nil end
        if type(issecretvalue) == "function" then
            local checked, secret = pcall(issecretvalue, value)
            if not checked or secret then return nil end
        end
        -- Older game APIs use nil for a false unit flag.
        return value and true or false
    end
    return { inCombat = Flag(InCombatLockdown), onTaxi = Flag(UnitOnTaxi, "player"),
        dead = Flag(UnitIsDeadOrGhost, "player"), money = Number(Call(GetMoney)) }
end

function A.OpenTaxiGossip()
    if not C_GossipInfo or type(C_GossipInfo.SelectOption) ~= "function" then return false end
    if Call(IsShiftKeyDown) then return false end
    local context = A.Context()
    if context.inCombat ~= false or context.onTaxi ~= false or context.dead ~= false then return false end
    local options = Call(C_GossipInfo.GetOptions)
    if type(options) ~= "table" then return false end
    -- GossipOptionUIInfo.icon is a file ID, NOT Enum.GossipNpcOption.
    -- 132057 is Interface\\GossipFrame\\TaxiGossipIcon. Match the service
    -- icon, available status, and a single concrete option ID only.
    local candidate
    for _, option in ipairs(options) do
        local icon = Number(Field(option, "icon"))
        local override = Number(Field(option, "overrideIconID"))
        if icon == 132057 and (not override or override == 132057) then
            if candidate then return false end
            local id = ID(Field(option, "gossipOptionID"))
            if not id or Number(Field(option, "status")) ~= 0 then return false end
            candidate = id
        end
    end
    if not candidate then return false end
    return pcall(C_GossipInfo.SelectOption, candidate)
end

function A.Take(node)
    if type(node) ~= "table" or not ID(node.slot) or node.state ~= "REACHABLE" then
        return false, "That destination is not available from this flight master."
    end
    if node.transition or node.special or node.specialCost then
        return false, "Choose this special flight directly on the flight master's map."
    end
    local context = A.Context()
    if context.inCombat ~= false or context.onTaxi ~= false or context.dead ~= false then return false, "You cannot start this flight right now." end
    if State(node.slot, node.rawState) ~= "REACHABLE" then return false, "The flight map changed; select your destination again." end
    local name = Name(Call(TaxiNodeName, node.slot))
    if name and name ~= node.name then return false, "The flight map changed; select your destination again." end
    local cost = Number(Call(TaxiNodeCost, node.slot))
    if not cost or cost < 0 or not context.money then return false, "The flight cost is unavailable." end
    if cost > context.money then return false, "You do not have enough money for this flight." end
    if type(TakeTaxiNode) ~= "function" then return false, "This client does not expose flight selection." end
    local ok = pcall(TakeTaxiNode, node.slot)
    if not ok then return false, "The client blocked flight selection. Choose the destination on the flight map." end
    -- An accepted API call is only a request. The controller waits for
    -- UnitOnTaxi before consuming the queue.
    return true
end
