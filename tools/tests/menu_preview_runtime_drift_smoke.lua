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
--   7. The group preview cell is an engine scene built by the first paint, once.
--   8. That cell ignores the out-of-combat fade (the Options window is always
--      open out of combat) and keeps every other alpha setting live.
--   9. The Animate chip hands its clock to the cell, which then moves.
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

-- The group preview scenes the Options graph builds (section 7).
local sceneBuilds = 0
local mw = Open({ page = "home", beforeOptions = function(world)
    local GF = assert(world.core.GF, "harness: the core has no group frame namespace before the Options graph loads")
    local build = assert(GF.NewPreviewScene, "harness: the core has no group preview scene")
    GF.NewPreviewScene = function(...)
        sceneBuilds = sceneBuilds + 1
        return build(...)
    end
end })
local buildsAtOpen = sceneBuilds
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
    -- The engine scene paints the cell's text: its colour follows the same gradient at the sample fraction.
    local state = gbox._msufGFSceneState
    Check(state and state.mock and state.runtimeHealth and state.runtimeText, "harness: the group preview kept no scene state")
    Check(state.runtimeText.healthColorByHealth == true, "harness: the group text is not coloured by health")
    local shown
    for _, key in ipairs({ "_hpLeftFS", "_hpCenterFS", "_hpRightFS" }) do
        local fs = state.mock[key]
        if fs and fs.shown == true and fs.textColor then shown = fs break end
    end
    Check(shown, "harness: the cell shows no health text")
    -- The cell colours its text from the gradient stops of the health spec at its own bar fraction.
    local bar = state.mock._health
    Check(bar and tonumber(bar.value) and tonumber(bar.maximum) and bar.maximum > 0, "harness: the cell health bar holds no values")
    Expect("group preview", state.runtimeHealth, bar.value / bar.maximum, shown.textColor)
    Check(core.GF.CompileSpec("party", nil, nil).text.healthColorByHealth == true,
        "the live party spec does not colour health text by health")
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
            previewScale = 1, sampleClass = class, box = {}, MSUF = core,
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

-- 7. The group cell is an engine scene the first paint builds ------------------
-- The Options file captures nothing of the scene at load: no root is built until a preview paints, and the root is
-- built once for the preview, not once per paint.
Section("7 group cell scene is built by the first paint", function()
    Check(buildsAtOpen == 0, "loading the Options graph and opening a page built " .. tostring(buildsAtOpen) .. " group preview scenes")
    M.gfScope = "party"
    local base = sceneBuilds
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    Check(sceneBuilds == base and box._scene == nil, "creating a group preview built a scene before it was shown")
    box:Show()
    box._stage:SetSize(600, 220)
    box:Refresh("SETTINGS")
    Check(sceneBuilds == base + 1 and box._scene ~= nil, "the first paint built " .. tostring(sceneBuilds - base) .. " scenes, not one")
    local root = box._scene
    box:Refresh("SETTINGS")
    Check(sceneBuilds == base + 1 and box._scene == root, "a second paint built another scene")
    Check(box._mock._cell and box._mock._cell.IsShown and box._mock._cell:IsShown(), "the first paint left no cell on screen")
    -- Suspending the preview quiets the root; the next paint brings the same one back.
    box:ReleaseRuntimePreview()
    Check(root:IsActive() == false, "a suspended preview left its scene root active")
    box:Refresh("SETTINGS")
    Check(sceneBuilds == base + 1 and box._scene == root and root:IsActive(), "resuming the preview built another scene or left it quiet")
    box:Hide()
end)

-- 8. The Options preview ignores the out-of-combat fade ------------------------
-- The Options window is always open out of combat, so the live fade would leave the preview permanently faded. Every
-- other alpha setting (here the health bar opacity) stays live, and a frame of the same engine that is not asked
-- still fades.
Section("8 group cell ignores the out-of-combat fade", function()
    local conf = env.MSUF_DB.gf_party
    local saved = { conf.oocFadeEnabled, conf.oocFadeAlpha, conf.hpBarAlpha }
    conf.oocFadeEnabled, conf.oocFadeAlpha, conf.hpBarAlpha = true, 0.4, 0.6
    core.GF.InvalidateCompiledSpecs("party")
    M.gfScope = "party"
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    box:Show()
    box._stage:SetSize(600, 220)
    box:Refresh("SETTINGS")
    local cell = box._mock._cell
    Check(cell and cell.GetAlpha, "harness: the group preview has no cell frame")
    -- Control: the same engine without the request fades, and so does an on-screen dummy.
    local plain = core.GF.NewPreviewScene(env.UIParent)
    plain:Activate()
    local plainGroup = plain:Group("party")
    plainGroup:Show(1, { immediate = true })
    mw.world.widgets:RunTimers()
    local plainFrame = plainGroup:Frames()[1]
    Check(plainFrame and plainFrame:GetAlpha() == 0.4, "harness: a scene frame without the request does not fade (" .. tostring(plainFrame and plainFrame:GetAlpha()) .. ")")
    plain:Release()
    local dummy
    local wasPreviewing = env.MSUF2_GFPagePreviewActive
    env.MSUF2_GFPagePreviewActive = true
    core.GF.ShowPreview("party", 1, { immediate = true })
    mw.world.widgets:RunTimers()
    dummy = core.GF._previewFrames.party and core.GF._previewFrames.party[1]
    Check(dummy and dummy:GetAlpha() == 0.4, "harness: the on-screen dummy does not fade (" .. tostring(dummy and dummy:GetAlpha()) .. ")")
    core.GF.HidePreview("party")
    env.MSUF2_GFPagePreviewActive = wasPreviewing
    Check(cell:GetAlpha() == 1, "the Options preview cell is faded by the out-of-combat fade (" .. tostring(cell:GetAlpha()) .. ")")
    Check(cell.MSUFSpec.alpha.active == true and cell.MSUFSpec.alpha.hpAlpha == 0.6 and cell.MSUFSpec.alpha.oocFade == false,
        "the Options preview cell lost the health bar opacity with the fade")
    -- The health bar opacity dims the cell's texts like a live frame's (the live look of the Options preview).
    Check(cell.nameText and cell.nameText:GetAlpha() == 0.6, "the health bar opacity is not live in the Options preview (name text alpha "
        .. tostring(cell.nameText and cell.nameText:GetAlpha()) .. ")")
    Check(core.GF.CompileSpec("party").alpha.oocFade == true, "the Options preview changed the shared compiled spec")
    conf.oocFadeEnabled, conf.oocFadeAlpha, conf.hpBarAlpha = saved[1], saved[2], saved[3]
    core.GF.InvalidateCompiledSpecs("party")
    box:Hide()
end)

-- 9. The Animate chip moves the cell ------------------------------------------
-- The preview's own driver hands its elapsed time to the scene root; without that clock the cell would stay at its
-- static sample while the handles and aura lanes animate.
Section("9 animate moves the group cell", function()
    M.gfScope = "party"
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    box:Show()
    box._stage:SetSize(600, 220)
    box:Refresh("SETTINGS")
    local health = box._mock._health
    Check(health and health.value, "harness: the group preview cell has no health bar")
    local still = health.value
    local action = box._previewAnimationButton and box._previewAnimationButton._msuf2CommandAction
    Check(action and action.set(true) == true, "the Animate toggle does not start the animation")
    local onUpdate = box:GetScript("OnUpdate")
    Check(type(onUpdate) == "function", "Animate installs no OnUpdate driver")
    local seen = {}
    for _ = 1, 12 do
        onUpdate(box, 0.2)
        seen[health.value] = true
    end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    Check(distinct >= 3, "Animate ticks left the group cell at " .. distinct .. " distinct health values")
    Check(seen[still] ~= true or distinct >= 3, "Animate never left the static sample")
    action.set(false)
    box:Refresh("SETTINGS")
    Check(health.value == still, "turning Animate off did not return the cell to its static sample")
    box:Hide()
end)

-- 10. The group cell mirrors the live player --------------------------------
-- The Options stage reads the player (MSUF.UFPreview.LiveUnitData) and hands the engine scene a sample: name, class,
-- exact health and power with their maxima and the absorb amount. The scene itself reads no unit. Any field the
-- player cannot give falls back to the stylized sample.
local livePlayer = { on = true, name = "Mirror", class = "MAGE", className = "Mage", hp = 600000, hpMax = 2400000,
    power = 40, powerMax = 200, absorb = 77000 }
local function StubLivePlayer()
    local function Wrap(name, value)
        local plain = env[name]
        env[name] = function(unit, ...)
            if unit == "player" and livePlayer.on then return value() end
            if type(plain) == "function" then return plain(unit, ...) end
        end
    end
    Wrap("UnitExists", function() return true end)
    Wrap("UnitName", function() return livePlayer.name end)
    Wrap("UnitClass", function() return livePlayer.className, livePlayer.class end)
    Wrap("UnitHealth", function() return livePlayer.hp end)
    Wrap("UnitHealthMax", function() return livePlayer.hpMax end)
    Wrap("UnitPower", function() return livePlayer.power end)
    Wrap("UnitPowerMax", function() return livePlayer.powerMax end)
    Wrap("UnitGetTotalAbsorbs", function() return livePlayer.absorb end)
end
StubLivePlayer()
-- The cell's value texts are formatted by the engine with client functions this harness only stubs, so the check
-- watches what the scene hands the text runtime: the exact health and the absorb amount it formats.
local textCalls
local function WatchTexts(cell)
    local text = core.UFText
    assert(text and text.UpdateTextSlots, "harness: no text slot updater")
    textCalls = { health = nil, absorb = nil }
    local plain = text.UpdateTextSlots
    text.UpdateTextSlots = function(slots, count, current, max, ...)
        local rt = cell._msufTextRuntime
        if rt and slots == rt.healthSlots then textCalls.health = { current, max, rt.healthAbsorb } end
        if rt and slots == rt.healthAbsorbSlots then textCalls.absorb = { rt.healthAbsorb } end
        return plain(slots, count, current, max, ...)
    end
    return function() text.UpdateTextSlots = plain end
end
Section("10 group cell mirrors the live player", function()
    M.gfScope = "party"
    local conf = env.MSUF_DB.gf_party
    local saved = { conf.textLeft, conf.textCenter, conf.textRight }
    conf.textLeft, conf.textCenter, conf.textRight = "ABSORB", "NONE", "CURRENT"
    core.GF.InvalidateCompiledSpecs("party")
    livePlayer.on = true
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    box:Show()
    box._stage:SetSize(600, 220)
    box:Refresh("SETTINGS")
    local cell = box._mock._cell
    Check(cell and cell.nameText, "harness: the group preview has no cell")
    Check(cell.nameText.text == "Mirror", "the cell does not carry the player's name (" .. tostring(cell.nameText.text) .. ")")
    Check(cell._msufPortraitSampleClass == "MAGE", "the cell does not carry the player's class (" .. tostring(cell._msufPortraitSampleClass) .. ")")
    local bar = cell.hpBar
    Check(bar and bar.value == 600000 and bar.maximum == 2400000,
        "the health bar is not the player's exact health (" .. tostring(bar and bar.value) .. "/" .. tostring(bar and bar.maximum) .. ")")
    local powerBar = cell.targetPowerBar or cell.powerBar
    if powerBar and powerBar.maximum then
        Check(powerBar.value == 40 and powerBar.maximum == 200,
            "the power bar is not the player's exact power (" .. tostring(powerBar.value) .. "/" .. tostring(powerBar.maximum) .. ")")
    end
    local unwatch = WatchTexts(cell)
    box:Refresh("SETTINGS")
    Check(textCalls.health and textCalls.health[1] == 600000 and textCalls.health[2] == 2400000,
        "the health text is not formatted from the player's exact health")
    Check(textCalls.absorb and textCalls.absorb[1] == 77000, "the absorb text is not formatted from the player's absorb")
    -- Without a readable player the stylized sample backs every field.
    livePlayer.on = false
    box:Refresh("SETTINGS")
    Check(cell.nameText.text ~= "Mirror" and cell.hpBar.value == 720000 and cell.hpBar.maximum == 1000000,
        "an unreadable player did not fall back to the stylized sample (" .. tostring(cell.nameText.text) .. ", "
        .. tostring(cell.hpBar.value) .. ")")
    Check(textCalls.health and textCalls.health[1] == 720000 and textCalls.absorb and textCalls.absorb[1] == 125000,
        "the stylized text values are gone without a player (" .. tostring(textCalls.health and textCalls.health[1]) .. ", "
        .. tostring(textCalls.absorb and textCalls.absorb[1]) .. ")")
    unwatch()
    livePlayer.on = true
    conf.textLeft, conf.textCenter, conf.textRight = saved[1], saved[2], saved[3]
    core.GF.InvalidateCompiledSpecs("party")
    box:Hide()
end)

-- 11. The live-state driver keeps the cell current ---------------------------
Section("11 group cell live-state driver", function()
    M.gfScope = "party"
    livePlayer.on = true
    livePlayer.hp = 600000
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    local driver = box._msufGFLiveStateDriver
    Check(driver, "the group preview has no live-state driver")
    Check(driver:IsEventRegistered("UNIT_HEALTH") ~= true, "the driver listens before the preview is shown")
    -- Show and Hide fire OnShow and OnHide like the client (the driver arms and drops with them).
    MenuWorld.FireVisibilityScripts(box)
    box:Hide()
    box:Show()
    box._stage:SetSize(600, 220)
    mw:RunTimers()
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_NAME_UPDATE", "PLAYER_REGEN_DISABLED" }) do
        Check(driver:IsEventRegistered(event), "the driver does not listen for " .. event .. " while the preview is shown")
    end
    local cell = box._mock._cell
    Check(cell and cell.hpBar and cell.hpBar.value == 600000, "harness: the cell is not at the player's health")
    -- A health tick repaints the cell with the new value (coalesced on the live-state window).
    livePlayer.hp = 1200000
    mw.world:FireEvent("UNIT_HEALTH", "player")
    mw:RunTimers()
    Check(box._mock._cell.hpBar.value == 1200000, "a health change did not reach the cell (" .. tostring(box._mock._cell.hpBar.value) .. ")")
    -- Combat drops every listener but the re-arm signal; leaving combat arms the driver again.
    mw.world:EnterCombat()
    mw:RunTimers()
    Check(not driver:IsEventRegistered("UNIT_HEALTH") and not driver:IsEventRegistered("PLAYER_REGEN_DISABLED"),
        "the driver kept listening in combat")
    Check(driver:IsEventRegistered("PLAYER_REGEN_ENABLED"), "the driver lost its re-arm signal in combat")
    mw.world:LeaveCombat()
    mw:RunTimers()
    Check(driver:IsEventRegistered("UNIT_HEALTH"), "the driver was not armed again after combat")
    -- A hidden preview listens to nothing.
    box:Hide()
    Check(not driver:IsEventRegistered("UNIT_HEALTH") and not driver:IsEventRegistered("PLAYER_REGEN_DISABLED"),
        "a hidden preview kept its live-state listeners")
    livePlayer.hp = 600000
end)

-- 12. A text drag moves the engine text as far as the handle ------------------
-- The drag delta is in the units of the outer preview frame, the engine texts sit in the zoomed cell: without the
-- scale ratio the text runs ahead of the handle by the zoom and snaps back on release.
Section("12 group text drag follows the zoomed cell", function()
    M.gfScope = "party"
    local conf = env.MSUF_DB.gf_party
    local savedConf = { conf.nameOffsetX, conf.nameOffsetY }
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    box._manualZoom = 3
    box:Show()
    box._stage:SetSize(600, 220)
    box:Refresh("SETTINGS")
    local mock = box._mock
    local zoom = tonumber(mock._previewScale)
    Check(zoom and zoom > 1.5, "harness: the preview is not zoomed (" .. tostring(zoom) .. ")")
    local handle = box._textHandles and box._textHandles.name
    Check(handle and handle._cfgText, "harness: the group preview has no name text handle")
    local region = mock._nameFS
    Check(region and region.GetPoint and region:GetPoint(1), "harness: the name text has no anchor")
    local cellScale = region:GetEffectiveScale() / mock:GetEffectiveScale()
    Check(math.abs(cellScale - zoom) < 1e-6, "harness: the cell is not zoomed with the preview (" .. tostring(cellScale) .. " vs " .. tostring(zoom) .. ")")
    local function Offset()
        local _, _, _, x, y = region:GetPoint(1)
        return x, y
    end
    local startX, startY = Offset()
    local cursorX, cursorY = 500, 400
    local plain = { env.GetCursorPosition, env.IsMouseButtonDown, env.IsControlKeyDown }
    env.GetCursorPosition = function() return cursorX, cursorY end
    env.IsMouseButtonDown = function() return true end
    env.IsControlKeyDown = function() return false end
    local start = assert(handle.scripts and handle.scripts.OnMouseDown, "harness: the text handle has no drag start")
    start(handle, "LeftButton")
    Check(handle._dragging == true, "harness: the text drag did not start")
    -- 30 screen pixels at the cell's zoom of 3 are 10 configured units.
    cursorX, cursorY = cursorX + 10 * zoom, cursorY + 6 * zoom
    local update = box._dragFrame:GetScript("OnUpdate")
    update(box._dragFrame, 0.016)
    local movedX, movedY = Offset()
    Check(math.abs((movedX - startX) - 10) < 1e-6 and math.abs((movedY - startY) - 6) < 1e-6,
        "the dragged text moved " .. tostring(movedX - startX) .. "," .. tostring(movedY - startY) .. " instead of 10,6 cell units")
    env.IsMouseButtonDown = function() return false end
    update(box._dragFrame, 0.016)
    env.GetCursorPosition, env.IsMouseButtonDown, env.IsControlKeyDown = plain[1], plain[2], plain[3]
    conf.nameOffsetX, conf.nameOffsetY = savedConf[1], savedConf[2]
    core.GF.InvalidateCompiledSpecs("party")
    box:Hide()
end)

-- 13. Every preview kind keeps its body ------------------------------------------
-- The engine cell of the Options group preview must sit inside the mock frame and draw its health fill, health
-- background and border for every kind the engine previews, also with the raid setting that keeps the groups apart
-- (its grid footprint is a whole group column, so a cell placed by the grid alone lands outside the mock).
local function PreviewKinds()
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local list = assert(source:match("local PREVIEW_KINDS = (%b{})"), "harness: the engine preview kind list moved")
    local kinds = {}
    for kind in list:gmatch('"([%w_]+)"') do kinds[#kinds + 1] = kind end
    assert(#kinds >= 3, "harness: the engine previews fewer than three kinds")
    return kinds
end
-- Rectangle of a frame in the mock's own units (origin: the mock's centre), following each first anchor point up to
-- the mock; offsets and sizes are scaled by the effective scale ratio.
local function RectInMock(mock, frame)
    local mockScale = mock:GetEffectiveScale()
    local function Corner(rect, point)
        local x = point:find("LEFT") and rect[1] or point:find("RIGHT") and rect[3] or (rect[1] + rect[3]) / 2
        local y = point:find("TOP") and rect[4] or point:find("BOTTOM") and rect[2] or (rect[2] + rect[4]) / 2
        return x, y
    end
    local function RectOf(f)
        if f == mock then
            local w, h = f:GetWidth(), f:GetHeight()
            return { -w / 2, -h / 2, w / 2, h / 2 }
        end
        local k = f:GetEffectiveScale() / mockScale
        local w, h = f:GetWidth() * k, f:GetHeight() * k
        local point, rel, relPoint, x, y = f:GetPoint(1)
        local ax, ay = Corner(RectOf(rel or f:GetParent()), relPoint or point)
        local px, py = ax + (x or 0) * k, ay + (y or 0) * k
        local left = point:find("LEFT") and px or point:find("RIGHT") and px - w or px - w / 2
        local bottom = point:find("BOTTOM") and py or point:find("TOP") and py - h or py - h / 2
        return { left, bottom, left + w, bottom + h }
    end
    return RectOf(frame)
end
local function EffectiveAlpha(region)
    local alpha, node = 1, region
    while node do
        if node.IsShown and node:IsShown() == false then return 0 end
        alpha = alpha * (node.GetAlpha and node:GetAlpha() or 1)
        node = node.GetParent and node:GetParent() or nil
    end
    return alpha
end
Section("13 every group preview kind keeps its body", function()
    local problems = {}
    for _, kind in ipairs(PreviewKinds()) do
        local conf = env.MSUF_DB["gf_" .. kind]
        local variants = { { "default" } }
        if kind ~= "party" then variants[#variants + 1] = { "groups kept apart", true } end
        for _, variant in ipairs(variants) do
            local saved = conf.preserveRaidGroups
            if variant[2] ~= nil then conf.preserveRaidGroups = variant[2] end
            core.GF.InvalidateCompiledSpecs(kind)
            M.gfScope = kind
            local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
            box:Show()
            box._stage:SetSize(600, 220)
            box:Refresh("SETTINGS")
            local label = kind .. " (" .. variant[1] .. ")"
            local mock, cell = box._mock, box._mock._cell
            if not cell then
                problems[#problems + 1] = label .. ": no cell"
            else
                local regions = { { "health fill", cell.hpBar and cell.hpBar:GetStatusBarTexture() },
                    { "health background", cell.hpBarBG }, { "border", cell.MSUFBorderOverlay } }
                for _, item in ipairs(regions) do
                    local region = item[2]
                    local w = region and region.GetWidth and region:GetWidth() or 0
                    local h = region and region.GetHeight and region:GetHeight() or 0
                    if not region or EffectiveAlpha(region) <= 0 or (item[1] ~= "health fill" and (w <= 0 or h <= 0)) then
                        problems[#problems + 1] = label .. ": " .. item[1] .. " is not drawn"
                    end
                end
                local rect, frame = RectInMock(mock, cell), { -mock:GetWidth() / 2, -mock:GetHeight() / 2, mock:GetWidth() / 2, mock:GetHeight() / 2 }
                if rect[1] < frame[1] - 0.5 or rect[2] < frame[2] - 0.5 or rect[3] > frame[3] + 0.5 or rect[4] > frame[4] + 0.5 then
                    problems[#problems + 1] = string.format("%s: the cell lies outside the preview frame (cell %.1f..%.1f x %.1f..%.1f, frame %.1f..%.1f x %.1f..%.1f)",
                        label, rect[1], rect[3], rect[2], rect[4], frame[1], frame[3], frame[2], frame[4])
                end
            end
            box:Hide()
            conf.preserveRaidGroups = saved
            core.GF.InvalidateCompiledSpecs(kind)
        end
    end
    Check(#problems == 0, table.concat(problems, "; "))
end)

if #failures > 0 then
    error(table.concat(failures, "\n"), 0)
end
print(string.format("menu_preview_runtime_drift_smoke: ok (%s)", flavor))
