-- menu_preview_runtime_drift_smoke.lua <repoRoot> <flavor>
--
-- The menu previews must show what the game shows. Each section drives one
-- preview and the live code it stands for with the same inputs and compares the
-- two outputs, so a rule that is changed on one side only turns this red:
--
--   1. Class resource width and anchor: the unit preview against the live
--      ClassPower container (real CP_Core layout) for every width mode.
--   2. Health text "by health": the unit and group previews paint the
--      configured gradient stops, not a fixed red-yellow-green ramp.
--   3. Detached arena castbar: the preview reads the live arena castbar for its
--      scale and offset like it does for boss, player, target and focus.
--   4. Portrait border colour: class and reaction styles in the unit and group
--      previews paint the colour the live portrait element resolves.
--   5. Group preview names: shortening never cuts a UTF-8 character.
--   6. The first spec read of the unit preview does not recompile (and so does
--      not replace) the specs the live frames hold.
--
-- Sections report together so one run shows every drift. Plain Lua 5.1, repo
-- root as arg 1, client matrix Suffix (or Forever) as arg 2.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_preview_runtime_drift_smoke boots the real TOC graph; run it with plain Lua 5.1")

local failures = {}
local function Section(name, fn)
    local ok, message = pcall(fn)
    if not ok then failures[#failures + 1] = string.format("[%s] %s: %s", flavor, name, tostring(message)) end
end
local function Check(condition, message)
    if not condition then error(message, 0) end
end
local function Near(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-4
end
local function RGBText(r, g, b)
    return string.format("%s/%s/%s", tostring(r), tostring(g), tostring(b))
end

-- 1. Live class resource geometry (before the menu world exists) -------------
-- The live container is what CP_Core lays out against the player frame; the
-- ClassPower stack is the repository's own, loaded by classpower_world.lua.
local CPWorld = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))()
local PLAYER_W = 275
local CASES = {
    { label = "default (player)", bars = {} },
    { label = "player with an X offset", bars = { classPowerWidthMode = "player", classPowerOffsetX = 7 } },
    { label = "custom 180", bars = { classPowerWidthMode = "custom", classPowerWidth = 180 } },
    { label = "custom below 30", bars = { classPowerWidthMode = "custom", classPowerWidth = 12 } },
    { label = "cooldown viewer absent", bars = { classPowerWidthMode = "cooldown", classPowerOffsetX = 3 } },
    { label = "auto_pips on a bar", bars = { classPowerWidthMode = "auto_pips", classPowerShape = "BAR" } },
    { label = "auto_pips on circles", bars = { classPowerWidthMode = "auto_pips", classPowerShape = "CIRCLE",
        classPowerGap = 2, classPowerHeight = 10 } },
}
local live = {}
for index, case in ipairs(CASES) do
    local bars = { classPowerHeight = 4 }
    for key, value in pairs(case.bars) do bars[key] = value end
    local ok, result = pcall(function()
        local t = CPWorld.Start(root, flavor == "Forever" and "Mainline" or flavor, "ROGUE", 1, CPWorld.PT.ENERGY, bars)
        _G.MSUF_player:SetSize(PLAYER_W, 40)
        assert(_G.MSUF_ClassPower_RefreshLayout() == true, "the live class resource layout did not run")
        local container = assert(t.CP.container, "the live class resource has no container")
        local _, _, _, x = container:GetPoint(1)
        return { width = container:GetWidth(), x = x }
    end)
    live[index] = ok and result or { error = tostring(result) }
end

-- The menu world: the whole core and Options graph -----------------------------
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
-- The group preview names its first frame after the player (section 5).
local previewPlayerName
local function Open(options)
    options = options or {}
    options.beforeCore = function(world)
        -- The stock class colours the live portrait border reads (the harness
        -- answers every unmodelled global with an opaque stub).
        world.env.RAID_CLASS_COLORS = {
            WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
            HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
            PRIEST = { r = 1, g = 1, b = 1 }, DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
            SHAMAN = { r = 0, g = 0.44, b = 0.87 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 },
            WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }, MONK = { r = 0, g = 1, b = 0.6 },
            DRUID = { r = 1, g = 0.49, b = 0.04 }, DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
            EVOKER = { r = 0.2, g = 0.58, b = 0.5 },
        }
        local plainUnitName = world.env.UnitName
        world.env.UnitName = function(unit, ...)
            if previewPlayerName ~= nil and unit == "player" then return previewPlayerName end
            return plainUnitName(unit, ...)
        end
        if world.widgets.Methods.GetCenter == nil then
            world.widgets.Methods.GetCenter = function(frame)
                return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
                    (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
            end
        end
    end
    return MenuWorld.Open(root, flavor, options)
end
local function UnitBox(mw, key)
    local env, Preview = mw.env, mw.core.UFPreview
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return key or "player" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show()
    box.canvas:SetSize(600, 260)
    local function Refresh()
        mw.core.UF.Config.Refresh()
        Preview.Refresh(box, "MENU_PREVIEW_RUNTIME_DRIFT")
    end
    Refresh()
    return box, Refresh
end

local mw = Open({ page = "home" })
local env, core, M = mw.env, mw.core, mw.M

Section("1 class resource width and anchor", function()
    local box, Refresh = UnitBox(mw, "player")
    local bars = env.MSUF_DB.bars
    local saved = {}
    for _, field in ipairs({ "classPowerWidthMode", "classPowerWidth", "classPowerOffsetX", "classPowerShape",
        "classPowerGap", "classPowerHeight", "showClassPower" }) do saved[field] = bars[field] end
    local problems = {}
    for index, case in ipairs(CASES) do
        local facts = live[index]
        Check(facts.error == nil, "harness: " .. case.label .. ": " .. tostring(facts.error))
        for _, field in ipairs({ "classPowerWidthMode", "classPowerWidth", "classPowerOffsetX", "classPowerShape",
            "classPowerGap" }) do bars[field] = nil end
        bars.showClassPower, bars.classPowerHeight = true, 4
        for key, value in pairs(case.bars) do bars[key] = value end
        Refresh()
        local container = box.mock.classPower
        local previewW = box._runtimeClassPowerW
        local _, _, _, previewX = container:GetPoint(1)
        if not (Near(previewW, facts.width) and Near(container:GetWidth(), facts.width)) then
            problems[#problems + 1] = string.format("%s: preview width %s (box %s), live %s", case.label,
                tostring(previewW), tostring(container:GetWidth()), tostring(facts.width))
        end
        if not Near(previewX, facts.x) then
            problems[#problems + 1] = string.format("%s: preview anchor x %s, live %s", case.label,
                tostring(previewX), tostring(facts.x))
        end
    end
    for field, value in pairs(saved) do bars[field] = value end
    Refresh()
    Check(#problems == 0, table.concat(problems, "; "))
end)

Section("2 health text gradient", function()
    local general = env.MSUF_DB.general
    local saved = {}
    local FIELDS = { "colorHealthTextByHealth", "healthGradientLowR", "healthGradientLowG", "healthGradientLowB",
        "healthGradientMidR", "healthGradientMidG", "healthGradientMidB", "healthGradientHighR",
        "healthGradientHighG", "healthGradientHighB" }
    for _, field in ipairs(FIELDS) do saved[field] = general[field] end
    general.colorHealthTextByHealth = true
    general.healthGradientLowR, general.healthGradientLowG, general.healthGradientLowB = 0.2, 0.1, 0.9
    general.healthGradientMidR, general.healthGradientMidG, general.healthGradientMidB = 0.1, 0.9, 0.9
    general.healthGradientHighR, general.healthGradientHighG, general.healthGradientHighB = 0.9, 0.3, 0.1
    local common = assert(core.UFBarTextCommon, "harness: no bar text common")
    local problems = {}
    local function Expect(label, health, pct, color)
        local r, g, b = common.HealthGradientColorFromValues(health, pct, 1)
        if not (color and Near(color[1], r) and Near(color[2], g) and Near(color[3], b)) then
            problems[#problems + 1] = string.format("%s at %.2f: preview %s, live %s", label, pct,
                color and RGBText(color[1], color[2], color[3]) or "none", RGBText(r, g, b))
        end
    end

    local box, Refresh = UnitBox(mw, "player")
    Refresh()
    local spec = core.UF.Config.specs.player
    Check(spec and spec.text and spec.text.healthColorByHealth == true, "harness: the player spec does not colour health text by health")
    local scene = box._msufPreviewScene
    Check(scene and scene.data and tonumber(scene.data.hp), "harness: the unit preview kept no scene data")
    Expect("unit preview", spec.health, tonumber(scene.data.hp), box.mock.hpTextLeft.textColor)

    M.gfScope = "party"
    local gbox = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    gbox:Show()
    core.UF.Config.Refresh()
    gbox:Refresh("SETTINGS")
    local state, htx = gbox._msufGFSceneState, gbox._msufGFHealthTextState
    Check(state and state.mock and state.runtimeHealth and htx and htx.byHealth == true,
        "harness: the group preview kept no by-health text state")
    local fakeHP = math.max(1, math.floor(htx.fakeMax * state.hpPct + 0.5))
    Expect("group preview", state.runtimeHealth, fakeHP / htx.fakeMax, state.mock._hpLeftFS.textColor)
    gbox:Hide()
    for _, field in ipairs(FIELDS) do general[field] = saved[field] end
    Refresh()
    Check(#problems == 0, table.concat(problems, "; "))
end)

Section("3 detached arena castbar", function()
    local Runtime = core.UFPreviewRuntime
    Check(type(core.UF.GetFrame) == "function", "harness: no UF.GetFrame")
    local unit = env.CreateFrame("Frame", nil, env.UIParent)
    unit:SetSize(220, 40)
    unit.left, unit.bottom = 100, 300
    local cast = env.CreateFrame("Frame", nil, env.UIParent)
    cast:SetSize(200, 20)
    cast.left, cast.bottom = 400, 120
    cast:SetScale(0.5)
    local savedUnit, savedPool = env.MSUF_arena1, env.MSUF_ArenaCastbars
    env.MSUF_arena1, env.MSUF_ArenaCastbars = unit, { cast }
    local target = env.CreateFrame("Frame", nil, env.UIParent)
    local problems = {}
    local ratio = Runtime.CastbarVisualScaleForPreviewKey("arena", target)
    if not Near(ratio, 0.5) then
        problems[#problems + 1] = "the arena castbar scale ratio is " .. tostring(ratio) .. " instead of the live bar's 0.5"
    end
    local dx, dy = Runtime.DetachedCastbarOffsetForPreviewKey("arena")
    local castX, castY = (400 + 100) * 0.5, (120 + 10) * 0.5
    local unitX, unitY = 100 + 110, 300 + 20
    if not (Near(dx, castX - unitX) and Near(dy, castY - unitY)) then
        problems[#problems + 1] = string.format("the detached arena offset is %s/%s instead of %s/%s",
            tostring(dx), tostring(dy), tostring(castX - unitX), tostring(castY - unitY))
    end
    env.MSUF_arena1, env.MSUF_ArenaCastbars = savedUnit, savedPool
    Check(#problems == 0, table.concat(problems, "; "))
end)

Section("4 portrait border colour", function()
    local Portrait = core.UF.elements.Portrait
    local RAID = env.RAID_CLASS_COLORS
    Check(type(RAID) == "table", "harness: no RAID_CLASS_COLORS")
    local problems = {}
    local function Want(label, got, r, g, b)
        if not (got and Near(got[1], r) and Near(got[2], g) and Near(got[3], b)) then
            problems[#problems + 1] = string.format("%s: preview %s, live %s", label,
                got and RGBText(got[1], got[2], got[3]) or "none", RGBText(r, g, b))
        end
    end
    local function BorderRGB(portrait)
        local border = portrait.border
        return { border._msufPreviewEdgeR, border._msufPreviewEdgeG, border._msufPreviewEdgeB }
    end

    -- Unit preview: a custom class colour is a bar/text choice; the live portrait
    -- border reads the stock class colour, and a reaction border is red
    -- (hostile), orange (neutral) or green (friendly), never other shades.
    for _, key in ipairs({ "player", "target" }) do
        local conf = env.MSUF_DB[key]
        local saved = { conf.portraitMode, conf.portraitShape, conf.portraitBorderStyle, conf.portraitBorderThickness }
        conf.portraitMode, conf.portraitShape, conf.portraitBorderThickness = "LEFT", "SQUARE", 2
        local box, Refresh = UnitBox(mw, key)
        local scene = box._msufPreviewScene
        local class = scene and scene.data and scene.data.class
        Check(type(class) == "string" and RAID[class], "harness: the " .. key .. " preview has no class colour")
        env.MSUF_DB.classColors = env.MSUF_DB.classColors or {}
        local savedClassColor = env.MSUF_DB.classColors[class]
        env.MSUF_DB.classColors[class] = { r = 0.11, g = 0.22, b = 0.33 }
        conf.portraitBorderStyle = "CLASS_COLOR"
        Refresh()
        local raw = RAID[class]
        Want(key .. " class colour border", BorderRGB(box.mock.portrait), raw.r, raw.g, raw.b)
        conf.portraitBorderStyle = "REACTION"
        Refresh()
        if key == "target" then
            Want("hostile reaction border", BorderRGB(box.mock.portrait), 1, 0, 0)
        else
            Want("friendly reaction border", BorderRGB(box.mock.portrait), 0, 1, 0)
        end
        env.MSUF_DB.classColors[class] = savedClassColor
        conf.portraitMode, conf.portraitShape, conf.portraitBorderStyle, conf.portraitBorderThickness = saved[1], saved[2], saved[3], saved[4]
    end

    -- Group preview.
    local party = env.MSUF_DB.gf_party
    local savedStyle, savedMode = party.portraitBorderStyle, party.portraitMode
    party.portraitMode, party.portraitRender, party.portraitShape = "LEFT", "2D", "SQUARE"
    local function GroupBorder(style, class, customClassColor)
        party.portraitBorderStyle = style
        core.GF.InvalidateCompiledSpecs("party")
        local spec = core.GF.CompileSpec("party", nil, "party1")
        local mock = env.CreateFrame("Frame", nil, env.UIParent)
        mock:SetSize(180, 48)
        mock:SetFrameLevel(500)
        mock._health = env.CreateFrame("StatusBar", nil, mock)
        mock._health:SetFrameLevel(501)
        local scene = { kind = "party", mock = mock, runtimeSpec = spec, layerAvailable = {}, layerVisible = {},
            previewScale = 1, liveData = { class = class }, box = {}, MSUF = core,
            S = { Layers = core.UF.Layers, ScaleValue = function(v, scale) return v * scale end,
                ClassColor = function() return unpack(customClassColor) end } }
        M.GroupPreviewRender.PaintGroupPreviewPortrait(scene)
        local holder = assert(mock._msufGroupPortrait, "harness: the group preview painted no portrait")
        local edge = assert(holder.edges and holder.edges[1], "harness: no group portrait border edge")
        return edge.vertexColor
    end
    local raw = RAID.MAGE
    Want("group class colour border", GroupBorder("CLASS_COLOR", "MAGE", { 0.11, 0.22, 0.33 }), raw.r, raw.g, raw.b)
    Want("group reaction border", GroupBorder("REACTION", "MAGE", { 0.11, 0.22, 0.33 }), 0, 1, 0)
    party.portraitBorderStyle, party.portraitMode = savedStyle, savedMode
    core.GF.InvalidateCompiledSpecs("party")

    -- The runtime rule the previews call.
    if type(Portrait.BorderColor) ~= "function" then
        problems[#problems + 1] = "the portrait element exports no BorderColor rule"
    else
        local function Rule(label, style, class, reaction, wr, wg, wb)
            local r, g, b = Portrait.BorderColor({ style = style }, class, reaction)
            if not (Near(r, wr) and Near(g, wg) and Near(b, wb)) then
                problems[#problems + 1] = string.format("BorderColor %s is %s, not %s", label, RGBText(r, g, b), RGBText(wr, wg, wb))
            end
        end
        Rule("class colour", "CLASS_COLOR", "MAGE", nil, raw.r, raw.g, raw.b)
        Rule("hostile reaction", "REACTION", nil, 2, 1, 0, 0)
        Rule("neutral reaction", "REACTION", nil, 4, 1, 0.6, 0)
        Rule("friendly reaction", "REACTION", nil, 5, 0, 1, 0)
        Rule("unknown reaction", "REACTION", nil, nil, 1, 1, 1)
    end
    Check(#problems == 0, table.concat(problems, "; "))
end)

Section("5 group preview names", function()
    local GF = core.GF
    GF.EnsureDB()
    -- Cyrillic (2 bytes per character) and Chinese (3 bytes per character) names.
    local names = { string.char(208, 144, 209, 128, 209, 130, 209, 145, 208, 188),
        string.char(228, 189, 160, 229, 165, 189, 228, 184, 150, 231, 149, 140, 230, 136, 145) }
    local problems = {}
    local function Utf8Length(text)
        local count, i, n = 0, 1, #text
        while i <= n do
            local byte = text:byte(i)
            local length = byte < 0x80 and 1 or (byte >= 0xC2 and byte < 0xE0 and 2) or (byte >= 0xE0 and byte < 0xF0 and 3)
                or (byte >= 0xF0 and byte < 0xF5 and 4) or 0
            if length == 0 or i + length - 1 > n then return nil end
            for k = 1, length - 1 do
                local cont = text:byte(i + k)
                if cont < 0x80 or cont > 0xBF then return nil end
            end
            i = i + length
            count = count + 1
        end
        return count
    end
    local function Utf8Prefix(text, characters)
        local i = 1
        for _ = 1, characters do
            local byte = text:byte(i)
            i = i + (byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4)
        end
        return text:sub(1, i - 1)
    end
    local conf = GF.GetConf("party")
    local saved = { conf.fontOverride, conf.nameShortenEnabled, conf.nameMaxChars, conf._msufLegacyNameAnchorToFrame }
    env.MSUF2_GFPagePreviewActive = true
    for _, legacy in ipairs({ false, true }) do
        for _, name in ipairs(names) do
            conf.enabled, conf.fontOverride, conf.nameShortenEnabled, conf.nameMaxChars = true, true, true, 4
            conf._msufLegacyNameAnchorToFrame = legacy or nil
            previewPlayerName = name
            GF.HidePreview("party")
            core.UF.Config.Refresh()
            GF.InvalidateCompiledSpecs("party")
            if GF.ShowPreview("party", 2) == false then error("the party preview did not open", 0) end
            local frame = GF._previewFrames.party[1]
            local shown = frame and frame.nameText and frame.nameText:GetText()
            local label = (legacy and "legacy " or "") .. "name of " .. #name .. " bytes"
            -- The engine paints the sample name: the full name (the layout clips it), or with
            -- the legacy rule its first 4 characters and "..", cut on character boundaries.
            local wanted = legacy and (Utf8Prefix(name, 4) .. "..") or name
            if shown ~= wanted then
                problems[#problems + 1] = string.format("%s shows %s (%s), the live rule paints %s", label,
                    tostring(shown), Utf8Length(tostring(shown)) and "valid UTF-8" or "invalid UTF-8", wanted)
            end
        end
    end
    conf.fontOverride, conf.nameShortenEnabled, conf.nameMaxChars, conf._msufLegacyNameAnchorToFrame =
        saved[1], saved[2], saved[3], saved[4]
    previewPlayerName = nil
    GF.HidePreview("party")
    env.MSUF2_GFPagePreviewActive = nil
    Check(#problems == 0, table.concat(problems, "; "))
end)

-- 6. The first spec read must not recompile the live specs ---------------------
Section("6 first preview refresh keeps the live specs", function()
    local fresh = Open({ page = "home", open = false })
    local Config = fresh.core.UF.Config
    Config.Refresh()
    local spec = Config.specs.player
    local portrait, serial = spec.portrait, Config.serial
    Check(type(portrait) == "table", "harness: the live player spec has no portrait table")
    local read = fresh.core.UFPreviewRuntime.SpecForPreviewKey("player")
    Check(read == spec, "the preview read a spec other than the live one")
    Check(Config.specs.player.portrait == portrait and Config.serial == serial,
        "the first preview read recompiled the live specs in place (portrait table replaced, serial "
        .. tostring(serial) .. " -> " .. tostring(Config.serial) .. ")")
    -- A profile swap replaces MSUF_DB; the runtime recompiles and applies it
    -- (State/MSUF_ProfileRuntime.lua), the preview must not do it a second time.
    local swapped = {}
    for key, value in pairs(fresh.env.MSUF_DB) do swapped[key] = value end
    fresh.env.MSUF_DB = swapped
    fresh.core.UFPreviewRuntime.SpecForPreviewKey("player")
    Check(Config.specs.player.portrait == portrait and Config.serial == serial,
        "a profile swap made the preview recompile the live specs")
end)

if #failures > 0 then
    error(table.concat(failures, "\n"), 0)
end
print(string.format("menu_preview_runtime_drift_smoke: ok (%s)", flavor))
