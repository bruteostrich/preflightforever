-- A strict widget double: unimplemented methods raise errors instead of being
-- silently accepted. These are Frame, Texture, FontString and EditBox methods
-- used by the addon; this exercises construction and callbacks, not rendering.
unpack = unpack or table.unpack
local passed = 0

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001,
        "expected approximately " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
    local ok, err = pcall(run)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("ok - " .. name)
end

local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetAllPoints(relative) self.allPoints = relative or self.parent end
function methods:SetFont(font, size) self.font, self.fontSize = font, size end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetJustifyV(value) self.justifyV = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetMaxLines(value) self.maxLines = value end
function methods:SetText(value)
    self.text = value
    if self.kind == "Tooltip" then self.lines = {} end
    if self.kind == "EditBox" and self.scripts.OnTextChanged then
        self.scripts.OnTextChanged(self, false)
    end
end
function methods:GetText() return self.text or "" end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.borderColor = { ... } end
function methods:SetTexture(value, horizontalWrap, verticalWrap, filter)
    self.texture, self.filter = value, filter
    self.textureAssignments = (self.textureAssignments or 0) + 1
end
function methods:SetAtlas(value) self.atlas = value end
function methods:SetRotation(radians) self.rotation = radians end
function methods:SetHorizTile(value) self.horizontalTile = value end
function methods:SetVertTile(value) self.verticalTile = value end
function methods:IsObjectLoaded() return self.loaded ~= false end
function methods:SetColorTexture(...) self.colorTexture = { ... } end
function methods:SetThickness(value) self.thickness = value end
function methods:SetStartPoint(...) self.startPoint = { ... } end
function methods:SetEndPoint(...) self.endPoint = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetHighlightTexture(texture, blend) self.highlight = { texture, blend } end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetScale(value) self.scale = value end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetEffectiveScale()
    return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function methods:GetCenter()
    if self.centerX then return self.centerX, self.centerY end
    local point = self.points[#self.points]
    if point and point[1] == "CENTER" and type(point[2]) == "table" then
        local x, y = point[2]:GetCenter()
        local ratio = point[2]:GetEffectiveScale() / self:GetEffectiveScale()
        return x * ratio + (point[4] or 0), y * ratio + (point[5] or 0)
    end
    return self:GetWidth() / 2, self:GetHeight() / 2
end
function methods:SetMovable(value) self.movable = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:SetMotionScriptsWhileDisabled(value) self.motionWhileDisabled = value end
function methods:RegisterForDrag(...) self.dragButtons = { ... } end
function methods:RegisterForClicks(...) self.clickButtons = { ... } end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:SetScript(event, handler)
    assert(handler == nil or type(handler) == "function", "invalid script handler for " .. event)
    self.scripts[event] = handler
end
function methods:Show()
    self.shown = true
    self.showCount = (self.showCount or 0) + 1
end
function methods:Hide()
    local wasShown = self.shown
    self.shown = false
    self.hideCount = (self.hideCount or 0) + 1
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:SetEnabled(value) self.enabled = not not value end
function methods:IsEnabled() return self.enabled end
function methods:SetChecked(value) self.checked = not not value end
function methods:GetChecked() return self.checked end
function methods:SetAutoFocus(value) self.autoFocus = value end
function methods:SetMaxLetters(value) self.maxLetters = value end
function methods:ClearFocus() self.focused = false end
function methods:SetScrollChild(value) self.scrollChild = value end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
function methods:AddLine(text, ...) self.lines[#self.lines + 1] = { text, ... } end

local function harness(options)
    options = options or {}
    local h = { widgets = {}, names = {}, messages = {}, queued = {}, refreshCount = 0, departCount = 0 }
    local function widget(kind, name, parent, template)
        local item = setmetatable({ kind = kind, objectName = name, parent = parent, template = template,
            scripts = {}, points = {}, lines = {}, children = {}, shown = true, enabled = true }, { __index = methods })
        h.widgets[#h.widgets + 1] = item
        if parent then parent.children[#parent.children + 1] = item end
        if name then h.names[name] = item; _G[name] = item end
        function item:CreateTexture(regionName, layer, templateName, subLevel)
            local region = widget("Texture", regionName, self)
            region.layer, region.subLevel = layer, subLevel
            return region
        end
        function item:CreateLine(regionName, layer)
            local region = widget("Line", regionName, self)
            region.layer = layer
            return region
        end
        function item:CreateFontString(regionName, layer, font)
            local region = widget("FontString", regionName, self, font)
            region.layer = layer
            return region
        end
        return item
    end
    CreateFrame = widget
    UIParent = widget("Frame", "UIParent")
    UIParent:SetSize(1920, 1080)
    UIParent.centerX, UIParent.centerY = 960, 540
    GameTooltip = widget("Tooltip", "GameTooltip")
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    UISpecialFrames = {}
    h.layer = { layerWidth = 1000, layerHeight = 650, tileWidth = 256, tileHeight = 256 }
    h.textures = {}
    for i = 1, 12 do h.textures[i] = 1000 + i end
    C_Texture = not options.noAtlas and { GetAtlasInfo = function(name)
        if name == "UI-WorldMapArrow" then return { width = 32, height = 32 } end
    end } or nil
    C_Map = {
        GetMapArtLayers = function() return h.layers or (h.layer and { h.layer } or nil) end,
        GetMapArtLayerTextures = function(_, index) return h.texturesByLayer and h.texturesByLayer[index] or h.textures end,
        GetMapArtBackgroundAtlas = function() return h.backgroundAtlas or "AdventureMap_TileBg" end,
    }
    local ns = { db = { maps = {}, learned = {}, autoDepart = true } }
    h.ns = ns
    h.context = { inCombat = false, onTaxi = false, dead = false, money = 500 }
    h.speedFactor, h.lookupCalls = 1, 0
    ns.API = { Context = function() return h.context end,
        GetFlightSpeedFactor = function() return h.speedFactor end,
        Facing = function() return h.facing end }
    ns.Timings = { Lookup = function(faction, mapID, sourceID, destinationID, route)
        h.lookupCalls = h.lookupCalls + 1
        h.lookupArgs = { faction, mapID, sourceID, destinationID, route }
        return h.databaseDuration, h.databaseSource
    end }
    assert(loadfile("Model.lua"))("PreflightForever", ns)
    ns.Print = function(message) h.messages[#h.messages + 1] = message end
    ns.Refresh = function()
        h.refreshCount = h.refreshCount + 1
        ns.UI.Render(ns.preview, ns.origin, ns.distance, h.reason)
    end
    ns.Queue = function(node)
        h.queued[#h.queued + 1] = node.id
        if not ns.Model.CanPlan(ns.origin, node) then return end
        ns.db.queue = ns.Model.NewQueue(ns.origin, node, ns.preview.mapID, 100)
        ns.Refresh()
    end
    ns.Cancel = function() ns.db.queue = nil; ns.Refresh() end
    ns.Depart = function() h.departCount = h.departCount + 1 end
    ns.Toggle = function() ns.UI.Toggle() end
    assert(loadfile("UI.lua"))("PreflightForever", ns)
    ns.UI.Init()
    h.window, h.launcher, h.details = h.names.PreflightPlanner, h.names.PreflightButton, h.names.PreflightDetails
    function h:find(predicate)
        local found = {}
        for _, item in ipairs(self.widgets) do
            if predicate(item) then found[#found + 1] = item end
        end
        return found
    end
    function h:one(predicate)
        local found = self:find(predicate)
        equal(#found, 1)
        return found[1]
    end
    function h:hasText(text)
        local found = self:find(function(item) return item.text == text and item.shown end)
        return #found > 0
    end
    function h:rows()
        return self:find(function(item) return item.kind == "Button" and item.state and item.shown end)
    end
    function h:pins()
        return self:find(function(item) return item.kind == "Button" and item.node and item.icon and item.shown end)
    end
    function h:routeLines()
        return self:find(function(item) return item.kind == "Line" and item.shown end)
    end
    function h:footerHas(text)
        for _, key in ipairs({ "title", "time", "route", "note" }) do
            local label = h.details[key]
            if label and label:GetText():find(text, 1, true) then return true end
        end
        return false
    end
    function h:idleFooter()
        equal(self.details.title:GetText(), "ROUTE PREVIEW")
        equal(self.details.time:GetText(), "")
        equal(self.details.route:GetText(), "Hover a destination to preview its route and travel time.")
    end
    function h:button(text)
        return self:one(function(item) return item.kind == "Button" and item.text == text end)
    end
    function h:click(item, mouse)
        if item.enabled and item.scripts.OnClick then item.scripts.OnClick(item, mouse or "LeftButton") end
    end
    function h:render()
        self.ns.Refresh()
    end
    function h:preview(known)
        ns.preview = {
            mapID = 1415, mapName = "Eastern Kingdoms", faction = 2,
            player = { x = 0.21, y = 0.22, instanceID = 0, worldX = 1, worldY = 1 },
            nodes = {
                { id = 10, name = "Origin", x = 0.2, y = 0.2, faction = 2, instanceID = 0, worldX = 0, worldY = 0 },
                { id = 20, name = "Centerville", x = 0.8, y = 0.8, faction = 2, instanceID = 0, worldX = 100, worldY = 100 },
                { id = 30, name = "Northwatch", x = 0.4, y = 0.1, faction = 0, instanceID = 0, worldX = 50, worldY = 80 },
            },
        }
        if known ~= false then
            for _, node in ipairs(ns.preview.nodes) do
                node.learned, ns.db.learned[node.id] = true, true
            end
        end
        ns.origin, ns.distance = ns.Model.FindNearest(ns.preview.nodes, ns.preview.player, 2)
        self:render()
    end
    function h:recordRoute(seconds)
        local nodes = ns.preview.nodes
        ns.Model.RecordSnapshot(ns.db, { mapID = 1415, sourceID = 10, nodes = {
            { id = 10, name = "Origin", state = "CURRENT" },
            { id = 30, name = "Northwatch", state = "REACHABLE" },
            { id = 20, name = "Centerville", state = "REACHABLE", route = {
                key = "10:30:20", points = { nodes[1], nodes[3], nodes[2] },
            } },
        } }, 100)
        if seconds then ns.Model.RecordDuration(ns.db, 1415, 10, 20, "10:30:20", seconds, 1) end
    end
    return h
end

test("UI constructs with valid callbacks and an initially hidden planner", function()
    local h = harness()
    equal(h.window:IsShown(), false)
    equal(h.launcher:IsShown(), true)
    equal(UISpecialFrames[1], "PreflightPlanner")
    assert(h.launcher.scripts.OnClick)
    assert(h.window.scripts.OnUpdate)
    equal(h.launcher.movable, true)
    equal(h.launcher.clamped, true)
end)

test("unavailable preview shows a useful state and disables departure", function()
    local h = harness()
    h.reason = "Move outdoors to locate your flight master."
    h:render()
    assert(h:hasText(h.reason))
    assert(h:hasText("Closest flight master unavailable"))
    equal(h:button("Depart now"):IsEnabled(), false)
    equal(h:button("Clear queue"):IsEnabled(), false)
    equal(#h:rows(), 0)
end)

test("missing discovery data leaves points red and explains how to refresh it", function()
    local h = harness()
    h:preview(false)
    h.ns.preview.needsFlightSync = true
    h:render()
    equal(#h:pins(), 3)
    equal(#h:rows(), 0)
    -- The closest point is still the departure (gold); nothing else is selectable.
    equal(h.ns.origin, h.ns.preview.nodes[1])
    for _, pin in ipairs(h:pins()) do
        equal(pin:IsEnabled(), false)
        equal(pin.motionWhileDisabled, true)
        local isOrigin = pin.node == h.ns.origin
        near(pin.icon.vertexColor[1], 1)
        near(pin.icon.vertexColor[2], isOrigin and 0.78 or 0.18)
        near(pin.icon.vertexColor[3], isOrigin and 0.34 or 0.16)
        h:click(pin)
        pin.scripts.OnClick(pin)
    end
    equal(#h.queued, 0)
    equal(h.ns.db.queue, nil)
    assert(h:hasText("Open a flight master's map to refresh unavailable discovery data."))
    assert(h:hasText("Closest: Origin (undiscovered)  ~1 yd"))
    assert(h:hasText("EASTERN KINGDOMS"))
end)

test("confirmed preview destinations are selectable before Preflight Forever visits a native map", function()
    local h = harness()
    h:preview()
    h.ns.db.learned, h.ns.db.observed = {}, {}
    h.ns.preview.needsFlightSync = false
    h:render()
    equal(#h:rows(), 2)
    equal(h.ns.origin.id, 10)
    equal(h:rows()[1]:IsEnabled(), true)
    h:click(h:rows()[1])
    equal(h.ns.db.queue.destinationID, 20)
    assert(not h:hasText("Flight discovery data is unavailable"))
end)

test("unverified remote points stay red and disabled with honest footer text", function()
    local h = harness()
    h:preview()
    local node = h.ns.preview.nodes[3]
    node.learned, node.locked, node.unverified = false, true, true
    h:render()
    local pin = h:one(function(item) return item.kind == "Button" and item.icon and item.node == node end)
    equal(pin:IsEnabled(), false)
    near(pin.icon.vertexColor[2], 0.18)
    equal(#h:rows(), 1)
    pin.scripts.OnEnter(pin)
    assert(h:footerHas("Unverified flight point"))
    assert(h:footerHas("The remote API cannot confirm this point. Open a flight master's normal map to verify your known destinations."))
    equal(h.lookupCalls, 0)
    pin.scripts.OnClick(pin)
    equal(#h.queued, 0)
end)

test("an API-reported all-unknown map does not claim synchronization is required", function()
    local h = harness()
    h:preview(false)
    h.ns.preview.needsFlightSync = false
    for _, node in ipairs(h.ns.preview.nodes) do node.learned, node.locked = false, true end
    h:render()
    equal(#h:rows(), 0)
    equal(h.ns.origin, h.ns.preview.nodes[1])
    assert(h:hasText("Closest: Origin (undiscovered)  ~1 yd"))
    assert(h:hasText("No known destinations available here."))
    assert(not h:hasText("Open a flight master's map to refresh unavailable discovery data."))
    for _, pin in ipairs(h:pins()) do
        equal(pin:IsEnabled(), false)
        near(pin.icon.vertexColor[1], 1)
        near(pin.icon.vertexColor[2], pin.node == h.ns.origin and 0.78 or 0.18)
    end
end)

test("learned routes and undiscovered points get distinct labels", function()
    local h = harness()
    h:preview()
    h.ns.db.maps[1415] = { origins = { [10] = { reachable = { [20] = true } } } }
    h.ns.preview.nodes[3].locked = true
    h:render()
    local rows = h:rows()
    equal(#rows, 1)
    equal(rows[1].node.id, 20)
    equal(rows[1].state.text, "Route seen at this flight master")
    local pin = h:one(function(item) return item.kind == "Button" and item.node and item.icon and item.node.id == 30 end)
    equal(pin:IsEnabled(), false)
    near(pin.icon.vertexColor[2], 0.18)
    h:click(pin)
    pin.scripts.OnClick(pin)
    equal(#h.queued, 0)
    pin.scripts.OnEnter(pin)
    assert(h:footerHas("Unknown flight point"))
    equal(h.ns.db.queue, nil)
end)

test("malformed cached route observations retain confirmed known labels", function()
    local h = harness()
    h:preview()
    for _, map in ipairs({ "invalid", { origins = false }, { origins = { [10] = "invalid" } },
        { origins = { [10] = {} } }, { origins = { [10] = { reachable = true } } } }) do
        h.ns.db.maps[1415] = map
        h:render()
        equal(h:rows()[1].state.text, "Known destination")
    end
end)

test("map pins and destination rows queue their own stable destination", function()
    local h = harness()
    h:preview()
    h:click(h:rows()[1])
    equal(h.ns.db.queue.destinationID, 20)
    equal(h.launcher.queued:IsShown(), true)
    equal(h:button("Clear queue"):IsEnabled(), true)
    local target = h:one(function(item) return item.kind == "Button" and item.node
        and item.node.id == 30 and item.icon and item.shown end)
    h:click(target)
    equal(h.ns.db.queue.destinationID, 30)
    equal(target.width, 25)
    equal(h:button("Depart now"):IsEnabled(), false)
end)

test("map tiles preserve aspect ratio and crop partial final tiles", function()
    local h = harness()
    h:preview()
    local tiles = h:find(function(item) return item.kind == "Texture" and type(item.texture) == "number" and item.shown end)
    equal(#tiles, 12)
    local last = tiles[12]
    equal(last.texture, 1012)
    near(last.parent.width, 628)
    near(last.parent.height, 408.2)
    near(last.width, 232 * 0.628)
    near(last.height, 138 * 0.628)
    near(last.texCoord[2], 232 / 256)
    near(last.texCoord[4], 138 / 256)
    near(last.points[1][4], 768 * 0.628)
    near(last.points[1][5], -512 * 0.628)
end)

test("map art draws above the dark panel with the native map background underneath", function()
    local h = harness()
    h.backgroundAtlas = "ContinentBackground"
    h:preview()
    local background = h:one(function(item) return item.atlas == "ContinentBackground" end)
    equal(background.layer, "BACKGROUND")
    equal(background.subLevel, 1)
    equal(background.horizontalTile, true)
    equal(background.verticalTile, true)
    equal(background.shown, true)
    local art = h:find(function(item) return item.kind == "Texture" and type(item.texture) == "number" end)
    equal(#art, 12)
    for _, tile in ipairs(art) do
        equal(tile.layer, "ARTWORK")
        equal(tile.filter, "TRILINEAR")
        near(tile.vertexColor[1], 1)
    end
end)

test("missing middle tiles cannot leave a partially black map", function()
    local h = harness()
    h.textures[6] = nil
    h:preview()
    equal(#h:find(function(item) return item.kind == "Texture" and type(item.texture) == "number" and item.shown end), 0)
    equal(#h:pins(), 0)
    equal(#h:rows(), 2)
    assert(h:hasText("Map art unavailable; choose a destination from the list."))
end)

test("a complete alternate art layer replaces an incomplete first layer", function()
    local h = harness()
    h.layers = { h.layer, { layerWidth = 1000, layerHeight = 650, tileWidth = 512, tileHeight = 512 } }
    h.texturesByLayer = { { 1001 }, { 2001, 2002, 2003, 2004 } }
    h:preview()
    local art = h:find(function(item) return item.kind == "Texture" and type(item.texture) == "number" and item.shown end)
    equal(#art, 4)
    equal(art[4].texture, 2004)
    near(art[4].points[1][4], 512 * 0.628)
    near(art[4].texCoord[2], 488 / 512)
    near(art[4].texCoord[4], 138 / 512)
    equal(#h:pins(), 3)
end)

test("periodic updates do not reset map texture streaming", function()
    local h = harness()
    h:preview()
    local art = h:find(function(item) return item.kind == "Texture" and type(item.texture) == "number" end)
    h:render()
    h:render()
    for _, tile in ipairs(art) do equal(tile.textureAssignments, 1) end
    h.textures[2] = 3030
    h:render()
    equal(art[2].textureAssignments, 2)
    equal(art[2].texture, 3030)
    equal(art[1].textureAssignments, 1)
end)

test("streaming map textures show loading instead of black holes and refresh when ready", function()
    local h = harness()
    h:preview()
    local art = h:find(function(item) return item.kind == "Texture" and type(item.texture) == "number" end)
    art[5].loaded = false
    h:render()
    for _, tile in ipairs(art) do equal(tile.shown, true); equal(tile.alpha, 0) end
    equal(#h:pins(), 0)
    equal(#h:rows(), 2)
    assert(h:hasText("Map textures are loading; you can still use the destination list."))
    art[5].loaded = true
    h.window.scripts.OnUpdate(h.window, 0.11)
    for _, tile in ipairs(art) do equal(tile.shown, true); equal(tile.alpha, 1); equal(tile.textureAssignments, 1) end
    equal(#h:pins(), 3)
end)

test("map diagnostics report actual art completeness and loading state without mutable aliases", function()
    local h = harness()
    h:preview()
    local info = h.ns.UI.GetMapDiagnostics()
    equal(info.mapID, 1415)
    equal(info.mode, "ready")
    equal(info.textureCount, 12)
    equal(info.expectedTextures, 12)
    equal(info.loadedTextures, 12)
    equal(info.backgroundAtlas, "AdventureMap_TileBg")
    info.mode = "overwritten"
    equal(h.ns.UI.GetMapDiagnostics().mode, "ready")
    h.textures[7] = nil
    h:render()
    info = h.ns.UI.GetMapDiagnostics()
    equal(info.mode, "unavailable")
    equal(info.textureCount, 11)
    equal(info.expectedTextures, 12)
    assert(info.reason)
    h.textures[7] = 1007
    local art = h:find(function(item) return item.kind == "Texture" and type(item.texture) == "number" end)
    art[1].loaded = false
    h:render()
    info = h.ns.UI.GetMapDiagnostics()
    equal(info.mode, "loading")
    equal(info.loadedTextures, 11)
    equal(info.textureCount, 12)
    h.ns.preview = nil
    h.reason = "Player map is unavailable."
    h:render()
    info = h.ns.UI.GetMapDiagnostics()
    equal(info.mapID, nil)
    equal(info.mode, "unavailable")
    equal(info.textureCount, 0)
    equal(info.expectedTextures, 0)
    equal(info.loadedTextures, 0)
    equal(info.backgroundAtlas, nil)
    equal(info.reason, h.reason)
    local refreshes = h.refreshCount
    h.window.scripts.OnUpdate(h.window, 0.2)
    equal(h.refreshCount, refreshes)
end)

test("missing map art preserves destination list selection", function()
    local h = harness()
    h:preview()
    h.layer = nil
    h:render()
    equal(#h:pins(), 0)
    equal(#h:rows(), 2)
    assert(h:hasText("Map art unavailable; choose a destination from the list."))
    h:click(h:rows()[1])
    equal(h.ns.db.queue.destinationID, 20)
end)

test("empty texture results show the missing-art fallback", function()
    local h = harness()
    h:preview()
    h.textures = {}
    h:render()
    equal(#h:rows(), 2)
    assert(h:hasText("Map art unavailable; choose a destination from the list."))
end)

test("search filters destination rows without treating input as a Lua pattern", function()
    local h = harness()
    h:preview()
    local search = h:one(function(item) return item.kind == "EditBox" end)
    search:SetText("CENTER")
    equal(#h:rows(), 1)
    equal(h:rows()[1].node.id, 20)
    equal(#h:pins(), 3)
    search:SetText("[")
    equal(#h:rows(), 0)
    search:SetText("")
    equal(#h:rows(), 2)
    assert(h:hasText("Search destinations"))
    search.focused = true
    search.scripts.OnEscapePressed(search)
    equal(search.focused, false)
end)

test("search clamps the scroll position after the list shrinks", function()
    local h = harness()
    h:preview()
    local search = h:one(function(item) return item.kind == "EditBox" end)
    local scroll = h:one(function(item) return item.kind == "ScrollFrame" end)
    scroll:SetVerticalScroll(400)
    search:SetText("center")
    equal(scroll:GetVerticalScroll(), 0)
end)

test("manual departure is enabled only at the queued source with a valid fare", function()
    local h = harness()
    h:preview()
    h:click(h:rows()[1])
    local depart = h:button("Depart now")
    equal(depart:IsEnabled(), false)
    h.ns.taxiOpen = true
    h.ns.live = { mapID = 1415, sourceID = 99, nodes = {
        { id = 20, slot = 7, state = "REACHABLE", cost = 100 },
    } }
    h:render()
    equal(depart:IsEnabled(), false)
    h.ns.live.sourceID = 10
    h:render()
    equal(depart:IsEnabled(), true)
    h:click(depart)
    equal(h.departCount, 1)
    h.context.money = 99
    h:render()
    equal(depart:IsEnabled(), false)
    h.context.money = 500
    h.ns.attempt = {}
    h:render()
    equal(depart:IsEnabled(), false)
end)

test("launcher toggles the planner, dragging suppresses click, and right-click clears", function()
    local h = harness()
    h:preview()
    h:click(h.launcher)
    equal(h.window:IsShown(), true)
    h:click(h.launcher)
    equal(h.window:IsShown(), false)
    h.launcher.scripts.OnMouseDown(h.launcher)
    h.launcher.scripts.OnDragStart(h.launcher)
    h.launcher.centerX, h.launcher.centerY = 1000, 600
    h.launcher.scripts.OnDragStop(h.launcher)
    h:click(h.launcher)
    equal(h.window:IsShown(), false)
    near(h.ns.db.buttonPosition.x, 40)
    near(h.ns.db.buttonPosition.y, 60)
    h.launcher.scripts.OnMouseDown(h.launcher)
    h:click(h:rows()[1])
    assert(h.ns.db.queue)
    h:click(h.launcher, "RightButton")
    equal(h.ns.db.queue, nil)
end)

test("reset restores launcher and planner anchors and clears saved positions", function()
    local h = harness()
    h.ns.db.buttonPosition = { x = 25, y = 80 }
    h.ns.db.windowPosition = { x = 90, y = 120 }
    h.ns.UI.ResetPosition()
    equal(h.ns.db.buttonPosition, nil)
    equal(h.ns.db.windowPosition, nil)
    equal(h.launcher.points[1][4], -180)
    equal(h.launcher.points[1][5], -100)
    equal(h.window.points[1][4], 0)
    equal(h.window.points[1][5], 0)
end)

test("destination details stay in the footer while the launcher keeps its tooltip", function()
    local h = harness()
    h:preview()
    local row = h:rows()[1]
    local tooltipShows = GameTooltip.showCount or 0
    row.scripts.OnEnter(row)
    equal(h.details.title:GetText(), "Centerville")
    equal(GameTooltip:IsShown(), false)
    equal(GameTooltip.owner, nil)
    equal(GameTooltip.showCount or 0, tooltipShows)
    row.scripts.OnLeave(row)
    equal(GameTooltip:IsShown(), false)
    h:idleFooter()
    h.launcher.scripts.OnEnter(h.launcher)
    equal(GameTooltip.text, "Preflight Forever")
    equal(GameTooltip:IsShown(), true)
    local check = h:one(function(item) return item.kind == "CheckButton" end)
    check:SetChecked(false)
    check.scripts.OnClick(check)
    equal(h.ns.db.autoDepart, false)
end)

test("known list excludes the origin and unknown pins stay red despite an old queue", function()
    local h = harness()
    h:preview()
    h.ns.preview.nodes[3].learned = nil
    h.ns.db.learned[30] = nil
    h.ns.db.queue = { sourceID = 10, destinationID = 30, mapID = 1415,
        sourceName = "Origin", destinationName = "Northwatch" }
    h:render()
    equal(#h:rows(), 1)
    equal(h:rows()[1].node.id, 20)
    for _, row in ipairs(h:rows()) do assert(row.node.id ~= 10 and row.node.id ~= 30) end
    local unknown = h:one(function(item) return item.kind == "Button" and item.node and item.icon and item.node.id == 30 end)
    equal(unknown.width, 17)
    equal(unknown:IsEnabled(), false)
    near(unknown.icon.vertexColor[1], 1)
    near(unknown.icon.vertexColor[2], 0.18)
    near(unknown.icon.vertexColor[3], 0.16)
end)

test("hover draws each cached hop and directional arrowheads through intermediate stops", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    equal(GameTooltip:IsShown(), false)
    equal(GameTooltip.owner, nil)
    equal(h.details.title:GetText(), "Centerville")
    local lines = h:routeLines()
    assert(#lines > 6)
    equal(lines[1].layer, "OVERLAY")
    near(lines[1].startPoint[3], 0.2 * 628)
    near(lines[1].startPoint[4], -0.2 * 408.2)
    near(lines[1].endPoint[3], 0.4 * 628)
    near(lines[1].endPoint[4], -0.1 * 408.2)
    local firstDX = lines[1].endPoint[3] - lines[1].startPoint[3]
    local firstDY = lines[1].endPoint[4] - lines[1].startPoint[4]
    for index = 2, 3 do
        local arrow = lines[index]
        local dx = arrow.endPoint[3] - arrow.startPoint[3]
        local dy = arrow.endPoint[4] - arrow.startPoint[4]
        assert(dx * firstDX + dy * firstDY > 0, "arrowhead points backwards")
    end
    local finalHop = h:one(function(item) return item.kind == "Line" and item.shown
        and math.abs(item.startPoint[3] - 0.4 * 628) < 0.000001
        and math.abs(item.startPoint[4] + 0.1 * 408.2) < 0.000001
        and math.abs(item.endPoint[3] - 0.8 * 628) < 0.000001
        and math.abs(item.endPoint[4] + 0.8 * 408.2) < 0.000001 end)
    equal(finalHop.thickness, 2)
    assert(h:footerHas("Route: Origin > Northwatch > Centerville"))
    assert(h:footerHas("Flight time: ~2m 00s"))
    assert(h:footerHas("Recorded flight"))
end)

test("database time is labeled and adjusted for the active flight speed perk", function()
    local h = harness()
    h:preview()
    h:recordRoute()
    h.databaseDuration, h.databaseSource, h.speedFactor = 145, "Bundled database estimate", 1.2
    local pin = h:one(function(item) return item.kind == "Button" and item.node and item.icon and item.node.id == 20 end)
    pin.scripts.OnEnter(pin)
    assert(h:footerHas("Flight time: ~2m 01s"))
    assert(h:footerHas("Bundled database estimate"))
    equal(h.lookupArgs[1], 2)
    equal(h.lookupArgs[2], 1415)
    equal(h.lookupArgs[3], 10)
    equal(h.lookupArgs[4], 20)
    equal(h.lookupArgs[5].key, "10:30:20")
    assert(#h:routeLines() > 0)
end)

test("recorded time takes precedence over the database and is speed adjusted", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    h.databaseDuration, h.databaseSource, h.speedFactor = 300, "Database estimate", 1.2
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    equal(h.lookupCalls, 0)
    assert(h:footerHas("Flight time: ~1m 40s"))
    assert(h:footerHas("Recorded flight"))
end)

test("first hover draws estimated bundled hops before any native map has been visited", function()
    local h = harness()
    h:preview()
    local nodes = h.ns.preview.nodes
    local calls = 0
    h.ns.Routes = { Estimate = function(preview, sourceID, destinationID)
        calls = calls + 1
        equal(preview, h.ns.preview)
        equal(sourceID, 10)
        equal(destinationID, 20)
        return { key = "10:30:20", points = { nodes[1], nodes[3], nodes[2] }, estimated = true }
    end }
    equal(next(h.ns.db.maps), nil)
    h.databaseDuration, h.databaseSource = 145, "Bundled database estimate"
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    equal(calls, 1)
    assert(#h:routeLines() > 6)
    assert(h:footerHas("Estimated route: Origin > Northwatch > Centerville"))
    assert(h:footerHas("Flight time: ~2m 25s"))
    equal(h.lookupArgs[5].estimated, true)
    row.scripts.OnLeave(row)
    equal(#h:routeLines(), 0)

    h:recordRoute(120)
    row.scripts.OnEnter(row)
    equal(calls, 1, "native routes should take priority")
    assert(h:footerHas("Route: Origin > Northwatch > Centerville"))
    assert(h:footerHas("Recorded flight"))
    assert(not h:footerHas("Estimated route: Origin > Northwatch > Centerville"))
end)

test("missing route and time show honest guidance without invented arrows", function()
    local h = harness()
    h:preview()
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    equal(#h:routeLines(), 0)
    assert(h:footerHas("Flight time: not recorded yet"))
    assert(h:footerHas("No connected route is available in the bundled data. Open Origin's flight map to record it."))
    h.databaseDuration, h.databaseSource = 99, "Database estimate"
    row.scripts.OnEnter(row)
    assert(h:footerHas("Flight time: ~1m 39s"))
    equal(#h:routeLines(), 0)
end)

test("new knowledge replaces a stale native chain with an estimated route and new timing", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    h.ns.db.learned[40] = true -- A new known point can change the chosen network.
    local nodes = h.ns.preview.nodes
    local estimated = { key = "10:20", points = { nodes[1], nodes[2] }, estimated = true }
    h.ns.Routes = { Estimate = function() return estimated end }
    h.databaseDuration, h.databaseSource = 75, "Updated database estimate"
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    assert(h:footerHas("Estimated route: Origin > Centerville"))
    assert(h:footerHas("Flight time: ~1m 15s"))
    assert(not h:footerHas("Recorded flight"))
    equal(h.lookupArgs[5], estimated)
    assert(#h:routeLines() > 0)
    -- Drawing a new estimate must not rewrite the historical observation.
    equal(h.ns.db.maps[1415].origins[10].routes[20].key, "10:30:20")
    equal(h.ns.db.maps[1415].origins[10].routes[20].duration, 120)
end)

test("a stale capture retains personal timing when the estimated stop chain still matches", function()
    local h = harness()
    h:preview()
    h.ns.db.clientBuild = "old-client"
    h:recordRoute(120)
    h.ns.db.clientBuild = "new-client"
    local nodes = h.ns.preview.nodes
    h.ns.Routes = { Estimate = function()
        return { key = "10:30:20", points = { nodes[1], nodes[3], nodes[2] }, estimated = true }
    end }
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    assert(h:footerHas("Estimated route: Origin > Northwatch > Centerville"))
    assert(h:footerHas("Flight time: ~2m 00s"))
    assert(h:footerHas("Recorded flight"))
    equal(h.lookupCalls, 0)
end)

test("a stale capture without a connected estimate is clearly labeled as previously recorded", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    h.ns.db.learned[40] = true
    h.ns.Routes = { Estimate = function() return nil end }
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    assert(h:footerHas("Previously recorded route: Origin > Northwatch > Centerville"))
    assert(h:footerHas("Revisit this flight master to refresh the recorded route."))
    assert(h:footerHas("Flight time: ~2m 00s"))
    assert(#h:routeLines() > 0)
end)

test("hover remains on the same visible pin through periodic renders", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    h.ns.UI.Show()
    local pin = h:one(function(item) return item.kind == "Button" and item.node and item.icon and item.node.id == 20 end)
    pin.scripts.OnEnter(pin)
    local hidden = pin.hideCount or 0
    local count = #h:routeLines()
    h.window.scripts.OnUpdate(h.window, 2.1)
    equal(pin.hideCount or 0, hidden)
    equal(#h:routeLines(), count)
    equal(h.details.title:GetText(), "Centerville")
    equal(GameTooltip.owner, nil)
    equal(GameTooltip:IsShown(), false)
    assert(h:footerHas("Route: Origin > Northwatch > Centerville"))
end)

test("leaving a node and hiding the planner clear route and footer details", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    h.ns.UI.Show()
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    assert(#h:routeLines() > 0)
    row.scripts.OnLeave(row)
    equal(#h:routeLines(), 0)
    equal(GameTooltip:IsShown(), false)
    h:idleFooter()
    row.scripts.OnEnter(row)
    h.ns.UI.Hide()
    equal(#h:routeLines(), 0)
    equal(GameTooltip:IsShown(), false)
    h:idleFooter()
    h.ns.UI.Show()
    row.scripts.OnEnter(row)
    h.window:Hide() -- Escape invokes the frame's OnHide rather than UI.Hide.
    equal(#h:routeLines(), 0)
    equal(GameTooltip:IsShown(), false)
    h:idleFooter()
end)

test("a filtered or repurposed hover target clears the previous route", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    assert(#h:routeLines() > 0)
    local search = h:one(function(item) return item.kind == "EditBox" end)
    search:SetText("North")
    equal(#h:routeLines(), 0)
    equal(GameTooltip:IsShown(), false)
    h:idleFooter()
    equal(h:rows()[1].node.id, 30)
end)

test("unknown hover clears known route and never looks up a flight time", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    h.ns.preview.nodes[3].learned = false
    h.ns.db.learned[30] = nil
    h:render()
    local unknown = h:one(function(item) return item.kind == "Button" and item.node and item.icon and item.node.id == 30 end)
    local lookups = h.lookupCalls
    unknown.scripts.OnEnter(unknown)
    equal(#h:routeLines(), 0)
    equal(h.lookupCalls, lookups)
    assert(h:footerHas("Unknown flight point"))
    assert(not h:footerHas("Flight time: not recorded yet"))
end)

test("loss of art or preview removes old route lines without leaving stale graphics", function()
    local h = harness()
    h:preview()
    h:recordRoute(120)
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    h.textures = {}
    h:render()
    equal(#h:routeLines(), 0)
    assert(h:footerHas("Flight time: ~2m 00s"))
    h.ns.preview = nil
    h:render()
    equal(#h:routeLines(), 0)
    equal(GameTooltip:IsShown(), false)
    h:idleFooter()
end)

test("player is the world map arrow, turned to the character's facing", function()
    local h = harness()
    local arrow = h:one(function(item) return item.atlas == "UI-WorldMapArrow" end)
    local pin = arrow.parent
    equal(arrow.colorTexture, nil)
    equal(pin.scripts.OnUpdate ~= nil, true)
    h.facing = math.pi / 2
    h:preview()
    equal(pin:IsShown(), true)
    local point = pin.points[#pin.points]
    equal(point[1], "CENTER")
    near(point[4], 0.21 * point[2]:GetWidth())
    near(point[5], -0.22 * point[2]:GetHeight())
    near(arrow.rotation, math.pi / 2)
    h.facing = 2
    pin.scripts.OnUpdate(pin, 0.016)
    near(arrow.rotation, 2)
    h.facing = nil
    pin.scripts.OnUpdate(pin, 0.016)
    near(arrow.rotation, 2)
    h.ns.preview = nil
    h:render()
    equal(pin:IsShown(), false)
end)

test("player arrow falls back to the minimap arrow without the world map atlas", function()
    local h = harness({ noAtlas = true })
    local arrow = h:one(function(item) return item.texture == "Interface\\Minimap\\MinimapArrow" end)
    equal(arrow.atlas, nil)
    h.facing = 1
    h:preview()
    near(arrow.rotation, 1)
end)

test("an undiscovered closest flight point is the departure", function()
    local h = harness()
    h:preview()
    local origin = h.ns.preview.nodes[1]
    origin.learned, origin.locked, h.ns.db.learned[10] = false, true, nil
    h.ns.origin, h.ns.distance = h.ns.Model.FindNearest(h.ns.preview.nodes, h.ns.preview.player, 2)
    equal(h.ns.origin, origin)
    h:render()
    assert(h:hasText("Closest: Origin (undiscovered)  ~" .. math.floor(h.ns.distance + 0.5) .. " yd"))
    local pin = h:one(function(item) return item.kind == "Button" and item.node == origin and item.icon end)
    pin.scripts.OnEnter(pin)
    equal(h.details.time:GetText(), "Closest flight master (undiscovered)")
    assert(h:footerHas("Flights leave from here."))
    pin.scripts.OnLeave(pin)
    -- The real estimator must draw arrows from the undiscovered departure.
    h.ns.RouteEdges = { 10, 20, 500 }
    assert(loadfile("Routes.lua"))("PreflightForever", h.ns)
    local row = h:rows()[1]
    row.scripts.OnEnter(row)
    assert(#h:routeLines() > 0)
    assert(h:footerHas("Estimated route: Origin > Centerville"))
    row.scripts.OnLeave(row)
    h:click(row)
    equal(h.ns.db.queue.sourceID, 10)
end)

test("the button counts down a flight over its dimmed icon", function()
    local h = harness()
    local remaining
    h.ns.Tracker = { Remaining = function() return remaining end }
    local countdown = h.launcher.countdown
    equal(countdown:IsShown(), false)
    h.launcher.scripts.OnUpdate(h.launcher, 0.1)
    equal(countdown:IsShown(), false)
    remaining = 83.2
    h.launcher.scripts.OnUpdate(h.launcher, 0.1)
    equal(countdown:IsShown(), true)
    equal(countdown:GetText(), "1:24")
    near(h.launcher.icon.vertexColor[1], 0.45)
    remaining = 0
    h.launcher.scripts.OnUpdate(h.launcher, 0.1)
    equal(countdown:GetText(), "0:00")
    remaining = nil
    h.launcher.scripts.OnUpdate(h.launcher, 0.1)
    equal(countdown:IsShown(), false)
    near(h.launcher.icon.vertexColor[1], 1)
end)

test("the button shows a wind rider for Horde and a gryphon otherwise", function()
    local gryphon, wyvern = "Interface\\Icons\\Ability_Mount_Gryphon_01", "Interface\\Icons\\Ability_Mount_Wyvern_01"
    local h = harness()
    equal(h.launcher.icon.texture, gryphon)
    h:preview()
    equal(h.launcher.icon.texture, gryphon)
    h.ns.preview.faction = 1
    h:render()
    equal(h.launcher.icon.texture, wyvern)
    GetFileIDFromPath = function() return nil end
    h:render()
    equal(h.launcher.icon.texture, gryphon)
    GetFileIDFromPath = nil
    h.ns.preview = nil
    h.ns.API.Faction = function() return 1 end
    h:render()
    equal(h.launcher.icon.texture, wyvern)
    h.ns.API.Faction = function() return 2 end
    h:render()
    equal(h.launcher.icon.texture, gryphon)
end)

print(string.format("%d UI smoke tests passed", passed))
