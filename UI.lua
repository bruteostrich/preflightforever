local _, ns = ...
local UI = {}
ns.UI = UI
local window, launcher, canvas, list, scroll, search, originText, queueText, statusText
local autoCheck, depart, cancel, mapTitle, emptyText, playerPin, playerArrow, emptyListText, mapBackground
local details
local pins, rows, tiles, routeLines = {}, {}, {}, {}
local hoveredWidget, hoveredID, hasMapArt
local mapWaiting = false
local mapDiagnostics = { mode = "not-opened" }
local mapWidth, mapHeight = 628, 420
local gold = { 1, 0.78, 0.34 }
local green = { 0.35, 0.9, 0.58 }
local grey = { 0.68, 0.71, 0.76 }
local red = { 1, 0.18, 0.16 }
local defaultStatus = "Gold: departure   Green: known   Red: unknown or unverified"

local function label(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(STANDARD_TEXT_FONT, size)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(color or { 0.9, 0.91, 0.93 }))
    return text
end

local function backdrop(frame, background, border)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(unpack(background or { 0.045, 0.055, 0.075, 0.97 }))
    frame:SetBackdropBorderColor(unpack(border or { 0.33, 0.29, 0.2, 1 }))
end

local function button(parent, text, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 25)
    b:SetText(text)
    b:SetScript("OnClick", action)
    return b
end

local function restore(frame, saved, fallbackX, fallbackY)
    frame:ClearAllPoints()
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", fallbackX or 0, fallbackY or 0)
    end
end

local function savePosition(frame, key)
    -- GetCenter is in this frame's scale, while UIParent's center is in its own.
    local x, y = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not x or not px then return end
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    ns.db[key] = { x = x - px * ratio, y = y - py * ratio }
end

local function originNote(node)
    if node.learned == true and not node.locked then return "" end
    return node.unverified and " (unverified)" or " (undiscovered)"
end

local function nodeStatus(node)
    if ns.origin and node.id == ns.origin.id then return "Closest flight master" .. originNote(node), gold end
    if node.unverified then return "Unverified flight point", red end
    if node.learned ~= true or node.locked then return "Unknown flight point", red end
    local map = ns.preview and ns.db.maps[ns.preview.mapID]
    local origins = type(map) == "table" and map.origins
    local origin = type(origins) == "table" and ns.origin and origins[ns.origin.id]
    if type(origin) == "table" and type(origin.reachable) == "table" and origin.reachable[node.id] then
        return "Route seen at this flight master", green
    end
    return "Known destination", green
end

local function hideRoute()
    for _, line in ipairs(routeLines) do line:Hide() end
end

local function resetDetails()
    if not details then return end
    details.title:SetText("ROUTE PREVIEW")
    details.title:SetTextColor(unpack(gold))
    details.time:SetText("")
    details.route:SetText("Hover a destination to preview its route and travel time.")
    details.route:SetTextColor(unpack(grey))
    statusText:SetText(defaultStatus)
end

local function clearHover(self)
    if self and hoveredWidget ~= self then return end
    hoveredWidget, hoveredID = nil, nil
    hideRoute()
    GameTooltip:Hide()
    resetDetails()
end

local function drawRoute(route)
    hideRoute()
    if not hasMapArt or not route then return end
    local used = 0
    local function stroke(x1, y1, x2, y2, thickness)
        used = used + 1
        local line = routeLines[used]
        if not line then line = canvas:CreateLine(nil, "OVERLAY"); routeLines[used] = line end
        line:SetThickness(thickness)
        line:SetColorTexture(1, 0.82, 0.25, 0.95)
        line:SetStartPoint("TOPLEFT", canvas, x1, -y1)
        line:SetEndPoint("TOPLEFT", canvas, x2, -y2)
        line:Show()
    end
    for i = 2, #route.points do
        local a, b = route.points[i - 1], route.points[i]
        local x1, y1, x2, y2 = a.x * mapWidth, a.y * mapHeight, b.x * mapWidth, b.y * mapHeight
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 1 then
            stroke(x1, y1, x2, y2, 2)
            local ux, uy = dx / length, dy / length
            -- Repeated chevrons show the actual direction through every stop.
            local arrows = math.max(1, math.min(32, math.floor(length / 42)))
            local size = math.min(6, length / 4)
            for j = 1, arrows do
                local t = j / (arrows + 1)
                local x, y = x1 + dx * t, y1 + dy * t
                stroke(x - ux * size - uy * size * 0.65, y - uy * size + ux * size * 0.65, x, y, 2)
                stroke(x - ux * size + uy * size * 0.65, y - uy * size - ux * size * 0.65, x, y, 2)
            end
        end
    end
end

local function showNodeDetails(self)
    local node = self.node
    if not node then return end
    hoveredWidget, hoveredID = self, node.id
    hideRoute()
    -- Keep all hover information below the map so no popup hides the route.
    GameTooltip:Hide()
    local state, color = nodeStatus(node)
    details.title:SetText(node.name)
    details.title:SetTextColor(unpack(color))
    details.time:SetText(state)
    details.time:SetTextColor(unpack(color))
    details.route:SetTextColor(0.83, 0.84, 0.87)
    statusText:SetText("")
    if ns.origin and ns.Model.CanPlan(ns.origin, node) then
        local route = ns.Model.GetRoute(ns.db, ns.preview.mapID, ns.origin.id, node.id)
        if (not route or route.stale) and ns.Routes then
            local estimated = ns.Routes.Estimate(ns.preview, ns.origin.id, node.id)
            if estimated then
                -- A measured time belongs to its exact stop chain, even
                -- when its original capture needs a fresh native check.
                if route and route.key == estimated.key then
                    estimated.duration, estimated.durationSource = route.duration, route.durationSource
                end
                route = estimated
            end
        end
        local duration, source = route and route.duration, route and route.durationSource
        if not duration and ns.Timings then
            duration, source = ns.Timings.Lookup(ns.preview.faction, ns.preview.mapID, ns.origin.id, node.id, route)
        end
        if duration then
            local speed = ns.API.GetFlightSpeedFactor and ns.API.GetFlightSpeedFactor() or 1
            local seconds = math.ceil(duration / speed)
            details.time:SetText(string.format("Flight time: ~%dm %02ds", math.floor(seconds / 60), seconds % 60))
            details.time:SetTextColor(unpack(gold))
        else
            details.time:SetText("Flight time: not recorded yet")
        end
        local notes = {}
        if duration then notes[#notes + 1] = source or "Estimated travel time" end
        if route then
            drawRoute(route)
            local names = {}
            for _, point in ipairs(route.points) do names[#names + 1] = point.name or ("Flight point #" .. point.id) end
            local prefix = route.estimated and "Estimated route: " or (route.stale and "Previously recorded route: " or "Route: ")
            details.route:SetText(prefix .. table.concat(names, " > "))
            if route.estimated then
                notes[#notes + 1] = "Estimated stops; the flight master's route may differ."
            elseif route.stale then
                notes[#notes + 1] = "Revisit this flight master to refresh the recorded route."
            end
        else
            details.route:SetText("No connected route is available in the bundled data. Open " .. ns.origin.name .. "'s flight map to record it.")
        end
        notes[#notes + 1] = "Click to queue from " .. ns.origin.name .. "."
        statusText:SetText(table.concat(notes, "  |  "))
    elseif ns.origin and node.id == ns.origin.id then
        details.route:SetText((node.learned == true and not node.locked) and "Hover a destination to preview a flight from here."
            or "Flights leave from here. Talking to this flight master discovers it if you haven't already.")
    elseif node.learned ~= true or node.locked then
        details.route:SetText(node.unverified
            and "The remote API cannot confirm this point. Open a flight master's normal map to verify your known destinations."
            or "This flight point is marked unknown. Discover it to select it.")
        details.route:SetTextColor(1, 0.35, 0.3)
    else
        details.route:SetText(ns.origin and "Hover a destination to preview a flight from here."
            or "No departure flight master is available here.")
    end
end

local function turnPlayerArrow()
    local facing = ns.API.Facing and ns.API.Facing()
    if facing and playerArrow.SetRotation then playerArrow:SetRotation(facing) end
end

local function makePin()
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(17, 17)
    pin:SetFrameLevel(canvas:GetFrameLevel() + 5)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Icon-White")
    pin:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    pin:SetMotionScriptsWhileDisabled(true)
    pin:SetScript("OnEnter", showNodeDetails)
    pin:SetScript("OnLeave", clearHover)
    pin:SetScript("OnClick", function(self) if self.selectable then ns.Queue(self.node) end end)
    return pin
end

local function drawMap(mapID)
    mapWaiting = false
    mapDiagnostics = { mapID = mapID, mode = "unavailable", textureCount = 0, expectedTextures = 0, loadedTextures = 0 }
    if C_Map and type(C_Map.GetMapArtID) == "function" then
        local available, artID = pcall(C_Map.GetMapArtID, mapID)
        if available and type(artID) == "number" then mapDiagnostics.artID = artID end
    end
    local ok, layers = false, nil
    if C_Map and type(C_Map.GetMapArtLayers) == "function" then
        ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    end
    if not ok or type(layers) ~= "table" then layers = nil end
    local layer, textures, columns, rowCount
    local function positive(value)
        return type(value) == "number" and value == value and value > 0 and value < math.huge
    end
    -- Do not call a partial texture list a complete map. Another resolution
    -- layer may already be available while the first one is being populated.
    for index, candidate in ipairs(layers or {}) do
        if type(candidate) == "table" and positive(candidate.layerWidth) and positive(candidate.layerHeight)
            and positive(candidate.tileWidth) and positive(candidate.tileHeight)
            and type(C_Map.GetMapArtLayerTextures) == "function" then
            local cols = math.ceil(candidate.layerWidth / candidate.tileWidth)
            local rows = math.ceil(candidate.layerHeight / candidate.tileHeight)
            if cols * rows <= 1024 then
                local available, files = pcall(C_Map.GetMapArtLayerTextures, mapID, index)
                local complete = available and type(files) == "table"
                local validCount = 0
                if complete then
                    for i = 1, cols * rows do
                        if positive(files[i]) and files[i] == math.floor(files[i]) then
                            validCount = validCount + 1
                        else
                            complete = false
                        end
                    end
                end
                if mapDiagnostics.expectedTextures == 0 or complete then
                    mapDiagnostics.layerIndex, mapDiagnostics.textureCount, mapDiagnostics.expectedTextures = index, validCount, cols * rows
                    mapDiagnostics.layerWidth, mapDiagnostics.layerHeight = candidate.layerWidth, candidate.layerHeight
                    mapDiagnostics.tileWidth, mapDiagnostics.tileHeight = candidate.tileWidth, candidate.tileHeight
                end
                if complete then layer, textures, columns, rowCount = candidate, files, cols, rows; break end
            end
        end
    end
    if not layer then
        mapDiagnostics.reason = "No complete map-art layer was returned."
        for _, texture in ipairs(tiles) do texture:Hide() end
        mapBackground:Hide()
        canvas:SetSize(628, 420)
        mapWidth, mapHeight = 628, 420
        return false
    end

    -- Blizzard's map has a parchment/sea background under transparent map
    -- areas. The dark panel backdrop is not a substitute for that map art.
    local atlas = "AdventureMap_TileBg"
    if type(C_Map.GetMapArtBackgroundAtlas) == "function" then
        local available, value = pcall(C_Map.GetMapArtBackgroundAtlas, mapID)
        if available and type(value) == "string" and value ~= "" then atlas = value end
    end
    if mapBackground.preflightAtlas ~= atlas then
        local assigned = pcall(mapBackground.SetAtlas, mapBackground, atlas)
        mapBackground.preflightAtlas = assigned and atlas or nil
    end
    mapBackground:SetShown(mapBackground.preflightAtlas ~= nil)
    mapDiagnostics.backgroundAtlas = mapBackground.preflightAtlas

    local scale = math.min(628 / layer.layerWidth, 420 / layer.layerHeight)
    mapWidth, mapHeight = layer.layerWidth * scale, layer.layerHeight * scale
    canvas:SetSize(mapWidth, mapHeight)
    local count = 0
    for row = 1, rowCount do
        for column = 1, columns do
            count = count + 1
            local texture = tiles[count]
            if not texture then
                -- BackdropTemplate's opaque Center is BACKGROUND too; map
                -- tiles need an explicit layer above it, below pins/routes.
                texture = canvas:CreateTexture(nil, "ARTWORK")
                tiles[count] = texture
            end
            local left, top = (column - 1) * layer.tileWidth, (row - 1) * layer.tileHeight
            local width = math.min(layer.tileWidth, layer.layerWidth - left)
            local height = math.min(layer.tileHeight, layer.layerHeight - top)
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", left * scale, -top * scale)
            texture:SetSize(width * scale, height * scale)
            texture:SetTexCoord(0, width / layer.tileWidth, 0, height / layer.tileHeight)
            if texture.preflightFileID ~= textures[count] then
                texture:SetTexture(textures[count], nil, nil, "TRILINEAR")
                texture.preflightFileID = textures[count]
            end
            texture:SetVertexColor(1, 1, 1)
            local ready = true
            if type(texture.IsObjectLoaded) == "function" then
                local checked, loaded = pcall(texture.IsObjectLoaded, texture)
                ready = checked and loaded
            end
            if ready then mapDiagnostics.loadedTextures = mapDiagnostics.loadedTextures + 1 else mapWaiting = true end
        end
    end
    -- Blizzard keeps requested tiles shown at zero alpha until the entire
    -- layer is resident. Match that streaming lifecycle while concealing
    -- incomplete art, instead of hiding the requested textures.
    for i, texture in ipairs(tiles) do
        texture:SetAlpha(mapWaiting and 0 or 1)
        texture:SetShown(i <= count)
    end
    if mapWaiting then
        mapDiagnostics.mode, mapDiagnostics.reason = "loading", "Map texture files are still loading."
        return false, "Map textures are loading; you can still use the destination list."
    end
    mapDiagnostics.mode = "ready"
    return true
end

function UI.GetMapDiagnostics()
    local snapshot = {}
    for key, value in pairs(mapDiagnostics) do snapshot[key] = value end
    return snapshot
end

local function makeRow(index)
    local row = CreateFrame("Button", nil, list)
    row:SetSize(250, 43)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 45)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = label(row, 12)
    row.name:SetPoint("TOPLEFT", 6, -6)
    row.name:SetWidth(238)
    row.name:SetMaxLines(1)
    row.state = label(row, 10, grey)
    row.state:SetPoint("TOPLEFT", 6, -24)
    row.state:SetWidth(238)
    row.state:SetMaxLines(1)
    row:SetScript("OnEnter", showNodeDetails)
    row:SetScript("OnLeave", clearHover)
    row:SetScript("OnClick", function(self) if self.selectable then ns.Queue(self.node) end end)
    return row
end

function UI.Render(preview, origin, distance, reason)
    if not window then return end
    defaultStatus = preview and preview.warning or reason
        or "Gold: departure   Green: known   Red: unknown or unverified"
    if not hoveredWidget then resetDetails() end
    local queue = ns.db.queue
    launcher.queued:SetShown(queue ~= nil)
    autoCheck:SetChecked(ns.db.autoDepart)
    if queue then
        queueText:SetText("QUEUED  " .. queue.sourceName .. "  >  " .. queue.destinationName)
    else
        queueText:SetText("Choose a destination on the map to queue your next flight.")
    end
    cancel:SetEnabled(queue ~= nil)
    local ready = ns.taxiOpen and queue and ns.live and ns.Model.ResolveQueue(queue, ns.live, ns.API.Context())
    depart:SetEnabled(ready ~= nil and ready ~= false and not ns.attempt)
    playerPin:Hide()
    if not preview then
        mapWaiting, hasMapArt = false, false
        mapDiagnostics = { mode = "unavailable", textureCount = 0, expectedTextures = 0, loadedTextures = 0,
            reason = reason or "No map preview is available here." }
        clearHover()
        for _, pin in ipairs(pins) do pin:Hide() end
        for _, row in ipairs(rows) do row:Hide() end
        for _, tile in ipairs(tiles) do tile:Hide() end
        mapBackground:Hide()
        mapTitle:SetText("FLIGHT PLANNER")
        originText:SetText("Closest flight master unavailable")
        statusText:SetText(reason or "Move outdoors and open the planner again.")
        emptyText:SetText(reason or "Flight data is unavailable here.")
        emptyText:Show()
        list:SetHeight(1)
        emptyListText:SetText("No known destinations available here.")
        emptyListText:Show()
        return
    end
    mapTitle:SetText(string.upper(preview.mapName or "Flight planner"))
    originText:SetText(origin and ("Closest: " .. origin.name .. originNote(origin)
        .. (distance and ("  ~" .. math.floor(distance + 0.5) .. " yd") or ""))
        or "No flight master is available on this map")
    local art, artReason = drawMap(preview.mapID)
    hasMapArt = art
    emptyText:SetText(art and "No flight points are available yet. Visit a flight master to record its map." or artReason or "Map art unavailable; choose a destination from the list.")
    emptyText:SetShown(not art or #preview.nodes == 0)
    local filter = (search:GetText() or ""):lower()
    local visible = {}
    local pinCount = 0
    for _, node in ipairs(preview.nodes) do
        if not node.transition and (not node.faction or node.faction == 0 or node.faction == preview.faction) then
            local state, color = nodeStatus(node)
            if art and type(node.x) == "number" and type(node.y) == "number"
                and node.x >= 0 and node.x <= 1 and node.y >= 0 and node.y <= 1 then
                pinCount = pinCount + 1
                local pin = pins[pinCount]
                if not pin then pin = makePin(); pins[pinCount] = pin end
                pin.node = node
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", node.x * mapWidth, -node.y * mapHeight)
                pin.selectable = origin and ns.Model.CanPlan(origin, node) or false
                pin:SetEnabled(pin.selectable)
                local selected = node.learned == true and not node.locked and queue and queue.destinationID == node.id
                pin:SetSize(selected and 25 or 17, selected and 25 or 17)
                pin.icon:SetVertexColor(unpack(selected and gold or color))
                pin:Show()
            end
            if node.learned == true and not node.locked and (not origin or origin.id ~= node.id)
                and (filter == "" or node.name:lower():find(filter, 1, true)) then
                visible[#visible + 1] = { node = node, state = state, color = color }
            end
        end
    end
    table.sort(visible, function(a, b) return a.node.name < b.node.name end)
    for i, item in ipairs(visible) do
        local row = rows[i]
        if not row then row = makeRow(i); rows[i] = row end
        row.node = item.node
        row.selectable = origin and ns.Model.CanPlan(origin, item.node) or false
        row:SetEnabled(row.selectable)
        local selected = queue and queue.destinationID == item.node.id
        row.name:SetText((selected and "> " or "") .. item.node.name)
        row.name:SetTextColor(unpack(selected and gold or item.color))
        row.state:SetText(item.state)
        row:Show()
    end
    for i = pinCount + 1, #pins do pins[i]:Hide() end
    for i = #visible + 1, #rows do rows[i]:Hide() end
    emptyListText:SetText(filter ~= "" and "No matching known destinations."
        or (preview.needsFlightSync and "Open a flight master's map to refresh unavailable discovery data." or "No known destinations available here."))
    emptyListText:SetShown(#visible == 0)
    list:SetHeight(math.max(1, #visible * 45))
    local maxScroll = math.max(0, list:GetHeight() - scroll:GetHeight())
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
    local player = preview.player
    if art and player and type(player.x) == "number" and type(player.y) == "number"
        and player.x >= 0 and player.x <= 1 and player.y >= 0 and player.y <= 1 then
        playerPin:ClearAllPoints()
        playerPin:SetPoint("CENTER", canvas, "TOPLEFT", player.x * mapWidth, -player.y * mapHeight)
        turnPlayerArrow()
        playerPin:Show()
    end
    if hoveredWidget then
        if hoveredWidget:IsShown() and hoveredWidget.node and hoveredWidget.node.id == hoveredID then
            showNodeDetails(hoveredWidget)
        else
            clearHover()
        end
    end
end

function UI.Show() window:Show(); ns.Refresh() end
function UI.Hide() clearHover(); window:Hide() end
function UI.Toggle() if window:IsShown() then UI.Hide() else UI.Show() end end
function UI.ResetPosition()
    ns.db.buttonPosition, ns.db.windowPosition = nil, nil
    restore(launcher, nil, -180, -100)
    restore(window)
    ns.Print("Button and planner positions reset.")
end

function UI.Init()
    launcher = CreateFrame("Button", "PreflightButton", UIParent, "BackdropTemplate")
    launcher:SetSize(48, 48)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetMovable(true)
    launcher:SetClampedToScreen(true)
    launcher:RegisterForDrag("LeftButton")
    launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    backdrop(launcher, nil, { 0.82, 0.62, 0.27, 1 })
    launcher.icon = launcher:CreateTexture(nil, "ARTWORK")
    launcher.icon:SetPoint("TOPLEFT", 4, -4)
    launcher.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    launcher.icon:SetTexture("Interface\\Icons\\Ability_Mount_Gryphon_01")
    launcher.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    launcher:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    launcher.queued = label(launcher, 20, gold)
    launcher.queued:SetPoint("TOPRIGHT", 3, 6)
    launcher.queued:SetText("*")
    launcher.queued:Hide()
    launcher:SetScript("OnMouseDown", function(self) self.dragged = false end)
    launcher:SetScript("OnDragStart", function(self) self.dragged = true; self:StartMoving() end)
    launcher:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self, "buttonPosition") end)
    launcher:SetScript("OnClick", function(self, mouseButton)
        if self.dragged then return end
        if mouseButton == "RightButton" then ns.Cancel() else ns.Toggle() end
    end)
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Preflight Forever", 1, 0.84, 0.5)
        local queue = ns.db.queue
        GameTooltip:AddLine(queue and (queue.sourceName .. " > " .. queue.destinationName) or "Plan your next flight.", 1, 1, 1, true)
        GameTooltip:AddLine("Left-click: planner  |  Drag: move", 0.7, 0.73, 0.79)
        GameTooltip:AddLine("Right-click: clear queued flight", 0.7, 0.73, 0.79)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
    restore(launcher, ns.db.buttonPosition, -180, -100)

    window = CreateFrame("Frame", "PreflightPlanner", UIParent, "BackdropTemplate")
    window:SetSize(960, 760)
    window:SetScale(math.min(1, (UIParent:GetWidth() - 30) / 960, (UIParent:GetHeight() - 30) / 760))
    window:SetFrameStrata("HIGH")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    backdrop(window)
    restore(window, ns.db.windowPosition)
    window:Hide()
    window:SetScript("OnHide", function() clearHover() end)
    UISpecialFrames[#UISpecialFrames + 1] = "PreflightPlanner"
    local title = label(window, 23, gold)
    title:SetPoint("TOPLEFT", 20, -17)
    title:SetText("Preflight Forever")
    local subtitle = label(window, 11, grey)
    subtitle:SetPoint("TOPLEFT", 21, -45)
    subtitle:SetText("PLAN HERE. DEPART AT THE FLIGHT MASTER.")
    local drag = CreateFrame("Frame", nil, window)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -40, 0)
    drag:SetHeight(65)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() window:StartMoving() end)
    drag:SetScript("OnDragStop", function() window:StopMovingOrSizing(); savePosition(window, "windowPosition") end)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", UI.Hide)
    originText = label(window, 14, gold)
    originText:SetPoint("TOPLEFT", 20, -77)
    originText:SetWidth(914)
    originText:SetMaxLines(1)
    mapTitle = label(window, 10, grey)
    mapTitle:SetPoint("TOPLEFT", 21, -105)
    canvas = CreateFrame("Frame", nil, window, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", 20, -128)
    canvas:SetSize(mapWidth, mapHeight)
    backdrop(canvas, { 0.025, 0.03, 0.04, 1 })
    mapBackground = canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
    mapBackground:SetAllPoints(canvas)
    mapBackground:SetHorizTile(true)
    mapBackground:SetVertTile(true)
    mapBackground:Hide()
    emptyText = label(canvas, 14, grey)
    emptyText:SetPoint("CENTER")
    emptyText:SetWidth(490)
    emptyText:SetJustifyH("CENTER")
    -- The world map's own player arrow, kept turned to the character's facing.
    playerPin = CreateFrame("Frame", nil, canvas)
    playerPin:SetSize(24, 24)
    playerPin:SetFrameLevel(canvas:GetFrameLevel() + 8)
    playerArrow = playerPin:CreateTexture(nil, "OVERLAY")
    playerArrow:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-WorldMapArrow") then
        playerArrow:SetAtlas("UI-WorldMapArrow")
    else
        playerArrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    end
    playerPin:SetScript("OnUpdate", turnPlayerArrow)
    local destinations = label(window, 10, grey)
    destinations:SetPoint("TOPLEFT", 670, -105)
    destinations:SetText("DESTINATIONS")
    search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    search:SetSize(248, 25)
    search:SetPoint("TOPLEFT", 676, -128)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local searchHint = label(search, 11, grey)
    searchHint:SetPoint("LEFT", 4, 0)
    searchHint:SetText("Search destinations")
    search:SetScript("OnTextChanged", function(self)
        searchHint:SetShown(self:GetText() == "")
        if ns.db then UI.Render(ns.preview, ns.origin, ns.distance) end
    end)
    scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 670, -162)
    scroll:SetSize(252, 386)
    list = CreateFrame("Frame", nil, scroll)
    list:SetSize(250, 1)
    scroll:SetScrollChild(list)
    emptyListText = label(window, 12, grey)
    emptyListText:SetPoint("TOPLEFT", 677, -175)
    emptyListText:SetWidth(230)
    details = CreateFrame("Frame", "PreflightDetails", window, "BackdropTemplate")
    details:SetPoint("TOPLEFT", 20, -557)
    details:SetSize(918, 110)
    backdrop(details, { 0.025, 0.03, 0.04, 1 })
    details.title = label(details, 13, gold)
    details.title:SetPoint("TOPLEFT", 10, -8)
    details.title:SetSize(598, 18)
    details.title:SetMaxLines(1)
    details.time = label(details, 12, gold)
    details.time:SetPoint("TOPRIGHT", -10, -8)
    details.time:SetSize(280, 18)
    details.time:SetJustifyH("RIGHT")
    details.time:SetMaxLines(1)
    details.route = label(details, 11, grey)
    details.route:SetPoint("TOPLEFT", 10, -30)
    details.route:SetSize(898, 42)
    details.route:SetJustifyV("TOP")
    details.route:SetMaxLines(3)
    statusText = label(details, 10, grey)
    statusText:SetPoint("TOPLEFT", 10, -79)
    statusText:SetSize(898, 26)
    statusText:SetJustifyV("TOP")
    statusText:SetMaxLines(2)
    details.note = statusText
    resetDetails()
    queueText = label(window, 12, gold)
    queueText:SetPoint("TOPLEFT", 20, -686)
    queueText:SetWidth(918)
    queueText:SetMaxLines(1)
    autoCheck = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
    autoCheck:SetSize(26, 26)
    autoCheck:SetPoint("BOTTOMLEFT", 16, 9)
    autoCheck:SetScript("OnClick", function(self) ns.db.autoDepart = self:GetChecked() == true; ns.Refresh() end)
    local autoLabel = label(autoCheck, 11, grey)
    autoLabel:SetPoint("LEFT", autoCheck, "RIGHT", 1, 0)
    autoLabel:SetText("Auto-depart on arrival (hold Shift to skip)")
    cancel = button(window, "Clear queue", 110, ns.Cancel)
    cancel:SetPoint("BOTTOMRIGHT", -158, 10)
    depart = button(window, "Depart now", 130, ns.Depart)
    depart:SetPoint("BOTTOMRIGHT", -20, 10)
    local elapsed = 0
    window:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= (mapWaiting and 0.1 or 2) then elapsed = 0; ns.Refresh() end
    end)
end
