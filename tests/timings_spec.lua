local ns = {}
assert(loadfile("Timings.lua"))("PreflightForever", ns)
local T = ns.Timings
local passed = 0

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
    local ok, message = pcall(run)
    if not ok then error(name .. ": " .. tostring(message), 0) end
    passed = passed + 1
    print("ok - " .. name)
end

test("Forever corrections override baseline Classic Era durations", function()
    equal(T.Lookup(1, 1414, 22, 80), 217)
    equal(T.Lookup(2, 1415, 4, 2), 82)
    equal(T.Lookup(1, 1414, 3203, 11), 582)
end)

test("numeric and named factions resolve the same baseline seconds", function()
    equal(T.Lookup(1, 1415, 10, 11), 112)
    equal(T.Lookup("Horde", 1415, 10, 11), 112)
    equal(T.Lookup("Alliance", 1415, 4, 2), 82)
    equal(T.Lookup(2, 1415, 10, 11), nil)
end)

test("direct endpoint durations are explicitly database estimates", function()
    local seconds, source = T.Lookup(1, 1415, 10, 11, { points = { { id = 10 }, { id = 13 }, { id = 11 } } })
    equal(seconds, 112)
    equal(source, "InFlight database estimate")
end)

test("a missing endpoint estimate can sum complete observed route legs", function()
    equal(T.Lookup(1, 1414, 25, 69), nil)
    local seconds, source = T.Lookup(1, 1414, 25, 69, { points = { { id = 25 }, { id = 22 }, { id = 69 } } })
    equal(seconds, 714)
    equal(source, "InFlight route-leg estimate")
end)

test("a route with an unknown leg does not yield a partial estimate", function()
    equal(T.Lookup(1, 1414, 25, 69, { points = { { id = 25 }, { id = 99999 }, { id = 69 } } }), nil)
    equal(T.Lookup(1, 1414, 25, 69, { points = { { id = 25 }, { id = 22 }, { id = 99999 }, { id = 69 } } }), nil)
end)

test("invalid routes and endpoint mismatches cannot produce timings", function()
    equal(T.Lookup(1, 1414, 25, 69, { points = { { id = 22 }, { id = 69 } } }), nil)
    equal(T.Lookup(1, 1414, 25, 69, { points = { { id = 25 }, { id = 22 } } }), nil)
    equal(T.Lookup(1, 1414, 25, 69, { points = { { id = 25 }, { id = 25 }, { id = 69 } } }), nil)
    equal(T.Lookup(1, 1414, 25, 69, { points = { { id = 25 }, "bad", { id = 69 } } }), nil)
end)

test("unknown nodes, other-era data and invalid identifiers remain unavailable", function()
    equal(T.Lookup(1, 1414, 99999, 11), nil)
    equal(T.Lookup(1, 1945, 99, 100), nil)
    equal(T.Lookup(0, 1415, 10, 11), nil)
    equal(T.Lookup(1, nil, 10, 11), nil)
    equal(T.Lookup(1, 1415, 10, 10), nil)
    equal(T.Lookup(1, 1415, 10.5, 11), nil)
end)

test("speed boosts are left to the caller and never baked into database values", function()
    local baseline = T.Lookup(1, 1415, 10, 11)
    equal(baseline, 112)
    local boosted = baseline / 1.2
    assert(boosted < baseline)
    equal(T.Lookup(1, 1415, 10, 11), 112)
end)

print(passed .. " timing database tests passed")
