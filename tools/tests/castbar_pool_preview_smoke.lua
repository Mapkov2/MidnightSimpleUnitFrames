-- castbar_pool_preview_smoke.lua <repoRoot>
--
-- Boss and arena castbar previews are one module: MSUF_CastbarPoolPreviews.lua
-- builds a preview object per pool kind from the pool descriptor plus the
-- preview descriptor in MSUF_BossCastbars_Preview.lua / MSUF_ArenaCastbars_Preview.lua,
-- and MSUF_CastbarPreviews.lua runs test mode, Edit Mode setup, drag
-- positioning, hide-all and the Menu2 page preview over those objects. This
-- smoke loads the real files in TOC order into a recording fake client and
-- pins, for both kinds: slot names and counts, the visibility gates, the
-- anchoring, the fill and target-name styling, the boss batch, every public
-- global, and the shared CastbarPreviews paths.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()

local CASTBARS = "MidnightSimpleUnitFrames/Castbars/"
local LOAD_ORDER = {
    "MSUF_CastbarPreviews.lua",
    "MSUF_CastbarPools.lua",
    "MSUF_CastbarPoolPreviews.lua",
    "MSUF_BossCastbars.lua",
    "MSUF_BossCastbars_Preview.lua",
    "MSUF_ArenaCastbars.lua",
    "MSUF_ArenaCastbars_Preview.lua",
}

local function Check(ok, message)
    if not ok then error("castbar_pool_preview_smoke: " .. message, 2) end
end

-- 1. Every client loads the preview module between the pool module and the
--    first preview descriptor.
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do
    local position = {}
    for index, path in ipairs(manifest.Paths(root, flavor)) do
        position[path:match("([^/]+)$")] = index
    end
    for index = 2, #LOAD_ORDER do
        local previous, current = position[LOAD_ORDER[index - 1]], position[LOAD_ORDER[index]]
        Check(previous and current and previous < current,
            flavor .. " TOC does not load " .. LOAD_ORDER[index] .. " after " .. LOAD_ORDER[index - 1])
    end
end

-- 2. Recording fake client.
local BASE_GLOBALS = {}
for key in pairs(_G) do BASE_GLOBALS[key] = true end

-- The sample cast target names are locale keys (every Locales pack).
local LOCALE = {
    ["Cleave Training Dummy"] = "Cleave-Trainingspuppe",
    ["Arena Ally"] = "Arena-Verbuendeter",
}

local function NewWorld(arenaSlots)
    local extra = {}
    for key in pairs(_G) do if not BASE_GLOBALS[key] then extra[#extra + 1] = key end end
    for index = 1, #extra do _G[extra[index]] = nil end

    local W = { unitFrames = {}, combat = false, calls = {} }
    local function Count(name) W.calls[name] = (W.calls[name] or 0) + 1 end
    local Frame = {}
    Frame.__index = Frame
    function Frame:Show() self.shown = true end
    function Frame:Hide() self.shown = false end
    function Frame:SetShown(shown) self.shown = shown and true or false end
    function Frame:IsShown() return self.shown end
    function Frame:ClearAllPoints() self.point = nil end
    function Frame:SetPoint(...) self.point = { ... } end
    function Frame:SetSize(width, height) self.width, self.height = width, height end
    function Frame:SetValue(value) self.value = value end
    function Frame:SetMinMaxValues() end
    function Frame:SetAlpha(alpha) self.alpha = alpha end
    function Frame:SetText(text) self.text = text end
    function Frame:SetTexture() end
    function Frame:SetScale() end
    function Frame:SetScript(name, fn) self.scripts[name] = fn end
    function Frame:RegisterEvent() end
    function Frame:UnregisterAllEvents() end
    function Frame:GetStatusBarTexture()
        self.fill = self.fill or setmetatable({ scripts = {} }, Frame)
        return self.fill
    end
    local function NewFrame(name)
        local frame = setmetatable({ name = name, shown = true, scripts = {} }, Frame)
        if name then _G[name] = frame end
        return frame
    end
    W.NewFrame = NewFrame

    _G.UIParent = NewFrame("UIParent")
    _G.CreateFrame = function(_, name) return NewFrame(name) end
    _G.UnitExists = function() return false end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.UnitIsUnconscious = function() return false end
    _G.C_Timer = { After = function() end }
    _G.GetTime = function() return 50 end
    _G.InCombatLockdown = function() return W.combat end
    _G.UnitAffectingCombat = function() return false end
    _G.MAX_BOSS_FRAMES = 5
    _G.MSUF_MAX_ARENA_FRAMES = arenaSlots
    _G.MSUF_DB = { general = {}, boss = {}, arena = {} }
    _G.MSUF_EnsureCastbarGeneralDB = function() return _G.MSUF_DB.general end
    _G.MSUF_IsPlayerInCombat = function() return W.combat end
    _G.MSUF_ShouldUseMSUFCastbar = function() return true end
    _G.MSUF_CreateCastbarPreviewFrame = function(kind, name, spec)
        local frame = NewFrame(name)
        frame.spec = spec
        frame.statusBar = NewFrame(nil)
        frame.castTargetText = NewFrame(nil)
        frame.castText = NewFrame(nil)
        frame.timeText = NewFrame(nil)
        return frame
    end
    _G.MSUF_HardSyncCastbarPreview = function() Count("HardSync") end
    _G.MSUF_RefreshCastbarFrame = function() Count("Refresh") end
    _G.MSUF_SetupCastbarPreviewEditHandlers = function(frame, unit) frame.editHandlers = unit end
    _G.MSUF_GetBossLayoutDelta = function(index) return 10 * index, -40 * index end
    _G.MSUF_GetArenaLayoutDelta = function(index) return 20 * index, -50 * index end
    -- The providers MSUF_CastbarPreviews.lua requires at load (Kernel/MSUF_Util,
    -- the castbar Utils, Core, Anchors and the player runtime), reduced to what
    -- these preview paths use. Sizes follow the pool settings, as the preview's
    -- own fallback does.
    _G.MSUF_SetTextIfChanged = function(fontString, text) fontString:SetText(text) end
    _G.MSUF_GetCastbarTimeFormat = function() return "CURRENT" end
    _G.MSUF_FormatCastbarTimeText = function(_, remaining) return string.format("%.1f", tonumber(remaining) or 0) end
    _G.MSUF_GetCastbarDesiredSize = function(unit, general, _, fallbackW, fallbackH)
        local kind = tostring(unit):match("^(%a+)")
        return tonumber(general[kind .. "CastbarWidth"]) or fallbackW, tonumber(general[kind .. "CastbarHeight"]) or fallbackH
    end
    _G.MSUF_ApplyPlayerCastbarSizeAndLayout = function(frame, _, width, height) frame:SetSize(width, height) end
    _G.MSUF_GetCastbarAutoAnchorOffsetX = function() return 0 end
    _G.MSUF_ApplyCastbarFrameLayer = function() end
    _G.MSUF_CB_ApplyTexts = function(frame, _, castText)
        if castText ~= nil and frame and frame.castText then frame.castText:SetText(castText) end
    end
    _G.MSUF_ApplyCastbarGlowFade = function() end
    _G.MSUF_ResetCastbarGlowFade = function() end
    _G.MSUF_UpdateCastbarTextures = function() end
    _G.MSUF_PlayerCastbar_UpdateLatencyZone = function() end
    local ns = {
        ExportPublic = function(name, value) _G[name] = value; return value end,
        UF = { frames = W.unitFrames, GetFrame = function(unit) return W.unitFrames[unit] end },
        -- MSUF.Translate (Locales/MSUF_Localization.lua) with a deDE pack.
        Translate = function(text) return LOCALE[text] or text end,
    }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", ns)
    for _, file in ipairs(LOAD_ORDER) do
        assert(loadfile(root .. "/" .. CASTBARS .. file))("MidnightSimpleUnitFrames", ns)
    end
    W.ns = ns
    return W
end

local KINDS = {
    {
        kind = "boss", cap = "Boss", slots = 5, first = "MSUF_BossCastbarPreview", second = "MSUF_BossCastbarPreview2",
        label = "Celestial Ruin", target = "Cleave-Trainingspuppe", fallbackY = -220, batch = true,
    },
    {
        kind = "arena", cap = "Arena", slots = 5, first = "MSUF_ArenaCastbarPreview1", second = "MSUF_ArenaCastbarPreview2",
        label = "Greater Pyroblast", target = "Arena-Verbuendeter", fallbackY = -320, batch = false,
    },
}

local function EditMode(on)
    _G.MSUF_UnitEditModeActive = on
    _G.MSUF_DB.general.castbarPlayerPreviewEnabled = on
end

for _, K in ipairs(KINDS) do
    local kind, cap = K.kind, K.cap
    local W = NewWorld(5)
    local preview = W.ns.Castbars.Pools.previews[kind]
    Check(preview and preview.maxFrames == K.slots, kind .. " preview does not follow the pool slot count")
    for _, name in ipairs({ "Update", "HideAll", "Create", "Position" }) do
        Check(type(_G["MSUF_" .. name .. cap .. "CastbarPreview" .. (name == "HideAll" and "s" or "")]) == "function",
            kind .. " lost the documented preview global for " .. name)
    end
    Check(type(_G["MSUF_Apply" .. cap .. "CastbarPreviewLayout"]) == "function", kind .. " lost its layout global")
    Check((type(_G["MSUF_Begin" .. cap .. "CastbarPreviewBatch"]) == "function") == K.batch
        and (type(_G["MSUF_End" .. cap .. "CastbarPreviewBatch"]) == "function") == K.batch,
        kind .. " batch globals are wrong")
    Check(type(_G["MSUF_Set" .. cap .. "CastbarTestMode"]) == "function"
        and type(_G["MSUF_Setup" .. cap .. "CastbarPreviewEditMode"]) == "function",
        kind .. " lost its test-mode or Edit Mode setup global")

    for index = 1, 3 do W.unitFrames[kind .. index] = W.NewFrame("UF_" .. kind .. index) end
    W.unitFrames[kind .. "3"].shown = false
    local update = _G["MSUF_Update" .. cap .. "CastbarPreview"]

    -- Gates: nothing outside Edit Mode, slots under shown unit frames inside it.
    update()
    Check(_G[K.first] == nil, kind .. " preview was built outside Edit Mode")
    EditMode(true)
    update()
    local first, second = _G[K.first], _G[K.second]
    Check(first and second and first.shown and second.shown, kind .. " previews 1-2 are not shown in Edit Mode")
    Check(_G["MSUF_" .. cap .. "CastbarPreview"] == first, kind .. " slot 1 alias is not published")
    Check(_G[K.first:gsub("1$", "") .. "3"] and not _G[K.first:gsub("1$", "") .. "3"].shown,
        kind .. " preview 3 shows under a hidden unit frame")
    Check(first.unit == kind and first._msufIsPreview and first[preview.kindFlag]
        and first[preview.indexField] == 1 and second[preview.indexField] == 2,
        kind .. " preview identity fields are wrong")
    Check(first.spec.label == K.label and first.spec.strata == "DIALOG" and first.spec.hideFillTexture == true,
        kind .. " preview frame spec changed")

    -- Styling: hidden fill, shown in test mode; the kind's sample target name.
    Check(first.statusBar.MSUF_hideFillTexture == true and first.statusBar.fill.alpha == 0,
        kind .. " preview fill is not hidden")
    Check(first.castTargetText.text == "" and not first.castTargetText.shown, kind .. " target name shows while off")
    _G.MSUF_DB.general["show" .. cap .. "CastTargetName"] = true
    first.MSUF_testMode = true
    _G["MSUF_Apply" .. cap .. "CastbarPreviewLayout"](first, 1)
    Check(first.statusBar.MSUF_hideFillTexture == nil and first.statusBar.fill.alpha == 1,
        kind .. " test-mode fill is not shown")
    Check(first.castTargetText.text == K.target and first.castTargetText.shown, kind .. " sample target name changed")
    first.MSUF_testMode = nil

    -- Anchoring: under the unit frame, detached with the layout delta, fallback.
    local general = _G.MSUF_DB.general
    general[kind .. "CastbarOffsetX"], general[kind .. "CastbarOffsetY"] = 4, -6
    _G["MSUF_Position" .. cap .. "CastbarPreview"](second, 2)
    Check(second.point[1] == "TOPLEFT" and second.point[2] == W.unitFrames[kind .. "2"] and second.point[3] == "BOTTOMLEFT"
        and second.point[4] == 4 and second.point[5] == -9, kind .. " attached preview anchor changed")
    general[kind .. "CastbarDetached"] = true
    _G["MSUF_Position" .. cap .. "CastbarPreview"](second, 2)
    local dx, dy = _G["MSUF_Get" .. cap .. "LayoutDelta"](2)
    Check(second.point[1] == "CENTER" and second.point[2] == _G.UIParent and second.point[4] == 4 + dx
        and second.point[5] == -6 + dy, kind .. " detached preview anchor changed")
    general[kind .. "CastbarDetached"] = false
    W.unitFrames[kind .. "2"] = nil
    _G["MSUF_Position" .. cap .. "CastbarPreview"](second, 2)
    Check(second.point[1] == "TOPRIGHT" and second.point[4] == -416 and second.point[5] == K.fallbackY - 6 - 34,
        kind .. " fallback preview anchor changed")
    W.unitFrames[kind .. "2"] = W.NewFrame("UF_" .. kind .. "2b")

    -- Combat leaves the previews alone; a disabled kind hides them.
    W.combat = true
    first.shown = false
    update()
    Check(first.shown == false, kind .. " preview refreshed in combat")
    W.combat = false
    _G.MSUF_DB[kind].enabled = false
    update()
    Check(not first.shown and not second.shown, kind .. " previews show for a disabled kind")
    _G.MSUF_DB[kind].enabled = true

    -- The page preview survives the persistent option being off.
    EditMode(false)
    update()
    Check(not first.shown, kind .. " preview shows with the option off")
    Check(_G.MSUF_ApplyCastbarPagePreviewState(kind) == kind, kind .. " page preview did not activate")
    Check(first.shown and first.MSUF_testMode and first.scripts.OnUpdate, kind .. " page preview does not animate")
    update()
    Check(first.shown, kind .. " page preview lost a texture/layout re-apply")
    _G.MSUF_ApplyCastbarPagePreviewState(nil)
    Check(not first.shown and not first.MSUF_testMode, kind .. " page preview was not restored")

    -- Test mode: saved switch, every slot animates, transient off keeps the key.
    local setTest = _G["MSUF_Set" .. cap .. "CastbarTestMode"]
    EditMode(true)
    setTest(true)
    Check(general[kind .. "CastbarTestMode"] == true, kind .. " test mode switch not saved")
    for index = 1, K.slots do
        local frame = _G[preview:Name(index)]
        Check(frame and frame.MSUF_testMode and frame.unit == kind, kind .. " test mode missed slot " .. index)
    end
    -- A transient off (Edit Mode sync) never overrides the saved switch.
    setTest(false, true)
    Check(general[kind .. "CastbarTestMode"] == true and first.MSUF_testMode,
        kind .. " transient test-mode off overrode the saved switch")
    setTest(false)
    Check(general[kind .. "CastbarTestMode"] == false and not first.MSUF_testMode
        and first.statusBar.MSUF_hideFillTexture == true, kind .. " test mode off left the animation")

    -- Edit Mode setup and drag positioning reach every slot.
    _G["MSUF_Setup" .. cap .. "CastbarPreviewEditMode"]()
    Check(first.editHandlers == kind and second.editHandlers == kind, kind .. " Edit Mode setup missed a slot")
    first.point, second.point = nil, nil
    Check(_G.MSUF_PositionCastbarPreviewUnit(kind .. "2") == true and first.point and second.point,
        kind .. " drag did not position every preview")
    Check(_G.MSUF_PositionCastbarPreviewUnit(kind .. "x") == false, kind .. " drag accepted a foreign unit token")

    -- Hide-all clears every slot of both kinds.
    setTest(true)
    _G.MSUF_HideAllCastbarPreviews()
    for index = 1, K.slots do
        local frame = _G[preview:Name(index)]
        Check(not frame.shown and not frame.MSUF_testMode and frame.statusBar.MSUF_hideFillTexture == true,
            kind .. " hide-all left slot " .. index)
    end
    Check(general[kind .. "CastbarTestMode"] == false, kind .. " hide-all kept the test-mode switch")

    -- Boss only: a batch folds every refresh into one pass.
    if K.batch then
        EditMode(true)
        W.calls.HardSync = 0
        _G.MSUF_BeginBossCastbarPreviewBatch()
        update()
        update()
        Check(W.calls.HardSync == 0, "boss batch did not hold the refresh back")
        _G.MSUF_EndBossCastbarPreviewBatch()
        Check(W.calls.HardSync == 2, "boss batch did not run exactly one refresh (2 shown slots)")
    end
end

-- 3. The arena kind follows the client slot count (3 on Mainline).
local W3 = NewWorld(3)
Check(W3.ns.Castbars.Pools.previews.arena.maxFrames == 3, "arena previews ignore MSUF_MAX_ARENA_FRAMES")
for index = 1, 5 do W3.unitFrames["arena" .. index] = W3.NewFrame("UF_arena" .. index) end
EditMode(true)
_G.MSUF_UpdateArenaCastbarPreview()
Check(_G.MSUF_ArenaCastbarPreview3 and not _G.MSUF_ArenaCastbarPreview4, "arena previews built past the slot count")

-- 4. Test mode builds every slot itself: it runs in Edit Mode even while the
--    castbar preview option (and with it the preview refresh) is off.
for _, K in ipairs(KINDS) do
    local W = NewWorld(5)
    _G.MSUF_UnitEditModeActive = true
    _G["MSUF_Set" .. K.cap .. "CastbarTestMode"](true)
    local preview = W.ns.Castbars.Pools.previews[K.kind]
    for index = 1, K.slots do
        local frame = _G[preview:Name(index)]
        Check(frame and frame.shown and frame.MSUF_testMode, K.kind .. " test mode without the preview option missed slot " .. index)
    end
end

print("castbar_pool_preview_smoke: ok (boss and arena previews share one module)")
