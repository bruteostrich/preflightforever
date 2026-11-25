local ns = {}
assert(loadfile("RoutesData.lua"))("PreflightForever", ns)
assert(loadfile("Routes.lua"))("PreflightForever", ns)
local Routes = ns.Routes
local passed = 0
local function test(name, run)
    local ok, err = pcall(run)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("ok - " .. name)
end
local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function fixture(ids)
    local preview = { mapID = 1415, faction = 2, player = { instanceID = 0 }, nodes = {} }
    for i, id in ipairs(ids) do
        preview.nodes[#preview.nodes + 1] = { id = id, name = "Point " .. id,
            learned = true, faction = 2, instanceID = 0, x = i / 20, y = i / 20 }
    end
    return preview
end

test("bundled graph contains the installed Forever build's 286 ordinary directed links", function()
    equal(ns.RouteDataBuild, "1.60.1.71091")
    equal(ns.RouteDataNodeCount, 65)
    equal(#ns.RouteEdges, 286 * 3)
    local seen = {}
    for i = 1, #ns.RouteEdges, 3 do
        local a, b, d = ns.RouteEdges[i], ns.RouteEdges[i + 1], ns.RouteEdges[i + 2]
        assert(a > 0 and b > 0 and a ~= b and d > 0 and d < math.huge)
        local key = a .. ":" .. b
        assert(not seen[key], key)
        seen[key] = true
        local metadata = assert(ns.RouteEdgeInfo[a][b])
        assert(metadata.pathID > 0 and metadata.cost >= 0)
    end
end)

test("fresh character cache can preview a real multihop route", function()
    local preview = fixture({ 7, 6, 2, 12 })
    local route = assert(Routes.Estimate(preview, 7, 12))
    equal(route.key, "7:6:2:12")
    equal(route.estimated, true)
    equal(route.distance, 2658 + 6310 + 3480)
    equal(route.duration, nil)
    equal(route.points[2].name, "Point 6")
    equal(route.points[2].x, preview.nodes[2].x)
end)

test("unknown intermediate point cannot be used", function()
    local preview = fixture({ 7, 6, 2, 12 })
    preview.nodes[2].learned = false
    equal(Routes.Estimate(preview, 7, 12), nil)
end)

test("unknown or locked endpoints cannot be used", function()
    local preview = fixture({ 2, 4 })
    preview.nodes[1].learned = false
    equal(Routes.Estimate(preview, 2, 4), nil)
    preview.nodes[1].learned = true
    preview.nodes[2].locked = true
    equal(Routes.Estimate(preview, 2, 4), nil)
end)

test("chooses a shorter available sequence without inventing an edge", function()
    local route = assert(Routes.Estimate(fixture({ 7, 6, 2, 12, 14, 16 }), 7, 12))
    equal(route.key, "7:6:2:12")
end)

test("Forever Farholde links are included", function()
    local route = assert(Routes.Estimate(fixture({ 3276, 5, 2 }), 3276, 2))
    equal(route.key, "3276:5:2")
    equal(route.distance, 3917 + 3374)
end)

test("opposite faction neutral connector does not expose hostile paths", function()
    local preview = fixture({ 79, 40, 25 })
    preview.mapID, preview.player.instanceID = 1414, 1
    for _, node in ipairs(preview.nodes) do node.instanceID = 1 end
    preview.nodes[1].faction = 0
    preview.nodes[2].faction, preview.nodes[3].faction = 1, 1
    equal(Routes.Estimate(preview, 79, 25), nil)
    preview.faction = 1
    equal(assert(Routes.Estimate(preview, 79, 25)).key, "79:40:25")
end)

test("class-only Nighthaven services are excluded from the ordinary graph", function()
    equal(Routes.Estimate(fixture({ 62, 27 }), 62, 27), nil)
    equal(Routes.Estimate(fixture({ 63, 22 }), 63, 22), nil)
end)

test("a direct flight takes precedence over a shorter chain and edges stay directed", function()
    local saved = ns.RouteEdges
    ns.RouteEdges = { 2, 4, 100, 2, 5, 10, 5, 4, 10 }
    local route = assert(Routes.Estimate(fixture({ 2, 4, 5 }), 2, 4))
    equal(route.key, "2:4")
    equal(route.distance, 100)
    equal(route.direct, true)
    equal(Routes.Estimate(fixture({ 2, 4, 5 }), 4, 2), nil)
    ns.RouteEdges = saved
end)

test("ordinary free flights are retained because fare is not flight distance", function()
    equal(ns.RouteEdgeInfo[26][27].cost, 0)
    equal(ns.RouteEdgeInfo[27][26].cost, 0)
    equal(assert(Routes.Estimate(fixture({ 26, 27 }), 26, 27)).key, "26:27")
    equal(assert(Routes.Estimate(fixture({ 26, 27 }), 27, 26)).key, "27:26")
end)

test("native comparison counts matches differences and missing estimates without altering routes", function()
    local preview = fixture({ 2, 4, 5, 9000 })
    local live = { mapID = 1415, sourceID = 2, nodes = {
        { id = 4, state = "REACHABLE", route = { key = "2:4" } },
        { id = 5, state = "REACHABLE", route = { key = "2:4:5" } },
        { id = 9000, state = "REACHABLE", route = { key = "2:9000" } },
        { id = 4, state = "UNREACHABLE", route = { key = "2:4" } },
    } }
    local report = assert(Routes.Compare(preview, live))
    equal(report.compared, 3)
    equal(report.matched, 1)
    equal(report.different, 1)
    equal(report.unavailable, 1)
    equal(report.differences[5].native, "2:4:5")
    equal(report.differences[5].estimated, "2:5")
    equal(live.nodes[2].route.key, "2:4:5")
    equal(Routes.Compare(preview, { mapID = 1414, sourceID = 2, nodes = live.nodes }), nil)
end)

test("missing graph link returns no fabricated straight line", function()
    equal(Routes.Estimate(fixture({ 7, 12 }), 7, 12), nil)
    equal(Routes.Estimate(fixture({ 2, 9000 }), 2, 9000), nil)
end)

test("transition special or other instance intermediates are excluded", function()
    for _, field in ipairs({ "transition", "special", "instanceID" }) do
        local preview = fixture({ 7, 6, 2, 12 })
        preview.nodes[2][field] = field == "instanceID" and 1 or true
        equal(Routes.Estimate(preview, 7, 12), nil)
    end
end)

test("invalid coordinates and duplicate IDs do not draw misleading geometry", function()
    local preview = fixture({ 7, 6, 2, 12 })
    preview.nodes[2].x = 1.1
    equal(Routes.Estimate(preview, 7, 12), nil)
    preview = fixture({ 7, 6, 2, 12, 6 })
    equal(Routes.Estimate(preview, 7, 12), nil)
end)

test("returns independent route points without mutating preview", function()
    local preview = fixture({ 2, 4 })
    local route = assert(Routes.Estimate(preview, 2, 4))
    route.points[1].x = 0.99
    equal(preview.nodes[1].x, 0.05)
    equal(preview.nodes[1].route, nil)
end)

test("invalid requests are rejected", function()
    equal(Routes.Estimate(nil, 2, 4), nil)
    equal(Routes.Estimate({}, 2, 4), nil)
    equal(Routes.Estimate(fixture({ 2, 4 }), 2, 2), nil)
    equal(Routes.Estimate(fixture({ 2, 4 }), "2", 4), nil)
    equal(Routes.Estimate(fixture({ 2, 4 }), 2, math.huge), nil)
end)

test("nonfinite or negative weights cannot enter a route", function()
    local saved = ns.RouteEdges
    for _, value in ipairs({ math.huge, -1, 0, 0/0 }) do
        ns.RouteEdges = { 2, 4, value }
        equal(Routes.Estimate(fixture({ 2, 4 }), 2, 4), nil)
    end
    ns.RouteEdges = saved
end)

print("Passed " .. passed .. " route tests")
