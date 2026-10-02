-- castbar_pool_residue_smoke.lua <repoRoot> [print]
--
-- Boss and arena castbars are one pool module (MSUF_CastbarPools.lua). The
-- sites outside it that act on "every boss and arena castbar" walk the pools
-- (Pools.order, pool.Bar, pool.preview) instead of hand-written boss and
-- arena twins with their own slot counts and frame-name fallbacks:
--   Anchors   effective size of every pool bar, the unit-frame width source
--             (signature and OnSizeChanged/OnShow/OnHide hooks);
--   Driver    the cast-target text colour fan-out;
--   Rounded   the rounded-corner castbar walker;
--   Classic   the castbar spark visual compat (Game/Classic);
--   Core      the anchor unit frame and strata of a pool bar or preview.
-- This smoke loads the real castbar stack into tools/tests/castbar_world.lua
-- with every pool built and its previews shown, runs each site on Midnight
-- (3 arena slots), TBC/Mists (5) and Classic Era/WoW Forever (0), and compares
-- one call trace per widget with the trace recorded from the code before the
-- fold (2026-10-02, commit 5498ae81), section by section (length and a
-- rolling hash; the full trace is about 230 KB). Widgets are named by their
-- global name or the field path from a named frame; calls on widgets no path
-- reaches are compared as a sorted multiset. "print" prints the measured trace,
-- "sums" the section table below.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local mode = arg[2]
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()

local EXTRA = {
    "MSUF_Require.lua", "MSUF_Castbars_Core.lua", "MSUF_CastbarStyle.lua", "MSUF_CastbarFrames.lua",
    "MSUF_CastbarAnchors.lua", "MSUF_PlayerCastbarRuntime.lua", "MSUF_CastbarPreviewEdit.lua",
    "MSUF_CastbarPreviews.lua",
    "MSUF_CastbarVisuals.lua", "MSUF_CastbarPoolPreviews.lua", "MSUF_BossCastbars_Preview.lua",
    "MSUF_ArenaCastbars_Preview.lua", "MSUF_CastbarRounded.lua", "MSUF_CastbarVisualCompat.lua",
}

---------------------------------------------------------------------------
-- Recording: every capitalized method call on a world widget is logged.
---------------------------------------------------------------------------
local log = {}
local recording = false

local function Install(world)
    for index = 1, #world.frames do
        local widget = world.frames[index]
        if not rawget(widget, "_smokeWrapped") then
            rawset(widget, "_smokeWrapped", true)
            for key, value in pairs(widget) do
                if type(key) == "string" and key:match("^%u") and type(value) == "function" then
                    local original = value
                    widget[key] = function(self, ...)
                        if recording then log[#log + 1] = { self, key, ... } end
                        return original(self, ...)
                    end
                end
            end
            local mt = getmetatable(widget)
            local fallback = mt and mt.__index
            setmetatable(widget, { __index = function(self, key)
                local value = type(fallback) == "function" and fallback(self, key) or nil
                if type(value) == "function" and type(key) == "string" and key:match("^%u") then
                    return function(owner, ...)
                        if recording then log[#log + 1] = { owner, key, ... } end
                        return value(owner, ...)
                    end
                end
                return value
            end })
        end
    end
end

local function Labels(world)
    local labels, queue = {}, {}
    local function Visit(value, label, depth)
        if type(value) ~= "table" or not rawget(value, "_smokeWrapped") or labels[value] then return end
        labels[value] = label
        queue[#queue + 1] = { value, label, depth }
    end
    local named = {}
    for index = 1, #world.frames do
        local widget = world.frames[index]
        if type(widget.name) == "string" then named[#named + 1] = widget end
    end
    table.sort(named, function(a, b) return a.name < b.name end)
    for index = 1, #named do Visit(named[index], named[index].name, 0) end
    local head = 1
    while head <= #queue do
        local value, label, depth = queue[head][1], queue[head][2], queue[head][3]
        head = head + 1
        if depth < 4 then
            local keys = {}
            for key in pairs(value) do
                if type(key) == "string" and key ~= "scripts" and key ~= "hooks" and key ~= "events" then
                    keys[#keys + 1] = key
                end
            end
            table.sort(keys)
            for _, key in ipairs(keys) do Visit(rawget(value, key), label .. "." .. key, depth + 1) end
        end
    end
    return labels
end

local function Arg(value, labels)
    local kind = type(value)
    if kind == "number" then
        if value == math.floor(value) then return string.format("%d", value) end
        return string.format("%.4f", value)
    end
    if kind == "string" or kind == "boolean" or kind == "nil" then return tostring(value) end
    if kind == "table" then return labels[value] or (rawget(value, "_smokeWrapped") and "<widget>" or "<table>") end
    return "<" .. kind .. ">"
end

local function Trace(world)
    local labels = Labels(world)
    local per, order, loose = {}, {}, {}
    for index = 1, #log do
        local entry = log[index]
        local parts = { entry[2] }
        for argIndex = 3, table.maxn(entry) do parts[#parts + 1] = Arg(entry[argIndex], labels) end
        local line = table.concat(parts, " ")
        local label = labels[entry[1]]
        if label then
            if not per[label] then per[label] = {}; order[#order + 1] = label end
            per[label][#per[label] + 1] = line
        else
            loose[#loose + 1] = line
        end
    end
    table.sort(order)
    table.sort(loose)
    local out = {}
    for _, label in ipairs(order) do out[#out + 1] = label .. ": " .. table.concat(per[label], "; ") end
    if #loose > 0 then out[#out + 1] = "(unnamed): " .. table.concat(loose, "; ") end
    return table.concat(out, "\n")
end

local function Run(world, label, fn)
    Install(world)
    log = {}
    recording = true
    fn()
    recording = false
    Install(world)
    return label, Trace(world)
end

---------------------------------------------------------------------------
-- One client: pools built, previews shown, unit frames for every slot.
---------------------------------------------------------------------------
local function NewWorld(arenaSlots)
    local unitFrames = {}
    local rounded = {}
    local function Setup(ns, w)
        ns.UF = { frames = unitFrames, GetFrame = function(unit) return unitFrames[unit] end }
        ns.RoundedSurface = {
            ClearMasks = function(frame) rounded[#rounded + 1] = frame end,
            BeginMaskRefresh = function() end,
            EndMaskRefresh = function() end,
            MaskTextureWith = function() end,
        }
        w.rounded = rounded
        -- Font and media services the castbar visuals call (Runtime/ owns them).
        _G.MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
        _G.MSUF_SetFontChecked = function(fs, path, size, flags) fs:SetFont(path, size, flags) return true end
        _G.MSUF_GetFontPath = function() return "Fonts\FRIZQT__.TTF" end
        _G.MSUF_GetFontFlags = function() return "OUTLINE" end
        _G.MSUF_IsPlayerInCombat = function() return false end
        -- Kernel/MSUF_Util.lua providers the castbar previews require at load,
        -- equal to the fallbacks the castbar files use without them.
        _G.MSUF_SetTextIfChanged = function(fontString, text) fontString:SetText(text) end
        _G.MSUF_GetCastbarTimeFormat = function() return "CURRENT" end
        _G.MSUF_FormatCastbarTimeText = function(_, remaining) return string.format("%.1f", tonumber(remaining) or 0) end
    end
    local world = World.New(root, "timer", { pools = true, extra = EXTRA, arenaSlots = arenaSlots, setup = Setup, richWidgets = true })
    world.unitFrames = unitFrames
    for index = 1, 5 do
        unitFrames["boss" .. index] = world.NewWidget("Frame", "MSUF_boss" .. index)
    end
    for index = 1, arenaSlots do
        unitFrames["arena" .. index] = world.NewWidget("Frame", "MSUF_arena" .. index)
    end
    world.exists.boss2, world.exists.boss3, world.exists.boss4, world.exists.boss5 = true, true, true, true
    local general = _G.MSUF_DB.general
    general.castbarPlayerPreviewEnabled = true
    general.showBossCastTargetName = true
    general.showArenaCastTargetName = true
    _G.MSUF_DB.bars = { roundedFramesEnabled = true, roundedCastbars = true }
    _G.MSUF_ApplyBossCastbarsEnabled()
    _G.MSUF_ApplyArenaCastbarsEnabled()
    _G.MSUF_UnitEditModeActive = true
    _G.MSUF_UpdateBossCastbarPreview()
    _G.MSUF_UpdateArenaCastbarPreview()
    return world
end

local sections = {}

local function Scenario(arenaSlots)
    local world = NewWorld(arenaSlots)
    local general = _G.MSUF_DB.general
    local function Add(label, text)
        sections[#sections + 1] = { key = arenaSlots .. " slots: " .. label, text = text }
    end

    Add(Run(world, "effective size boss", function() _G.MSUF_ApplyCastbarEffectiveSizeUnit("boss") end))
    Add(Run(world, "effective size arena", function() _G.MSUF_ApplyCastbarEffectiveSizeUnit("arena") end))

    general.bossCastbarMatchWidth = "unitframe"
    general.arenaCastbarMatchWidth = "unitframe"
    Add(Run(world, "width source boss", function() _G.MSUF_UpdateCastbarWidthSourceSync(general, "boss") end))
    Add(Run(world, "width source arena", function() _G.MSUF_UpdateCastbarWidthSourceSync(general, "arena") end))
    Add(Run(world, "width source resize", function()
        for index = 1, 5 do
            local frame = world.unitFrames["boss" .. index]
            local hook = frame and frame.hooks.OnSizeChanged
            if hook then for _, fn in ipairs(hook) do fn(frame) end end
        end
        for index = 1, arenaSlots do
            local frame = world.unitFrames["arena" .. index]
            local hook = frame and frame.hooks.OnSizeChanged
            if hook then for _, fn in ipairs(hook) do fn(frame) end end
        end
        world:Advance(0.5)
    end))
    general.bossCastbarMatchWidth = nil
    general.arenaCastbarMatchWidth = nil

    -- A custom target-name colour makes the preview recolour observable.
    _G.MSUF_GetCastbarTargetNameColor = function() return 0.25, 0.5, 0.75, true end
    Add(Run(world, "cast target colours", function() _G.MSUF_RefreshAllCastTargetTextColors() end))
    _G.MSUF_GetCastbarTargetNameColor = nil

    Add(Run(world, "rounded on", function() world.ns.RoundedCastbarsApplyAll(true) end))
    Add(Run(world, "rounded off", function() world.ns.RoundedCastbarsApplyAll(false) end))

    Add(Run(world, "classic spark boss", function() _G.MSUF_ApplyCastbarVisualsForUnit("boss") end))
    Add(Run(world, "classic spark arena", function() _G.MSUF_ApplyCastbarVisualsForUnit("arena") end))

    Add(Run(world, "frame layer", function()
        for index = 1, 5 do _G.MSUF_ApplyCastbarFrameLayer(_G["MSUF_BossCastbar" .. index], general, "boss") end
        for index = 1, arenaSlots do _G.MSUF_ApplyCastbarFrameLayer(_G["MSUF_ArenaCastbar" .. index], general, "arena") end
        for index = 2, 5 do
            _G.MSUF_ApplyCastbarFrameLayer(_G["MSUF_BossCastbarPreview" .. index], general, "boss")
        end
        _G.MSUF_ApplyCastbarFrameLayer(_G.MSUF_BossCastbarPreview, general, "boss")
        for index = 1, arenaSlots do
            _G.MSUF_ApplyCastbarFrameLayer(_G["MSUF_ArenaCastbarPreview" .. index], general, "arena")
        end
    end))
end

Scenario(3)
Scenario(5)
Scenario(0)

-- Lua 5.1 numbers are doubles: every intermediate stays below 2^37.
local function Checksum(text)
    local hash = 0
    for index = 1, #text do hash = (hash * 31 + text:byte(index)) % 2147483647 end
    return string.format("%d:%d", #text, hash)
end

if mode == "print" then
    for _, section in ipairs(sections) do io.write("## ", section.key, "\n", section.text, "\n") end
    return
end
if mode == "sums" then
    for _, section in ipairs(sections) do
        io.write(string.format("    { %q, %q },\n", section.key, Checksum(section.text)))
    end
    return
end

-- Recorded from the boss/arena twins before the fold (commit 5498ae81).
local EXPECTED = {
    { "3 slots: effective size boss", "12151:898680211" },
    { "3 slots: effective size arena", "7340:623039201" },
    { "3 slots: width source boss", "13299:600623632" },
    { "3 slots: width source arena", "7925:2001148923" },
    { "3 slots: width source resize", "1791:30200776" },
    { "3 slots: cast target colours", "1060:1272740194" },
    { "3 slots: rounded on", "2662:803476627" },
    { "3 slots: rounded off", "5258:566203803" },
    { "3 slots: classic spark boss", "14625:606960255" },
    { "3 slots: classic spark arena", "8319:1825541278" },
    { "3 slots: frame layer", "5368:1345619038" },
    { "5 slots: effective size boss", "12151:898680211" },
    { "5 slots: effective size arena", "12234:1425550537" },
    { "5 slots: width source boss", "13299:600623632" },
    { "5 slots: width source arena", "13209:923465352" },
    { "5 slots: width source resize", "2011:1006890774" },
    { "5 slots: cast target colours", "1328:949083875" },
    { "5 slots: rounded on", "3336:1957103341" },
    { "5 slots: rounded off", "6584:207953388" },
    { "5 slots: classic spark boss", "14625:606960255" },
    { "5 slots: classic spark arena", "13859:405069398" },
    { "5 slots: frame layer", "6698:1013118119" },
    { "0 slots: effective size boss", "12151:898680211" },
    { "0 slots: effective size arena", "0:0" },
    { "0 slots: width source boss", "13299:600623632" },
    { "0 slots: width source arena", "0:0" },
    { "0 slots: width source resize", "1314:1828393128" },
    { "0 slots: cast target colours", "658:295835695" },
    { "0 slots: rounded on", "1651:205973700" },
    { "0 slots: rounded off", "3269:646221331" },
    { "0 slots: classic spark boss", "14625:606960255" },
    { "0 slots: classic spark arena", "0:0" },
    { "0 slots: frame layer", "3373:913452340" },
}

local failures = {}
for index, section in ipairs(sections) do
    local expected = EXPECTED[index]
    local measured = Checksum(section.text)
    if not expected or expected[1] ~= section.key or expected[2] ~= measured then
        failures[#failures + 1] = string.format("%s: expected %s, measured %s", section.key,
            expected and expected[2] or "(no section)", measured)
    end
end
if #EXPECTED ~= #sections then
    failures[#failures + 1] = string.format("%d sections expected, %d measured", #EXPECTED, #sections)
end
if #failures > 0 then
    error("castbar_pool_residue_smoke: the pool walkers changed what the boss/arena sites do"
        .. " (run with 'print' and diff against the recorded code):\n  " .. table.concat(failures, "\n  "), 0)
end
print(string.format("castbar_pool_residue_smoke: ok (%d sections on 3, 5 and 0 arena slots match the recorded"
    .. " boss/arena trace)", #sections))
