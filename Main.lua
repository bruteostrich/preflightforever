local addonName, ns = ...
local M, A = ns.Model, ns.API
local events = CreateFrame("Frame")
ns.events = events
ns.version = "0.3.5"
local session = 0

function ns.Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffcf70Preflight Forever:|r " .. message) end
end

function ns.Refresh()
    if not ns.db then return end
    local preview, reason = A.GetPreview(ns.db)
    ns.preview = preview
    ns.origin, ns.distance = nil, nil
    if preview then
        ns.origin, ns.distance = M.FindNearest(preview.nodes, preview.player, preview.faction)
    end
    ns.UI.Render(preview, ns.origin, ns.distance, reason)
    local known, total = 0, 0
    for _, node in ipairs(preview and preview.nodes or {}) do
        total = total + 1
        if node.learned == true then known = known + 1 end
    end
    -- Keep map/art identifiers and counts for diagnosing actual client data.
    ns.db.lastDiagnostics = { version = ns.version, mapID = preview and preview.mapID,
        known = known, total = total, needsFlightSync = preview and preview.needsFlightSync,
        unverified = preview and preview.unverifiedCount, remoteKnown = preview and preview.remoteKnownCount,
        art = ns.UI.GetMapDiagnostics and ns.UI.GetMapDiagnostics() or nil, reason = reason }
end

local function recordTaxiSnapshot(live)
    M.RecordSnapshot(ns.db, live, time())
    if ns.Tracker then ns.Tracker.SetSnapshot(live) end
    ns.Refresh()
    if ns.Routes and ns.Routes.Compare then
        local report = ns.Routes.Compare(ns.preview, live)
        if report then
            report.clientBuild, report.seenAt = ns.db.clientBuild, time()
            ns.db.lastRouteAudit = report
        end
    end
end

function ns.Toggle()
    if not ns.db then return end
    ns.UI.Toggle()
end

function ns.Cancel()
    if not ns.db or not ns.db.queue then return end
    ns.db.queue, ns.attempt = nil, nil
    ns.Print("Queued flight cleared.")
    ns.Refresh()
end

function ns.Queue(destination)
    if not ns.preview or not ns.origin then return end
    local allowed, problem = M.CanPlan(ns.origin, destination)
    if not allowed then ns.Print(problem); return end
    local queue, reason = M.NewQueue(ns.origin, destination, ns.preview.mapID, time())
    if not queue then ns.Print(reason); return end
    ns.db.queue, ns.attempt = queue, nil
    ns.Print("Queued " .. queue.destinationName .. " from " .. queue.sourceName .. ".")
    ns.Refresh()
end

local function finishAttempt(attempt, tries)
    if ns.attempt ~= attempt then return end
    if A.Context().onTaxi == true then
        if ns.db.queue == attempt.queue then ns.db.queue = nil end
        ns.attempt = nil
        ns.Print("Departing for " .. attempt.queue.destinationName .. ".")
        ns.UI.Hide()
        ns.Refresh()
    elseif tries < 15 then
        C_Timer.After(0.2, function() finishAttempt(attempt, tries + 1) end)
    else
        ns.attempt = nil
        ns.Print("Departure was not confirmed. Your destination is still queued; select it on the flight map or speak to the flight master again.")
        ns.Refresh()
    end
end

function ns.Depart()
    if not ns.taxiOpen or not ns.db.queue or ns.attempt then return end
    -- Slots, reachability and fare are read again immediately before taking off.
    local live, reason = A.GetLive()
    if not live then ns.Print(reason or "The flight map is not ready."); return end
    ns.live = live
    recordTaxiSnapshot(live)
    local node
    node, reason = M.ResolveQueue(ns.db.queue, live, A.Context())
    if not node then ns.Print(reason); return end
    local attempt = { queue = ns.db.queue }
    ns.attempt = attempt
    if ns.Tracker then
        ns.Tracker.BeforeTake(live, node.slot)
    end
    local ok
    ok, reason = A.Take(node)
    if not ok then
        ns.attempt = nil
        if ns.Tracker then ns.Tracker.CancelPending() end
        ns.Print(reason or "The client could not start that flight. Your destination is still queued.")
        return
    end
    finishAttempt(attempt, 0)
end

local function readTaxiMap(token, tries, skip)
    if token ~= session or not ns.taxiOpen then return end
    local live, reason = A.GetLive()
    if not live then
        if tries < 10 then
            C_Timer.After(0.1, function() readTaxiMap(token, tries + 1, skip) end)
        elseif ns.db.queue then
            ns.Print(reason or "Flight data is unavailable. Your destination is still queued.")
        end
        return
    end
    ns.live = live
    recordTaxiSnapshot(live)
    if not ns.db.queue then return end
    if skip then
        ns.Print("Automatic departure skipped while Shift is held. Your destination is still queued.")
        return
    end
    local node
    node, reason = M.ResolveQueue(ns.db.queue, live, A.Context())
    if not node then ns.Print(reason); return end
    if ns.db.autoDepart then
        ns.Depart()
    else
        ns.UI.Show()
        ns.Print("Your queued flight is ready. Click Depart now to take it.")
    end
end

local function onEvent(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= addonName then return end
        PreflightDB = type(PreflightDB) == "table" and PreflightDB or {}
        ns.db = PreflightDB
        ns.db.clientBuild = A.GetBuildKey and A.GetBuildKey() or nil
        M.InitializeKnowledge(ns.db)
        ns.db.version = 4
        if type(ns.db.autoDepart) ~= "boolean" then ns.db.autoDepart = true end
        local savedQueue = ns.db.queue
        ns.db.queue = nil
        -- The departure may still be undiscovered; the destination must be known.
        if type(savedQueue) == "table" and ns.db.learned[savedQueue.destinationID] == true then
            ns.db.queue = M.NewQueue({ id = savedQueue.sourceID, name = savedQueue.sourceName },
                { id = savedQueue.destinationID, name = savedQueue.destinationName }, savedQueue.mapID, savedQueue.createdAt)
        end
        if ns.Tracker then ns.Tracker.Init(ns.db) end
        ns.UI.Init()
        events:UnregisterEvent("ADDON_LOADED")
    elseif not ns.db then
        return
    elseif event == "TAXIMAP_OPENED" then
        session = session + 1
        ns.taxiOpen, ns.live = true, nil
        local skip = IsShiftKeyDown()
        local token = session
        -- Wait until Blizzard has populated the current taxi interaction.
        C_Timer.After(0.1, function() readTaxiMap(token, 0, skip) end)
    elseif event == "TAXIMAP_CLOSED" then
        session = session + 1
        ns.taxiOpen, ns.live = false, nil
        if ns.Tracker then ns.Tracker.CloseInteraction() end
        ns.Refresh()
    elseif event == "TAXI_NODE_STATUS_CHANGED" then
        if ns.taxiOpen then
            local live = A.GetLive()
            if live then
                ns.live = live
                recordTaxiSnapshot(live)
            end
        end
    elseif event == "GOSSIP_SHOW" then
        if ns.db.queue and ns.db.autoDepart and not IsShiftKeyDown() and A.OpenTaxiGossip then
            A.OpenTaxiGossip()
        end
    elseif event == "PLAYER_CONTROL_LOST" then
        if ns.attempt then finishAttempt(ns.attempt, 0) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        session = session + 1
        ns.taxiOpen, ns.live, ns.attempt = false, nil, nil
        if ns.Tracker then ns.Tracker.Reset() end
        ns.Refresh()
    end
end

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED", "GOSSIP_SHOW", "PLAYER_CONTROL_LOST" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", onEvent)

SLASH_PREFLIGHT1 = "/preflight"
SLASH_PREFLIGHT2 = "/pf"
SlashCmdList.PREFLIGHT = function(message)
    if not ns.db then return end
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "clear" then
        ns.Cancel()
    elseif command == "reset" then
        ns.UI.ResetPosition()
    elseif command == "auto" then
        ns.db.autoDepart = not ns.db.autoDepart
        ns.Print("Automatic departure " .. (ns.db.autoDepart and "enabled." or "disabled. Click Depart now when ready."))
        ns.Refresh()
    elseif command == "status" then
        local queue = ns.db.queue
        ns.Print(queue and ("Queued " .. queue.destinationName .. " from " .. queue.sourceName .. ".") or "No flight queued.")
    elseif command == "debug" then
        ns.Refresh()
        local report = ns.db.lastDiagnostics
        local art = report.art or {}
        ns.Print("Version " .. ns.version .. "; map " .. tostring(report.mapID or "unavailable")
            .. "; known " .. report.known .. "/" .. report.total .. "; art " .. tostring(art.mode or "unavailable")
            .. "; tiles " .. tostring(art.textureCount or 0) .. "/" .. tostring(art.expectedTextures or 0) .. ".")
        ns.Print("Remote reports " .. tostring(report.remoteKnown or 0) .. " known; "
            .. tostring(report.unverified or 0) .. " points still need verification.")
        local audit = ns.db.lastRouteAudit
        if type(audit) == "table" then
            ns.Print("Last native route check at #" .. tostring(audit.sourceID) .. ": "
                .. tostring(audit.matched or 0) .. " matched, " .. tostring(audit.different or 0)
                .. " differed, " .. tostring(audit.unavailable or 0) .. " without an estimate ("
                .. tostring(audit.compared or 0) .. " native routes).")
        else
            ns.Print("No native route comparison recorded yet.")
        end
        if report.needsFlightSync then ns.Print("Open any flight master's normal map once to synchronize known destinations.") end
        if art.reason or report.reason then ns.Print(art.reason or report.reason) end
    elseif command == "" then
        ns.Toggle()
    else
        ns.Print("/pf opens the map; /pf clear cancels; /pf auto toggles automatic departure; /pf reset resets frame positions; /pf status shows the queue; /pf debug shows map diagnostics.")
    end
end
