-- menu_preview_live_parity_smoke.lua <repoRoot> <flavor>
--
-- The options menu previews draw samples of live elements. Each sample must
-- follow the rule, colour, icon source and geometry of the live builder it
-- stands for, on the client that runs it. This smoke boots the flavor's whole
-- shipped core and Options graph through tools/tests/client_world.lua and
-- checks the preview samples against the live facts:
--
--   1. Friendly bosses (group preview): the extra-sample list, the layout and
--      the real group preview only offer boss samples where boss units exist
--      (Client.SupportsUnit("boss1")); Classic Era and TBC have none.
--   2. Group mock aura icons: icon file IDs of the unit preview's set, never a
--      spell lookup that turns into the question mark on another client.
--   3. Portrait crop without a compiled spec: the unit config's own compile
--      (zoom, aspect ratio, pan, flip), never a drifted copy.
--   4. Castbar samples: the latency text in the player time font, channel
--      ticks placed like the live markers (count, centring, fill direction).
--   5. Castbar fill colour: with a palette choice and no custom RGB the unit
--      preview paints what the live castbars resolve (MSUF_ResolveCastbarColors),
--      never a colour of its own.
--
-- Plain Lua 5.1 with the repo root and a client matrix Suffix (or Forever).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_preview_live_parity_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "menu_preview_live_parity_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
-- Blizzard's boss frame count, read by the core at load (the harness has none).
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local env, MSUF = world.env, world.core
local Methods = world.widgets.Methods
for name, method in pairs({
    SetStartPoint = function(self, ...) self.startPoint = { ... } end,
    SetEndPoint = function(self, ...) self.endPoint = { ... } end,
    SetThickness = function(self, value) self.thickness = value end,
    SetAutoFocus = function(self, value) self.autoFocus = value end,
    SetMaxLetters = function(self, value) self.maxLetters = value end,
    EnableKeyboard = function(self, value) self.keyboardEnabled = value end,
}) do
    if Methods[name] == nil then Methods[name] = method end
end
env.C_Texture = { GetAtlasInfo = function() return nil end }
env.MSUF_EnsureDB(true)
local M = MSUF.MSUF2
local Client = MSUF.Client
Check(type(Client) == "table" and type(Client.SupportsUnit) == "function", "no client model")

-- 1. Friendly bosses -------------------------------------------------------
do
    local bossUnits = Client.SupportsUnit("boss1") == true
    local R = M.GroupPreviewRender
    Check(type(R) == "table" and type(R.AdditionalPreviewLayout) == "function", "no group preview render")
    Check(type(R.ADDITIONAL_PREVIEW_PREFIXES) == "table", "the group preview publishes no extra-sample list")
    local listed = false
    for _, prefix in ipairs(R.ADDITIONAL_PREVIEW_PREFIXES) do
        if prefix == "friendlyBoss" then listed = true end
    end
    Check(listed == bossUnits, "friendly boss samples " .. (listed and "listed" or "missing")
        .. " although the client " .. (bossUnits and "has" or "has no") .. " boss units")
    local asked = {}
    local gf = { GetAdditionalPreviewSpec = function(_, prefix)
        asked[prefix] = true
        return { enabled = true, totalWidth = 100, totalHeight = 50 }
    end }
    local conf = { enabled = true, friendlyBossEnabled = true }
    local layout = R.AdditionalPreviewLayout(gf, "party", conf, 120, 40)
    if bossUnits then
        Check(layout ~= nil and layout.friendlyBoss ~= nil, "Friendly bosses alone draw no sample")
    else
        Check(layout == nil and not asked.friendlyBoss, "Friendly bosses alone open a sample scene without boss units")
    end
    conf.petsEnabled, conf.targetsEnabled, conf.healerManaEnabled = true, true, true
    layout = R.AdditionalPreviewLayout(gf, "party", conf, 120, 40)
    Check(layout ~= nil and layout.pets ~= nil and layout.targets ~= nil and layout.healerMana ~= nil,
        "the other extra samples vanished")
    Check((layout.friendlyBoss ~= nil) == bossUnits and (asked.friendlyBoss == true) == bossUnits,
        "the scene " .. (layout.friendlyBoss and "draws" or "omits") .. " friendly boss samples on a client "
        .. (bossUnits and "with" or "without") .. " boss units")

    -- The real group preview on a profile that enabled Friendly bosses (for
    -- example imported from a client that has them).
    env.MSUF_ActiveProfile = "Default"
    env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
    MSUF.GF.EnsureDB()
    M.gfScope = "party"
    local partyConf = M.GroupPage and type(M.GroupPage.Conf) == "function" and M.GroupPage.Conf("party")
        or MSUF.GF.GetConf("party")
    Check(type(partyConf) == "table", "no party configuration")
    partyConf.friendlyBossEnabled = true
    local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    box:Show(); box._stage:SetSize(600, 220)
    box:Refresh("SETTINGS")
    local root = box._additionalPreviewRoots and box._additionalPreviewRoots.friendlyBoss
    if not bossUnits then
        Check(root == nil or not root:IsShown(), "the group preview draws Friendly bosses without boss units")
        Check(not (box._additionalPreviewLayout and box._additionalPreviewLayout.friendlyBoss),
            "the group preview lays out Friendly bosses without boss units")
    end
    partyConf.friendlyBossEnabled = nil

    -- 2. Group mock aura icons are icon file IDs from the unit preview's set,
    -- which exist on every client; spell IDs resolved to the question mark
    -- wherever the spell does not exist.
    local PREVIEW_ICONS = {}
    for _, id in ipairs({ 135987, 136116, 135932, 136085, 132333, 135981, 136048, 135964,
        136118, 136139, 136197, 135817, 132851, 136188, 136170, 135813 }) do PREVIEW_ICONS[id] = true end
    -- No spell resolves here, as on a client that lacks the old mock spells.
    env.C_Spell = { GetSpellTexture = function() return nil end }
    env.GetSpellInfo = function() return nil end
    box:Refresh("SETTINGS")
    local state = box._msufGFRenderState
    local checked = 0
    for _, field in ipairs({ "buffHandle", "trackedBuffHandle", "debuffHandle", "externalHandle" }) do
        local handle = state and state[field]
        for i = 1, #(handle and handle._icons or {}) do
            local icon = handle._icons[i]
            if icon.texture ~= nil then
                checked = checked + 1
                Check(type(icon.texture) == "number" and PREVIEW_ICONS[icon.texture],
                    "the " .. field .. " mock aura " .. i .. " shows " .. tostring(icon.texture) .. " instead of a preview icon file ID")
            end
        end
    end
    Check(checked > 0, "harness: the group preview painted no mock aura icon")
    box:Hide()
end

-- 3. Portrait texture coordinates without a compiled spec -------------------
-- The fallback must compile exactly what the unit config compiles: zoom, the
-- holder's aspect ratio, pan and flip (Shared.CompilePortraitTexCoords).
do
    local Preview = MSUF.UFPreview
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "player" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show(); box.canvas:SetSize(400, 200)
    local player = env.MSUF_DB.player
    local FIELDS = { "portraitMode", "portraitRender", "portraitShape", "portraitSizeMode", "portraitWidth",
        "portraitHeight", "portraitZoom", "portraitPanX", "portraitPanY", "portraitFlip" }
    local saved = {}
    for _, field in ipairs(FIELDS) do saved[field] = player[field] end
    player.portraitMode, player.portraitRender, player.portraitShape = "LEFT", "2D", "SQUARE"
    player.portraitSizeMode, player.portraitWidth, player.portraitHeight = "SEPARATE", 60, 30
    player.portraitZoom, player.portraitPanX, player.portraitPanY, player.portraitFlip = 150, 50, -25, true
    MSUF.UF.Config.Refresh()
    local R = Preview.RefreshDeps._RenderState
    local compiled = R.RuntimeSpecForPreviewKey("player")
    Check(compiled and compiled.portrait and compiled.portrait.texL ~= nil, "harness: no compiled player portrait")
    local runtimeSpecFor = R.RuntimeSpecForPreviewKey
    R.RuntimeSpecForPreviewKey = function() return nil end
    Preview.Refresh(box, "MENU_PREVIEW_LIVE_PARITY")
    R.RuntimeSpecForPreviewKey = runtimeSpecFor
    local coords = box.mock.portrait.tex.texCoord
    Check(type(coords) == "table", "harness: the fallback portrait got no texture coordinates")
    local p = compiled.portrait
    local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
    Check(Near(coords[1], p.texL) and Near(coords[2], p.texR) and Near(coords[3], p.texT) and Near(coords[4], p.texB),
        string.format("the fallback portrait crop %.4f %.4f %.4f %.4f differs from the compiled %.4f %.4f %.4f %.4f",
            tonumber(coords[1]) or -1, tonumber(coords[2]) or -1, tonumber(coords[3]) or -1, tonumber(coords[4]) or -1,
            p.texL, p.texR, p.texT, p.texB))
    for _, field in ipairs(FIELDS) do player[field] = saved[field] end
    MSUF.UF.Config.Refresh()
    box:Hide()
end

-- 4. Castbar samples (player) ----------------------------------------------
-- Latency text in the player castbar's time font; channel ticks centred on
-- their offset, five by default, mirrored by a right-to-left fill, on OVERLAY
-- sublevel 7 (Castbars/MSUF_CastbarChannelTicks.lua, MSUF_PlayerCastbarRuntime.lua).
do
    local Preview = MSUF.UFPreview
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "player" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show(); box.canvas:SetSize(400, 200)
    local g = env.MSUF_DB.general
    local FIELDS = { "enablePlayerCastbar", "castbarShowLatencyText", "castbarShowChannelTicks", "castbarAccentLastTick",
        "castbarFillDirection", "castbarTimeFontSize", "castbarPlayerTimeFontSize", "showPlayerCastTime" }
    local saved = {}
    for _, field in ipairs(FIELDS) do saved[field] = g[field] end
    g.enablePlayerCastbar, g.castbarShowLatencyText, g.castbarShowChannelTicks, g.castbarAccentLastTick = true, true, true, true
    g.castbarTimeFontSize, g.castbarPlayerTimeFontSize, g.showPlayerCastTime = 9, 21, false
    local castbar = env.MSUF_DB.player.castbar or {}
    env.MSUF_DB.player.castbar = castbar
    local savedCustom = castbar.channelTickUseCustom
    castbar.channelTickUseCustom = false
    for _, direction in ipairs({ "LTR", "RTL" }) do
        g.castbarFillDirection = direction
        MSUF.UF.Config.Refresh()
        Preview.Refresh(box, "MENU_PREVIEW_LIVE_PARITY")
        local samples = box.mock.cast._featureSamples
        Check(samples and samples.latency and samples.latency:IsShown(), "harness: no latency sample")
        local _, latencySize = samples.latency:GetFont()
        local _, timeSize = box.mock.cast.time:GetFont()
        Check(latencySize ~= nil and latencySize == timeSize,
            "the latency sample is " .. tostring(latencySize) .. " px, the player castbar time text " .. tostring(timeSize) .. " px")
        local reverse = direction == "RTL"
        local first
        for i = 1, 5 do
            local marker = samples.ticks[i]
            Check(marker and marker:IsShown(), "channel tick " .. i .. " of the five live markers is missing")
            local point, _, relativePoint, x = marker:GetPoint(1)
            Check(point == "TOP" and relativePoint == (reverse and "TOPRIGHT" or "TOPLEFT"),
                "channel tick " .. i .. " is anchored " .. tostring(point) .. " to " .. tostring(relativePoint)
                .. " instead of centred on its " .. (reverse and "right-to-left" or "left-to-right") .. " offset")
            local _, _, bottomRelative, bottomX = marker:GetPoint(2)
            Check(bottomRelative == (reverse and "BOTTOMRIGHT" or "BOTTOMLEFT") and bottomX == x,
                "channel tick " .. i .. " does not span the bar height on its offset")
            x = tonumber(x) or 0
            Check((reverse and x < 0) or (not reverse and x > 0), "channel tick " .. i .. " sits on the wrong side")
            -- Live spacing: i / (count + 1) of the bar width, five markers.
            first = first or x
            Check(math.abs(x - first * i) < 1e-6, "channel tick " .. i .. " is not at " .. i .. "/6 of the bar")
            local _, sublevel = marker:GetDrawLayer()
            Check(sublevel == 7, "channel tick " .. i .. " is not on OVERLAY sublevel 7")
        end
        Check(not samples.ticks[6], "more than five default channel ticks")
    end
    castbar.channelTickUseCustom = savedCustom
    for _, field in ipairs(FIELDS) do g[field] = saved[field] end
    MSUF.UF.Config.Refresh()
    box:Hide()
end

-- 5. Castbar fill colour ---------------------------------------------------
-- The live target/focus/boss castbars tint through MSUF_ResolveCastbarColors
-- (Castbars/MSUF_CastbarDriver.lua): the custom RGB, else the palette choice.
-- The unit preview painted a fixed teal whenever no custom RGB was set, so a
-- palette choice showed in the menu's colour rows and on the live bar but not
-- in the preview.
do
    local Preview = MSUF.UFPreview
    local resolve = env.MSUF_ResolveCastbarColors
    Check(type(resolve) == "function", "harness: the core publishes no MSUF_ResolveCastbarColors")
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "player" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show(); box.canvas:SetSize(400, 200)
    local g = env.MSUF_DB.general
    local FIELDS = { "enablePlayerCastbar", "castbarInterruptibleColor", "castbarInterruptibleR",
        "castbarInterruptibleG", "castbarInterruptibleB" }
    local saved = {}
    for _, field in ipairs(FIELDS) do saved[field] = g[field] end
    g.enablePlayerCastbar = true
    local OLD_FIXED = { 0.0, 0.9, 0.8 }
    local function PreviewFill(label)
        MSUF.UF.Config.Refresh()
        Preview.Refresh(box, "MENU_PREVIEW_LIVE_PARITY")
        local color = box.mock.cast.fill.vertexColor
        Check(type(color) == "table", "harness: the castbar preview painted no fill colour (" .. label .. ")")
        return color
    end
    for _, key in ipairs({ "red", "yellow", "turquoise" }) do
        g.castbarInterruptibleColor = key
        g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB = nil, nil, nil
        local r, gr, b = resolve()
        local color = PreviewFill(key)
        Check(color[1] == r and color[2] == gr and color[3] == b,
            string.format("palette choice %s without a custom RGB: the preview fill is %s/%s/%s, the live castbar resolves %s/%s/%s",
                key, tostring(color[1]), tostring(color[2]), tostring(color[3]), tostring(r), tostring(gr), tostring(b)))
        if key ~= "turquoise" then
            Check(not (r == OLD_FIXED[1] and gr == OLD_FIXED[2] and b == OLD_FIXED[3]),
                "harness: the " .. key .. " palette resolves to the old fixed teal, so the check proves nothing")
        end
    end
    g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB = 0.25, 0.5, 0.75
    local color = PreviewFill("custom")
    local r, gr, b = resolve()
    Check(r == 0.25 and gr == 0.5 and b == 0.75, "harness: the live castbar ignores the custom RGB")
    Check(color[1] == r and color[2] == gr and color[3] == b, "the preview fill ignores the custom RGB the live castbar uses")
    for _, field in ipairs(FIELDS) do g[field] = saved[field] end
    MSUF.UF.Config.Refresh()
    box:Hide()
end

print(string.format("menu_preview_live_parity_smoke: ok (%s)", flavor))
