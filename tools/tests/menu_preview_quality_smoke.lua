-- menu_preview_quality_smoke.lua <repoRoot> <flavor>
--
-- The options menu previews, checked on the flavor's whole shipped core and
-- Options graph (tools/tests/client_world.lua):
--
--   1. Name shortening follows the unit's compiled text spec (the engine's
--      ResolveNameShortening in UnitFrames/Engine/MSUF_UF_Config.lua, aliases
--      included) and counts characters, never bytes, so a Cyrillic or CJK
--      name is never cut inside a character.
--   2. The unit preview refresh hooks never stack on a global another wrapper
--      took over, and come back at once when the preview is shown again.
--   3. A group preview repaint never walks the live group frames.
--   4. Sweeping Strikes draws all 18 segments (Class Resources and Player).
--   5. The dark bar colour without a settings cache is the engine's.
--   6. The Class Resources preview defers a refresh asked for in combat.
--
-- Plain Lua 5.1 with the repo root and a client matrix Suffix (or Forever).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_preview_quality_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "menu_preview_quality_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local world = World.New(root, flavor)
-- Blizzard's boss frame count, read by the core at load (the harness has none).
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local env, MSUF = world.env, world.core
local widgets = world.widgets
local methods = widgets.Methods
for _, key in ipairs({ "SetStartPoint", "SetEndPoint", "SetThickness", "SetAutoFocus", "SetMaxLetters",
    "EnableKeyboard", "SetNumeric", "SetTextInsets", "ClearFocus", "SetCursorPosition", "HighlightText",
    "SetPropagateKeyboardInput", "SetPropagateMouseWheel", "SetValueStep", "SetObeyStepOnDrag" }) do
    if not methods[key] then methods[key] = function() end end
end
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
for name, method in pairs({
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = Store("thumbTexture"), GetThumbTexture = Fetch("thumbTexture"), SetStepsPerPage = Store("stepsPerPage"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    HasFocus = function() return false end, SetFocus = function() end, GetCursorPosition = function() return 0 end,
    SetTimerDuration = function() end,
    SetScrollChild = Store("scrollChild"), GetScrollChild = Fetch("scrollChild"), SetVerticalScroll = Store("verticalScroll"),
    GetVerticalScroll = function(self) return self.verticalScroll or 0 end, GetVerticalScrollRange = function() return 0 end,
}) do
    if methods[name] == nil then methods[name] = method end
end
-- The stub keeps geometry in plain fields; regions that carry a child named
-- "left" or "bottom" (bar outline pieces) are not a position.
local function Coord(self, field)
    local value = rawget(self, field)
    return type(value) == "number" and value or 0
end
methods.GetCenter = function(self)
    return Coord(self, "left") + Coord(self, "width") / 2, Coord(self, "bottom") + Coord(self, "height") / 2
end
-- A native slider starts at its minimum; the stub leaves the value unset.
local StubGetValue = methods.GetValue
methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end
env.C_Texture = { GetAtlasInfo = function() return nil end }
env.InCombatLockdown = function() return false end
env.MSUF_EnsureDB(true)
local M = Check(MSUF.MSUF2, "Menu2 did not load")

-- A UTF-8 string is well formed: every lead byte has its continuation bytes.
local function ValidUtf8(text)
    local i, n = 1, #text
    while i <= n do
        local b = text:byte(i)
        local extra = b < 0x80 and 0 or (b >= 0xF0 and 3) or (b >= 0xE0 and 2) or (b >= 0xC0 and 1) or -1
        if extra < 0 then return false end
        for k = 1, extra do
            local c = text:byte(i + k)
            if not c or c < 0x80 or c > 0xBF then return false end
        end
        i = i + extra + 1
    end
    return true
end
local function Utf8Chars(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

---------------------------------------------------------------------------
-- 1. Name shortening: characters, compiled settings, engine aliases.
---------------------------------------------------------------------------
do
    local Preview = Check(MSUF.UFPreview, "no unit preview")
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "target" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show(); box.canvas:SetSize(400, 200)
    -- A live target with a ten-character Cyrillic name (twenty bytes).
    local NAME = "\208\144\208\177\208\178\208\179\208\180\208\181\208\182\208\183\208\184\208\186"
    Check(#NAME == 20 and Utf8Chars(NAME) == 10, "harness: the sample name is not 10 two-byte characters")
    env.UnitExists = function(unit) return unit == "target" or unit == "player" end
    env.UnitName = function(unit) if unit == "target" then return NAME end return "Player" end
    local db = env.MSUF_DB
    local function Render()
        MSUF.UF.Config.Refresh()
        Preview.Refresh(box, "MENU_PREVIEW_QUALITY")
        return Check(box.mock and box.mock.nameText, "the target preview has no name text"):GetText()
    end
    db.shortenNames = true
    db.general.shortenNameMaxChars, db.general.shortenNameClipSide, db.general.shortenNameShowDots = 6, "LEFT", true
    db.target.nameTextAnchor = "TOPLEFT"
    local text = Render()
    Check(ValidUtf8(text), "the shortened preview name is not valid UTF-8: " .. text:gsub("[\128-\255]", "?"))
    Check(text == "..." .. NAME:sub(9), "a 10-character name shortened to 6 from the left reads " .. text:gsub("[\128-\255]", "?")
        .. ", not ... and its last 6 characters")
    -- The engine's per-frame aliases: nameClipSide (any case) and nameNoEllipsis.
    db.target.fontOverride, db.target.nameClipSide, db.target.nameNoEllipsis = true, "right", true
    text = Render()
    Check(text == NAME:sub(1, 12), "with the per-frame nameClipSide=right and nameNoEllipsis aliases the name reads "
        .. text:gsub("[\128-\255]", "?") .. ", not its first 6 characters without dots")
    db.target.fontOverride, db.target.nameClipSide, db.target.nameNoEllipsis = nil, nil, nil
    -- The target of target inline name uses its own compiled block (text.inlineToT).
    env.UnitExists = function(unit) return unit == "target" or unit == "player" or unit == "targettarget" end
    env.UnitName = function(unit) if unit == "target" or unit == "targettarget" then return NAME end return "Player" end
    db.targettarget.showToTInTargetName = true
    Render()
    local inline = Check(box.mock.totInlineText, "the target preview has no inline target of target"):GetText()
    Check(inline == "..." .. NAME:sub(9), "the inline target of target name reads " .. tostring(inline):gsub("[\128-\255]", "?")
        .. ", not ... and its last 6 characters")
    db.targettarget.showToTInTargetName = nil
    db.shortenNames = false
    Check(Render() == NAME, "with shortening off the name is not shown in full")
end

---------------------------------------------------------------------------
-- 2. Unit preview refresh hooks (Preview/MSUF_Menu2_UnitPreview_API.lua):
--    a. hiding and showing the preview never stacks a second wrapper on a
--       runtime global that another wrapper (Edit Mode's preview reforce,
--       MSUF_EditMode_Compat.lua) sits on top of;
--    b. a preview shown again right after it was hidden gets its hooks at
--       once, not after the one-second rescan throttle.
---------------------------------------------------------------------------
do
    local Preview = MSUF.UFPreview
    M.frame = M.frame or { IsShown = function() return true end }
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "player" end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box.canvas:SetSize(400, 200)
    local requested = {}
    local RequestRefresh = Preview.RequestRefresh
    Preview.RequestRefresh = function(reason, ...)
        requested[reason] = (requested[reason] or 0) + 1
        return RequestRefresh(reason, ...)
    end
    local function ShowPreview()
        box:Show()
        Preview.RequestRefreshForBox(box, "SHOW")
    end
    local function HidePreview()
        box:Hide()
        Preview.UninstallRefreshHooks()
    end
    local function Calls(name)
        requested[name] = nil
        env[name]()
        return requested[name] or 0
    end
    env.MSUF_UpdateAllFonts = function() end
    env.MSUF_UpdateAllBarTextures = function() end
    ShowPreview()
    Check(Calls("MSUF_UpdateAllFonts") == 1, "the shown preview does not refresh on MSUF_UpdateAllFonts")
    -- Another wrapper takes the global over while the preview's is installed.
    local under = env.MSUF_UpdateAllFonts
    env.MSUF_UpdateAllFonts = function(...) return under(...) end
    for _ = 1, 3 do
        HidePreview()
        widgets:AdvanceTime(2)
        ShowPreview()
    end
    local calls = Calls("MSUF_UpdateAllFonts")
    Check(calls == 1, "after three hide/show cycles one MSUF_UpdateAllFonts call refreshes the preview "
        .. calls .. " times (the wrapper chain grew)")
    HidePreview()
    Check(Calls("MSUF_UpdateAllFonts") == 0, "a hidden preview still refreshes on MSUF_UpdateAllFonts")
    -- Shown again within the rescan throttle.
    ShowPreview()
    Check(Calls("MSUF_UpdateAllBarTextures") == 1, "the preview shown again does not refresh on MSUF_UpdateAllBarTextures")
    HidePreview()
    ShowPreview()
    Check(Calls("MSUF_UpdateAllBarTextures") == 1,
        "a preview shown again right after hiding has no refresh hooks until the 1 s rescan")
    HidePreview()
    Preview.RequestRefresh = RequestRefresh
end

---------------------------------------------------------------------------
-- 3. A group preview repaint never walks the live group frames: the handle
--    strata follow the preview host only (live strata are ignored on purpose,
--    GroupPreview_Render ApplyHandleStrata).
---------------------------------------------------------------------------
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
MSUF.GF.EnsureDB()
local function NewGroupPreview(scope)
    M.gfScope = scope
    local group = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
    group:Show(); group._stage:SetSize(600, 220)
    return group
end
do
    local gf = MSUF.GF
    local walks = 0
    local ForEachFrame = Check(gf.ForEachFrame, "the group runtime has no frame iterator")
    gf.ForEachFrame = function(...)
        walks = walks + 1
        return ForEachFrame(...)
    end
    for _, scope in ipairs({ "party", "raid" }) do
        local group = NewGroupPreview(scope)
        group:Refresh("SETTINGS")
        walks = 0
        for _ = 1, 3 do group:Refresh("SETTINGS") end
        Check(walks == 0, "a " .. scope .. " group preview repaint walks the live group frames " .. walks .. " times in 3 repaints")
        group:Hide()
    end
    gf.ForEachFrame = ForEachFrame
end

---------------------------------------------------------------------------
-- 4. Class Resources preview: Sweeping Strikes draws all 18 segments across
--    the whole bar, as the live bar draws 18 stacks (MSUF_CP_NativeAuras.lua).
---------------------------------------------------------------------------
M.cache = M.cache or {}
M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)
local function BuildShownPage(key)
    local entry = Check(M.BuildPageEntry(key, false), "the " .. key .. " page did not build")
    M.activeKey = key
    widgets:RunTimers(20000)
    return entry
end
local classPowerEntry
do
    classPowerEntry = BuildShownPage("classpower")
    local box = Check(classPowerEntry.classPowerPreview, "the Class Resources page built no preview")
    local GetSpec = M.GetClassPowerPreviewSpec
    M.GetClassPowerPreviewSpec = function()
        return { key = "warrior_sweeping", label = "Warrior - Sweeping Strikes", token = "SWEEPING_STRIKES",
            mode = "aura_segmented", segments = 18, value = 12, previewText = "12" }
    end
    local bars = env.MSUF_DB.bars
    bars.showClassPower = true
    box:Show()
    box:Refresh()
    M.GetClassPowerPreviewSpec = GetSpec
    local frame = Check(box.classPower or box._classPowerFrame or (box._msufCPPreviewAnim and box._msufCPPreviewAnim.classFrame),
        "the Class Resources preview has no class resource frame")
    local shown, right = 0, 0
    for i, bg in ipairs(frame.bgs or {}) do
        if bg:IsShown() then
            shown = shown + 1
            local _, _, _, x = bg:GetPoint(1)
            right = math.max(right, (x or 0) + (bg:GetWidth() or 0))
        end
    end
    Check(shown == 18, "the Sweeping Strikes preview shows " .. shown .. " of 18 segments")
    Check(math.abs(right - frame:GetWidth()) <= 1, string.format(
        "the Sweeping Strikes segments end at x=%d on a %d px bar", right, frame:GetWidth()))
    -- The Player preview on the Class Resources page draws the same resource row.
    local Preview = MSUF.UFPreview
    local parent = env.CreateFrame("Frame", nil, env.UIParent); parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return "player" end
    local unitBox = Preview._BuildPreview(parent, panel, 900, 400)
    unitBox:Show(); unitBox.canvas:SetSize(400, 200)
    M.GetClassPowerPreviewSpec = function()
        return { key = "warrior_sweeping", token = "SWEEPING_STRIKES", mode = "aura_segmented", segments = 18, value = 12 }
    end
    Preview.Refresh(unitBox, "MENU_PREVIEW_QUALITY")
    M.GetClassPowerPreviewSpec = GetSpec
    local unitShown = 0
    for _, segment in ipairs(unitBox.mock.classPower.segments or {}) do
        if segment:IsShown() then unitShown = unitShown + 1 end
    end
    Check(unitShown == 18, "the Player preview on the Class Resources page shows " .. unitShown .. " of 18 Sweeping Strikes segments")
    unitBox:Hide()
end

---------------------------------------------------------------------------
-- 5. The dark bar colour without a settings cache is the engine's own
--    fallback (UF_Config ResolveDarkColor, CP_PlayerHP DarkColor): the saved
--    dark colour, else the dark gray, else 0.07. The unit, group and Class
--    Resources previews all draw it.
---------------------------------------------------------------------------
do
    local general, bars = env.MSUF_DB.general, env.MSUF_DB.bars
    local GetCache = env.MSUF_UFCore_GetSettingsCache
    env.MSUF_UFCore_GetSettingsCache = function() return nil end
    local saved = { general.barMode, general.darkBarR, general.darkBarG, general.darkBarB, general.darkBarGray,
        general.darkBgBrightness }
    general.barMode = "dark"
    local function Same(r, g, b, er, eg, eb)
        return math.abs(r - er) < 1e-6 and math.abs(g - eg) < 1e-6 and math.abs(b - eb) < 1e-6
    end
    local function Expect(where, r, g, b, er, eg, eb)
        Check(Same(r or -1, g or -1, b or -1, er, eg, eb), string.format("%s dark colour is %s,%s,%s, the engine draws %s,%s,%s",
            where, tostring(r), tostring(g), tostring(b), er, eg, eb))
    end
    local Model = Check(MSUF.UFPreview.Model, "no unit preview model")
    local group = NewGroupPreview("party")
    local groupState = Check(group._msufGFRenderState, "no group preview render state")
    local conf = M.GroupPage.Conf("party")
    local savedMode = conf.gfBarMode
    conf.gfBarMode = "dark"
    local cpBox = classPowerEntry.classPowerPreview
    bars.playerHPBarEnabled, bars.playerHPBarColorMode = true, "DARK"
    for _, case in ipairs({
        { label = "saved colour", r = 0.2, g = 0.3, b = 0.4, want = { 0.2, 0.3, 0.4 } },
        { label = "dark gray", gray = 0.15, want = { 0.15, 0.15, 0.15 } },
        { label = "dark background brightness", brightness = 0.12, want = { 0.12, 0.12, 0.12 } },
        { label = "no setting", want = { 0.07, 0.07, 0.07 } },
    }) do
        general.darkBarR, general.darkBarG, general.darkBarB = case.r, case.g, case.b
        general.darkBarGray, general.darkBgBrightness = case.gray, case.brightness
        local w = case.want
        local ur, ug, ub = Model.HealthColor("target", nil)
        Expect("the unit preview (" .. case.label .. ")", ur, ug, ub, w[1], w[2], w[3])
        local gr, gg, gb = groupState.HealthColor(conf, 0.72, "WARRIOR")
        Expect("the group preview (" .. case.label .. ")", gr, gg, gb, w[1], w[2], w[3])
        cpBox:Refresh()
        local fill = Check(cpBox.playerHP and cpBox.playerHP.fill, "the Class Resources preview has no second HP bar")
        local color = fill.vertexColor or {}
        Expect("the Class Resources second HP bar (" .. case.label .. ")", color[1], color[2], color[3], w[1], w[2], w[3])
    end
    conf.gfBarMode = savedMode
    bars.playerHPBarEnabled, bars.playerHPBarColorMode = nil, nil
    general.barMode, general.darkBarR, general.darkBarG, general.darkBarB, general.darkBarGray, general.darkBgBrightness =
        saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
    env.MSUF_UFCore_GetSettingsCache = GetCache
    group:Hide()
end

---------------------------------------------------------------------------
-- 6. The Class Resources preview never renders in combat, like the unit
--    preview: a refresh asked for in combat waits for PLAYER_REGEN_ENABLED.
--    The menu normally closes at combat start; this covers a surface that is
--    still shown (a pinned preview, a direct refresh).
---------------------------------------------------------------------------
do
    local box = classPowerEntry.classPowerPreview
    M.frame = { IsShown = function() return true end }
    M.activeKey = "classpower"
    box._msufCPPreviewWrapper = nil
    box._msufCPPreviewOwnerShown = function() return true end
    box:Show()
    local renders = 0
    local GetSpec = M.GetClassPowerPreviewSpec
    M.GetClassPowerPreviewSpec = function(...)
        renders = renders + 1
        return GetSpec(...)
    end
    -- Spec reads of one full render, out of combat.
    box:Refresh()
    local perRender = renders
    Check(perRender > 0, "harness: a Class Resources render reads no preview spec")
    renders = 0
    env.InCombatLockdown = function() return true end
    M.ClassPowerStackPreview.RequestRefresh(box, "MENU_PREVIEW_QUALITY")
    widgets:RunTimers(20000)
    box:Refresh()
    Check(renders == 0, "the Class Resources preview rendered " .. renders .. " times in combat")
    Check(box:IsEventRegistered("PLAYER_REGEN_ENABLED"), "the Class Resources preview does not wait for the end of combat")
    env.InCombatLockdown = function() return false end
    local onEvent = Check(box:GetScript("OnEvent"), "the Class Resources preview has no event handler")
    onEvent(box, "PLAYER_REGEN_ENABLED")
    Check(renders == perRender, "the Class Resources preview did not render once after combat ("
        .. renders .. " spec reads, " .. perRender .. " per render)")
    Check(not box:IsEventRegistered("PLAYER_REGEN_ENABLED"), "the Class Resources preview keeps listening after combat")
    M.GetClassPowerPreviewSpec = GetSpec
end

print(string.format("menu_preview_quality_smoke: ok (%s)", flavor))
