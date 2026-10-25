-- Geometry hot paths, all five anchor modes and both axes/reverse directions.
-- <root> [pre-split Prediction.lua]: optional baseline is measurement-only.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local base = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return source
end
local anchor = { LEFT = 1, RIGHT = 2, FOLLOW_HP = 3, FOLLOW_HP_OVERFLOW = 4, REVERSE_FROM_MAX = 5 }
local natives = 0
local methods = {}
for _, name in ipairs({ "ClearAllPoints", "SetPoint", "SetAllPoints", "SetClipsChildren", "EnableMouse" }) do
    methods[name] = function() natives = natives + 1 end
end
for _, entry in ipairs({ { "Parent", "parent" }, { "FrameLevel", "level" }, { "FrameStrata", "strata" },
    { "Width", "width" }, { "Height", "height" }, { "ReverseFill", "reverse" }, { "Orientation", "orientation" } }) do
    local field = entry[2]
    methods["Get" .. entry[1]] = function(self) natives = natives + 1; return self[field] end
    methods["Set" .. entry[1]] = function(self, value) natives = natives + 1; self[field] = value end
end
methods.GetStatusBarTexture = function(self) natives = natives + 1; return self.texture end
methods.HookScript = function(self, _, callback) natives = natives + 1; self.sizeChanged = callback end
local mt = { __index = methods }
local function Widget(_, _, parent)
    return setmetatable({ parent = parent, width = 200, height = 30, strata = "MEDIUM", level = 5, texture = {} }, mt)
end
local ns = { UFModuleFactories = {}, UF = { Shared = { ABSORB_ANCHOR = anchor } } }
local env = setmetatable({ CreateFrame = Widget, issecretvalue = function() return false end }, { __index = _G })
local layout, path
local names = { "LayoutBarIfNeeded", "LayoutHealAbsorbBar", "EnsureHpGeometryHook", "NormalizeAnchorMode", "ReverseForMode" }
if arg[2] then
    path = arg[2]
    local source = Read(path)
    local first = assert(source:find("local function NormalizeAnchorMode(", 1, true))
    local last = assert(source:find("local function HideBar(", first, true))
    local a = assert(source:find("-- SetParent resets a frame's strata", 1, true))
    local b = assert(source:find("local function MixedFollowNeedsClamp(", a, true))
    local exports = {}
    for _, name in ipairs(names) do exports[#exports + 1] = name .. "=" .. name end
    local header = "local ABSORB_ANCHOR, PixelLayoutRegion = ...\n"
        .. "local FOLLOW_HP,FOLLOW_HP_OVERFLOW=ABSORB_ANCHOR.FOLLOW_HP,ABSORB_ANCHOR.FOLLOW_HP_OVERFLOW\n"
        .. "local CreateFrame,issecretvalue,tonumber=CreateFrame,issecretvalue,tonumber\n"
    local chunk = assert(loadstring(header .. source:sub(first, last - 1) .. source:sub(a, b - 1)
        .. "\nreturn {" .. table.concat(exports, ",") .. "}", "@" .. path))
    setfenv(chunk, env)
    layout = chunk(anchor, function(f) return f end)
else
    path = base .. "MSUF_UF_Prediction_Layout.lua"
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("test", ns)
    layout = ns.UFModuleFactories.PredictionLayout(function(f) return f end)
end
local items = {}
for mode = 1, 5 do
    for _, vertical in ipairs({ false, true }) do
        for _, reverse in ipairs({ false, true }) do
            local frame = Widget()
            frame.hpBar = Widget()
            frame._msufPredictionVertical, frame._msufPredictionHpReverse = vertical, reverse
            frame._msufPredictionFrameWidth = 200
            local bar, healAbsorb, follow = Widget(), Widget(), Widget()
            items[#items + 1] = { frame, bar, healAbsorb, follow, mode, layout.ReverseForMode(mode, reverse) }
            layout.EnsureHpGeometryHook(frame.hpBar)
        end
    end
end
local function Batch(resize)
    for _, item in ipairs(items) do
        local frame, bar, healAbsorb, follow, mode, reverse = unpack(item)
        if resize then frame.hpBar.sizeChanged(frame.hpBar) end
        layout.LayoutBarIfNeeded(frame, bar, 2, mode, reverse, follow, 0, 0)
        layout.LayoutHealAbsorbBar(frame, healAbsorb, 3, frame._msufPredictionHpReverse, mode, 0, 0)
    end
end
for _, resize in ipairs({ false, true }) do
    Batch(resize)
    Batch(resize)
    local instructions, calls = 0, 0
    natives = 0
    debug.sethook(function(event)
        if debug.getinfo(2, "S").source == "@" .. path then
            if event == "count" then instructions = instructions + 1 end
            if event == "call" then calls = calls + 1 end
        end
    end, "c", 1)
    for _ = 1, 50 do Batch(resize) end
    debug.sethook()
    local count, nativeCount = #items * 50, natives
    local kb = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 50 do Batch(resize) end
        kb = math.min(kb, (collectgarbage("count") - before) / count)
        collectgarbage("restart")
    end
    print(string.format("layout %s: %.3f instructions, %.3f calls, %.3f natives, %.6f KB/item",
        resize and "resize" or "warm", instructions / count, calls / count, nativeCount / count, kb))
    local budget = resize and { 298, 11.6, 8.2 } or { 279, 10.6, 6.2 }
    assert(instructions / count <= budget[1] and calls / count <= budget[2] and nativeCount / count <= budget[3],
        "layout exceeded the pre-split instruction/call/native budget")
    assert(kb == 0, "layout allocated on a warm update")
end
print("PASS uf_prediction_layout_budget: 20 geometries; cache reuse and resize invalidation")
