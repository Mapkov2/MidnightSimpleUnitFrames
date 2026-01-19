local addonName, ns = ...
ns = ns or {}

-- Ensure the Castbars LoD addon is loaded before calling castbar functions.
local function MSUF_EnsureCastbars()
    if type(_G.MSUF_EnsureAddonLoaded) == "function" then
        _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        return
    end
    local loader = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
    if type(loader) == "function" then
        pcall(loader, "MidnightSimpleUnitFrames_Castbars")
    end
end


-- Early tab guard helper
-- Some OnShow handlers call IsFramesTab() before the tab API is constructed.
-- In this build, the controls are only created for the Frames UI anyway, so this must be safe.
local function IsFramesTab()
    return true
end

-- Numeric editbox helper: ensures the number is visible even when set programmatically.
local function MSUF_SetNumericEditBoxValue(edit, v)
    if not edit then return end
    if edit.HasFocus and edit:HasFocus() then return end

    local n = tonumber(v) or 0
    n = math.floor(n + 0.5)

    -- Force a readable font + color in our dark UI.
    if edit.SetFontObject then
        edit:SetFontObject(GameFontHighlightSmall)
    end
    if edit.SetTextColor then
        edit:SetTextColor(1, 1, 1, 1)
    end

    if edit.SetNumber then
        edit:SetNumber(n)
    else
        edit:SetText(tostring(n))
    end

    if edit.SetCursorPosition then
        edit:SetCursorPosition(0)
    end
end


-- Mockup Unitframe Layout (reusable)
-- Left:  Frame Basics + Frame Size
-- Right: Name / HP / Power (X stepper, Y stepper, Size slider)
--
-- IMPORTANT: This module is designed to work in two modes depending on the core:
--  1) Player-only reflector mode (older core): only shows/applies when currentKey == "player".
--  2) Multi-unit mode (newer core): can be shown for any unit key; handlers write to MSUF_DB[currentKey].

local MSUF_PositionLeaderMiniHeaders

-- Shared label helper for the Leader Icon anchor dropdown.
-- Must be file-scope so both CreatePanel() and ApplyFromDB() can use it.
local function MSUF_LeaderAnchorText(v)
    if v == "TOPLEFT" then return "Top left" end
    if v == "TOPRIGHT" then return "Top right" end
    if v == "BOTTOMLEFT" then return "Bottom left" end
    if v == "BOTTOMRIGHT" then return "Bottom right" end
    return "Top left"
end


-- Raid marker anchor text helper (used by dropdown + ApplySettingsForKey)
local function MSUF_RaidMarkerAnchorText(v)
    if v == "CENTER" then return "Center" end
    if v == "TOPRIGHT" then return "Top right" end
    if v == "BOTTOMLEFT" then return "Bottom left" end
    if v == "BOTTOMRIGHT" then return "Bottom right" end
    return "Top left"
end

local function MSUF_LevelAnchorText(v)
    if v == "TOPLEFT" then return "Top left" end
    if v == "TOPRIGHT" then return "Top right" end
    if v == "BOTTOMLEFT" then return "Bottom left" end
    if v == "BOTTOMRIGHT" then return "Bottom right" end
    if v == "NAMELEFT" then return "Left to player name" end
    if v == "NAMERIGHT" then return "Right to player name" end
    return "Right to player name"
end

-- Shared indicator specs for Options_Player (used by ApplyFromDB layout + InstallHandlers)
local _MSUF_INDICATOR_SPECS = {
    leader = {
        id = "leader",
        order = 1,
        allowed = function(key) return (key == "player" or key == "target") end,

        showCB = "playerLeaderIconCB", showField = "showLeaderIcon", showDefault = true,

        xStepper = "playerLeaderOffsetXStepper", xField = "leaderIconOffsetX", xDefault = 0,
        yStepper = "playerLeaderOffsetYStepper", yField = "leaderIconOffsetY", yDefault = 3,

        anchorDrop = "playerLeaderAnchorDrop", anchorLabel = "playerLeaderAnchorLabel",
        anchorField = "leaderIconAnchor", anchorDefault = "TOPLEFT",
        anchorText = function(v) return MSUF_LeaderAnchorText(v) end,
        anchorChoices = {
            { MSUF_LeaderAnchorText("TOPLEFT"), "TOPLEFT" },
            { MSUF_LeaderAnchorText("TOPRIGHT"), "TOPRIGHT" },
            { MSUF_LeaderAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
            { MSUF_LeaderAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
        },


        sizeEdit = "playerLeaderSizeEdit", sizeLabel = "playerLeaderSizeLabel",
        sizeField = "leaderIconSize", sizeDefault = 14,

        divider = "playerLeaderGroupDivider",
        resetBtn = "playerLeaderResetBtn",

        refreshFnName = "MSUF_RefreshLeaderIconFrames",
    },

    raidmarker = {
        id = "raidmarker",
        order = 2,
        allowed = function(_) return true end,

        showCB = "playerRaidMarkerCB", showField = "showRaidMarker", showDefault = true,

        xStepper = "playerRaidMarkerOffsetXStepper", xField = "raidMarkerOffsetX", xDefault = 16,
        yStepper = "playerRaidMarkerOffsetYStepper", yField = "raidMarkerOffsetY", yDefault = 3,

        anchorDrop = "playerRaidMarkerAnchorDrop", anchorLabel = "playerRaidMarkerAnchorLabel",
        anchorField = "raidMarkerAnchor", anchorDefault = "TOPLEFT",
        anchorText = function(v) return MSUF_RaidMarkerAnchorText(v) end,
        anchorChoices = {
            { MSUF_RaidMarkerAnchorText("TOPLEFT"), "TOPLEFT" },
            { MSUF_RaidMarkerAnchorText("TOPRIGHT"), "TOPRIGHT" },
            { MSUF_RaidMarkerAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
            { MSUF_RaidMarkerAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
            { MSUF_RaidMarkerAnchorText("CENTER"), "CENTER" },
        },


        sizeEdit = "playerRaidMarkerSizeEdit", sizeLabel = "playerRaidMarkerSizeLabel",
        sizeField = "raidMarkerSize", sizeDefault = 18,

        divider = "playerRaidMarkerGroupDivider",
        resetBtn = "playerRaidMarkerResetBtn",

        refreshFnName = "MSUF_RefreshRaidMarkerFrames",
    },

    level = {
        id = "level",
        order = 3,
        allowed = function(_) return true end,

        showCB = "playerLevelIndicatorCB", showField = "showLevelIndicator", showDefault = true,

        xStepper = "playerLevelOffsetXStepper", xField = "levelIndicatorOffsetX", xDefault = 0,
        yStepper = "playerLevelOffsetYStepper", yField = "levelIndicatorOffsetY", yDefault = 0,

        anchorDrop = "playerLevelAnchorDrop", anchorLabel = "playerLevelAnchorLabel",
        anchorField = "levelIndicatorAnchor", anchorDefault = "NAMERIGHT",
        anchorText = function(v) return MSUF_LevelAnchorText(v) end,
        anchorChoices = {
            { MSUF_LevelAnchorText("NAMERIGHT"), "NAMERIGHT" },
            { MSUF_LevelAnchorText("NAMELEFT"), "NAMELEFT" },
            { MSUF_LevelAnchorText("TOPLEFT"), "TOPLEFT" },
            { MSUF_LevelAnchorText("TOPRIGHT"), "TOPRIGHT" },
            { MSUF_LevelAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
            { MSUF_LevelAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
        },


        -- (no size controls for Level)
        sizeEdit = nil,
        sizeLabel = nil,
        sizeField = nil,

        divider = "playerLevelGroupDivider",
        resetBtn = "playerLevelResetBtn",

        refreshFnName = "MSUF_RefreshLevelIndicatorFrames",
    },
}

-- ============================================================
-- Step 4B: ApplyFromDB refactor helpers (spec-driven apply)
-- ============================================================

local MSUF_INDICATOR_ORDER = { "leader", "raidmarker", "level" }

local function MSUF_ReadBool(conf, g, field, defaultVal)
    local v = conf and conf[field]
    if v == nil and g then v = g[field] end
    if v == nil then v = defaultVal end
    return (v ~= false)
end

local function MSUF_ReadNumber(conf, g, field, defaultVal)
    local v = conf and conf[field]
    if type(v) ~= "number" then v = nil end
    if v == nil and g then
        local gv = g[field]
        if type(gv) == "number" then v = gv end
    end
    if v == nil then v = defaultVal end
    return v
end

local function MSUF_ReadString(conf, g, field, defaultVal)
    local v = conf and conf[field]
    if type(v) ~= "string" then v = nil end
    if v == nil and g then
        local gv = g[field]
        if type(gv) == "string" then v = gv end
    end
    if v == nil then v = defaultVal end
    return v
end


-- ============================================================
-- Step 4C: Portrait + Alpha + BossSpacing in Specs/Loops
-- ============================================================

local MSUF_PORTRAIT_OPTIONS = {
    { value = "OFF",      text = "Portrait Off" },
    { value = "2D_LEFT",  text = "2D Portrait Left" },
    { value = "2D_RIGHT", text = "2D Portrait Right" },
    { value = "3D_LEFT",  text = "3D Portrait Left" },
    { value = "3D_RIGHT", text = "3D Portrait Right" },
}

-- Target-of-Target inline-in-Target separator dropdown (token stored in MSUF_DB.targettarget.totInlineSeparator).
-- UI shows the raw token; runtime renders it with spaces around it (legacy: " | ").
local MSUF_TOTINLINE_SEP_OPTIONS = {
    { value = ".",   text = "."   },
    { value = "-",   text = "-"   },
    { value = "/",   text = "/"   },
    { value = "\\",  text = "\\"  },
    { value = "|",   text = "|"   },
    { value = "<<<", text = "<<<" },
    { value = ">>>", text = ">>>" },
    -- optional extras (UTF-8 is fine in Lua sources)
    { value = "•",   text = "•"   },
    { value = "—",   text = "—"   },
    { value = "·",   text = "·"   },
    { value = ">",   text = ">"   },
    { value = "<",   text = "<"   },
}

-- Fast validation for ToT-inline separator tokens (keeps dropdown checked-state stable
-- even if profiles/imports contain unknown values).
local MSUF_TOTINLINE_SEP_LOOKUP = {}
do
    for i = 1, #MSUF_TOTINLINE_SEP_OPTIONS do
        local v = MSUF_TOTINLINE_SEP_OPTIONS[i] and MSUF_TOTINLINE_SEP_OPTIONS[i].value
        if type(v) == "string" and v ~= "" then
            MSUF_TOTINLINE_SEP_LOOKUP[v] = true
        end
    end
end

local function MSUF_ToTInlineSepTokenText(v)
    if type(v) ~= "string" or v == "" then return "|" end
    if not MSUF_TOTINLINE_SEP_LOOKUP[v] then return "|" end
    return v
end

local function MSUF_PortraitModeText(mode)
    if mode == "2D_LEFT" then return "2D Portrait Left" end
    if mode == "2D_RIGHT" then return "2D Portrait Right" end
    if mode == "3D_LEFT" then return "3D Portrait Left" end
    if mode == "3D_RIGHT" then return "3D Portrait Right" end
    return "Portrait Off"
end

local function MSUF_GetPortraitDropdownValue(conf)
    if not conf then return "OFF" end
    local pm = conf.portraitMode or "OFF"
    if pm ~= "LEFT" and pm ~= "RIGHT" then
        return "OFF"
    end

    local render = conf.portraitRender
    if render == "3D" then
        return (pm == "LEFT") and "3D_LEFT" or "3D_RIGHT"
    end

    -- Default to 2D for legacy profiles (portraitRender nil/unknown)
    return (pm == "LEFT") and "2D_LEFT" or "2D_RIGHT"
end

local function MSUF_ApplyPortraitChoice(conf, choice)
    if not conf then return end

    if choice == "OFF" then
        conf.portraitMode = "OFF"
        return
    end

    if choice == "2D_LEFT" then
        conf.portraitMode = "LEFT"
        conf.portraitRender = "2D"
        return
    end
    if choice == "2D_RIGHT" then
        conf.portraitMode = "RIGHT"
        conf.portraitRender = "2D"
        return
    end

    if choice == "3D_LEFT" then
        conf.portraitMode = "LEFT"
        conf.portraitRender = "3D"
        return
    end
    if choice == "3D_RIGHT" then
        conf.portraitMode = "RIGHT"
        conf.portraitRender = "3D"
        return
    end

    -- Fallback
    conf.portraitMode = "OFF"
end

local function MSUF_BindPortraitDropdown(panel, fieldName, IsFramesTabFn, EnsureKeyDBFn, ApplyFn)
    local dd = panel and panel[fieldName]
    if not dd or not UIDropDownMenu_Initialize then return end

    local function OnClick(btn, arg1)
        if IsFramesTabFn and not IsFramesTabFn() then return end
        local conf = EnsureKeyDBFn and EnsureKeyDBFn()
        if not conf then return end

        local choice = (btn and btn.value) or arg1 or "OFF"

        MSUF_ApplyPortraitChoice(conf, choice)

        -- Sync dropdown UI based on current frame config (not global state)
        local cur = MSUF_GetPortraitDropdownValue(conf)
        if UIDropDownMenu_SetSelectedValue then
            UIDropDownMenu_SetSelectedValue(dd, cur)
        end
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(dd, MSUF_PortraitModeText(cur))
        end

        if ApplyFn then ApplyFn() end

        -- Hard-sync portrait visuals immediately. Some core paths skip portrait updates
        -- when portraitMode is OFF, so we must explicitly hide the 3D model if it was
        -- previously visible.
        local getKey = panel and panel._msufGetCurrentKey
        local key = (type(getKey) == "function") and getKey() or nil
        local sync = _G and _G.MSUF_3DPortraits_SyncUnit
        if key and type(sync) == "function" then
            pcall(sync, key)
        end
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        if not level or level ~= 1 then return end
        for _, opt in ipairs(MSUF_PORTRAIT_OPTIONS or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.text
            info.value = opt.value
            info.func  = OnClick
            info.arg1  = opt.value
            info.checked = function()
                local conf = EnsureKeyDBFn and EnsureKeyDBFn()
                local cur = MSUF_GetPortraitDropdownValue(conf)
                return (cur == opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local function MSUF_BindDropdown(panel, fieldName, confKey, options, textFn, IsFramesTabFn, EnsureKeyDBFn, ApplyFn)
    local dd = panel and panel[fieldName]
    if not dd or not UIDropDownMenu_Initialize then return end

    local function OnClick(btn, arg1)
        if IsFramesTabFn and not IsFramesTabFn() then return end
        local conf = EnsureKeyDBFn and EnsureKeyDBFn()
        if not conf then return end

        local value = (btn and btn.value) or arg1 or (options and options[1] and options[1].value) or "OFF"
        conf[confKey] = value

        if UIDropDownMenu_SetSelectedValue then
            UIDropDownMenu_SetSelectedValue(dd, value)
        end
        if UIDropDownMenu_SetText and textFn then
            UIDropDownMenu_SetText(dd, textFn(value))
        end

        if ApplyFn then ApplyFn() end
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        if not level or level ~= 1 then return end
        for _, opt in ipairs(options or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.text
            info.value = opt.value
            info.func  = OnClick
            info.arg1  = opt.value
            -- safe checked function, don’t rely on btn.text being non-nil
            info.checked = function()
                local conf = EnsureKeyDBFn and EnsureKeyDBFn()
                local v = conf and conf[confKey]
                return (v == opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

local MSUF_ALPHA_SLIDER_SPECS = {
    { field = "playerAlphaInCombatSlider",  key = "alphaInCombat",     otherField = "playerAlphaOutCombatSlider", otherKey = "alphaOutOfCombat" },
    { field = "playerAlphaOutCombatSlider", key = "alphaOutOfCombat",  otherField = "playerAlphaInCombatSlider",  otherKey = "alphaInCombat" },
}


local function MSUF_ApplyCheck(panel, widgetKey, show, checked)
    if not panel or not widgetKey then return end
    local w = panel[widgetKey]
    if not w then return end
    if w.SetShown then w:SetShown(show and true or false) end
    if show and w.SetChecked then w:SetChecked(checked and true or false) end
end

local function MSUF_ApplyDropdown(panel, widgetKey, show, value, textLabel)
    if not panel or not widgetKey then return end
    local d = panel[widgetKey]
    if not d then return end
    if d.SetShown then d:SetShown(show and true or false) end
    if show then
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(d, value) end
        if UIDropDownMenu_SetText and textLabel then UIDropDownMenu_SetText(d, textLabel) end
    end
end

local function MSUF_GetShowWithFallback(storedValue, fallbackValue)
    if storedValue == nil then
        return (fallbackValue ~= false)
    end
    return (storedValue ~= false)
end

local MSUF_BASIC_CB_SPECS = {
    { w = "playerEnableFrameCB", eval = function(conf) return (conf.enabled ~= false) end },
    { w = "playerShowNameCB",    eval = function(conf) return (conf.showName ~= false) end },
    { w = "playerShowHPCB",      eval = function(conf) return (conf.showHP ~= false) end },
    { w = "playerShowPowerCB",   eval = function(conf) return (conf.showPower ~= false) end },
}

local MSUF_CASTBAR_FRAME_TOGGLE_SPECS = {
    { key = "player", enableW = "playerCastbarEnableCB", enableK = "enablePlayerCastbar", timeW = "playerCastbarTimeCB", timeK = "showPlayerCastTime", interruptW = "playerCastbarInterruptCB" },
    { key = "target", enableW = "targetCastbarEnableCB", enableK = "enableTargetCastbar", timeW = "targetCastbarTimeCB", timeK = "showTargetCastTime", interruptW = "targetCastbarInterruptCB" },
    { key = "focus",  enableW = "focusCastbarEnableCB",  enableK = "enableFocusCastbar",  timeW = "focusCastbarTimeCB",  timeK = "showFocusCastTime",  interruptW = "focusCastbarInterruptCB" },
    { key = "boss",   enableW = "bossCastbarEnableCB",   enableK = "enableBossCastbar",   timeW = "bossCastbarTimeCB",   timeK = "showBossCastTime",   interruptW = "bossCastbarInterruptCB" },
}

local MSUF_CASTBAR_TEXTICON_SPECS = {
    { key = "player", iconW = "playerCastbarShowIconCB", iconK = "castbarPlayerShowIcon", textW = "playerCastbarShowTextCB", textK = "castbarPlayerShowSpellName", textDirect = false },
    { key = "target", iconW = "targetCastbarShowIconCB", iconK = "castbarTargetShowIcon", textW = "targetCastbarShowTextCB", textK = "castbarTargetShowSpellName", textDirect = false },
    { key = "focus",  iconW = "focusCastbarShowIconCB",  iconK = "castbarFocusShowIcon",  textW = "focusCastbarShowTextCB",  textK = "castbarFocusShowSpellName",  textDirect = false },
    { key = "boss",   iconW = "bossCastbarShowIconCB",   iconK = "showBossCastIcon",      textW = "bossCastbarShowTextCB",   textK = "showBossCastName",           textDirect = true },
}

-- Copy-to-all confirmation dialog helper (used by Copy To dropdowns).
-- UI-safe: uses a standard StaticPopup YES/NO confirmation.
local function MSUF_EnsureCopyToAllDialog()
    if not StaticPopupDialogs then return end
    if StaticPopupDialogs["MSUF_COPY_TO_ALL_CONFIRM"] then return end

    StaticPopupDialogs["MSUF_COPY_TO_ALL_CONFIRM"] = {
        text = "Copy these settings to ALL unitframes?\n\nThis will overwrite existing settings on Player/Target/Focus/Boss/Pet/Target of Target.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(self, data)
            if type(data) == "function" then
                data()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function MSUF_ConfirmCopyToAll(callback)
    if type(callback) ~= "function" then return end
    MSUF_EnsureCopyToAllDialog()
    if StaticPopup_Show then
        StaticPopup_Show("MSUF_COPY_TO_ALL_CONFIRM", nil, nil, callback)
    else
        callback()
    end
end

_G.MSUF_ConfirmCopyToAll = MSUF_ConfirmCopyToAll


-- ============================================================
-- Copy Engine (deduplicated)
-- ============================================================
-- This used to be implemented as large per-unit inline blocks.
-- Keep it centralized so future fields/behavior changes are one edit.

local MSUF_COPY_BASIC_FIELDS = {
    "enabled",
    "showName",
    "showHP",
    "showPower",
    "portraitMode",
    "portraitRender",
    "alphaInCombat",
    "alphaOutOfCombat",
    "alphaSync",
}

local MSUF_COPY_INDICATOR_FIELDS = {
    "showLeaderIcon",
    "leaderIconOffsetX",
    "leaderIconOffsetY",
    "leaderIconAnchor",
    "leaderIconSize",

    "showRaidMarker",
    "raidMarkerOffsetX",
    "raidMarkerOffsetY",
    "raidMarkerAnchor",
    "raidMarkerSize",

    "showLevelIndicator",
    "levelIndicatorOffsetX",
    "levelIndicatorOffsetY",
    "levelIndicatorAnchor",
    "levelIndicatorSize",
}

local function MSUF_CanonUnitKey(k)
    if not k then return nil end
    if type(k) ~= "string" then return k end
    k = k:lower()
    if k:match("^boss") then return "boss" end
    if k == "tot" or k == "targetoftarget" or k == "target_of_target" or k == "targettarget" then
        return "targettarget"
    end
    return k
end

local function MSUF_EnsureDB_IfPossible(api)
    -- EnsureDB is typically provided by core (global). Fall back to api.EnsureDB if available.
    if type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    elseif type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    elseif api and type(api.EnsureDB) == "function" then
        api.EnsureDB()
    end
end

local function MSUF_EnsureUnitDB(key)
    MSUF_DB = MSUF_DB or {}
    local k = MSUF_CanonUnitKey(key)
    if not k then return nil, nil end

    if k == "targettarget" then
        -- keep alias in sync for older builds
        MSUF_DB.targettarget = MSUF_DB.targettarget or MSUF_DB.tot or {}
        MSUF_DB.tot = MSUF_DB.targettarget
        return MSUF_DB.targettarget, "targettarget"
    end

    MSUF_DB[k] = MSUF_DB[k] or {}
    return MSUF_DB[k], k
end

local function MSUF_CopyFieldList(dst, src, fields)
    if not dst or not src or not fields then return end
    for i = 1, #fields do
        local f = fields[i]
        dst[f] = src[f]
    end
end

local function MSUF_GetCastbarKeysForUnit(unitKey)
    unitKey = MSUF_CanonUnitKey(unitKey)
    if unitKey == "player" then
        return { enable = "enablePlayerCastbar", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", name = "castbarPlayerShowSpellName" }
    elseif unitKey == "target" then
        return { enable = "enableTargetCastbar", time = "showTargetCastTime", icon = "castbarTargetShowIcon", name = "castbarTargetShowSpellName" }
    elseif unitKey == "focus" then
        return { enable = "enableFocusCastbar", time = "showFocusCastTime", icon = "castbarFocusShowIcon", name = "castbarFocusShowSpellName" }
    elseif unitKey == "boss" then
        return { enable = "enableBossCastbar", time = "showBossCastTime", icon = "showBossCastIcon", name = "showBossCastName" }
    end
    return nil
end

local function MSUF_CopyCastbarSettings(g, srcUnit, dstUnit)
    if not g then return end
    srcUnit = MSUF_CanonUnitKey(srcUnit)
    dstUnit = MSUF_CanonUnitKey(dstUnit)

    local srcKeys = MSUF_GetCastbarKeysForUnit(srcUnit)
    local dstKeys = MSUF_GetCastbarKeysForUnit(dstUnit)
    if not srcKeys or not dstKeys then return end

    g[dstKeys.enable] = g[srcKeys.enable]
    g[dstKeys.time]   = g[srcKeys.time]
    g[dstKeys.icon]   = g[srcKeys.icon]
    g[dstKeys.name]   = g[srcKeys.name]
end

local function MSUF_CopyUnitSettings(srcKey, destKey, api)
    api = api or nil

    MSUF_EnsureDB_IfPossible(api)
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}

    srcKey = MSUF_CanonUnitKey(srcKey) or "player"
    destKey = (type(destKey) == "string") and destKey or "target"
    destKey = destKey:lower()

    local g = MSUF_DB.general

    local src, srcCanon = MSUF_EnsureUnitDB(srcKey)
    if not src or not srcCanon then return end

    local function CopyOne(toKey)
        local dst, dstCanon = MSUF_EnsureUnitDB(toKey)
        if not dst or not dstCanon then return end
        if dstCanon == srcCanon then return end

        MSUF_CopyFieldList(dst, src, MSUF_COPY_BASIC_FIELDS)
        MSUF_CopyFieldList(dst, src, MSUF_COPY_INDICATOR_FIELDS)

        -- Per-unit castbar interrupt toggle
        dst.showInterrupt = src.showInterrupt

        -- Copy matching castbar settings in general DB (player/target/focus/boss)
        MSUF_CopyCastbarSettings(g, srcCanon, dstCanon)

        if api and api.ApplySettingsForKey then
            api.ApplySettingsForKey(dstCanon)
        end
    end

    if destKey == "all" then
        if _G.MSUF_ConfirmCopyToAll then
            _G.MSUF_ConfirmCopyToAll(function()
                local keys = { "player", "target", "focus", "boss", "pet", "targettarget" }
                for i = 1, #keys do
                    local k = keys[i]
                    if k ~= srcCanon then
                        CopyOne(k)
                    end
                end

                if _G.MSUF_UpdateCastbarVisuals then
                    _G.MSUF_UpdateCastbarVisuals()
                end
                if _G.MSUF_RefreshAllIndicators then
                    _G.MSUF_RefreshAllIndicators()
                end
            end)
        end
        return
    end

    CopyOne(destKey)

    if _G.MSUF_UpdateCastbarVisuals then
        _G.MSUF_UpdateCastbarVisuals()
    end
    if _G.MSUF_RefreshAllIndicators then
        _G.MSUF_RefreshAllIndicators()
    end
end

local function MSUF_BindAllCopyButtons(panel)
    if not panel then return end

    local function Bind(btn, srcKey, destVar, defaultDest)
        if not btn or btn._msufCopyBound then return end
        btn._msufCopyBound = true

        btn:SetScript("OnClick", function()
            local isFramesTab = (panel._msufIsFramesTab and panel._msufIsFramesTab()) or (type(IsFramesTab) == "function" and IsFramesTab()) or true
            if not isFramesTab then return end

            local api = panel._msufAPI
            local destKey = (destVar and panel[destVar]) or defaultDest
            MSUF_CopyUnitSettings(srcKey, destKey, api)
        end)
    end

    Bind(panel.playerCopyToButton, "player", "_msufCopyDestKey", "target")
    Bind(panel.targetCopyToButton, "target", "_msufCopyDestKey_target", "player")
    Bind(panel.focusCopyToButton,  "focus",  "_msufCopyDestKey_focus",  "target")
    Bind(panel.bossCopyToButton,   "boss",   "_msufCopyDestKey_boss",   "target")
    Bind(panel.petCopyToButton,    "pet",    "_msufCopyDestKey_pet",    "target")
    Bind(panel.totCopyToButton,    "targettarget", "_msufCopyDestKey_tot", "player")
end


local function CreateGroupBox(parent, title, x, y, w, h, texWhite, texWhite2)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    box:SetBackdrop({
        bgFile = texWhite or "Interface\\Buttons\\WHITE8X8",
        edgeFile = texWhite2 or "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0, 0, 0, 0.25)
    box:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    local titleText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -6)
    titleText:SetText(title or "")

    local divider = box:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -22)
    divider:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -22)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.08)

    box._msufTitleText = titleText
    box._msufDivider = divider
    return box
end

-- Expand the clickable area of a Blizzard UIDropDownMenu so the whole dropdown "box" is clickable,
-- not just the small arrow button. We do this by expanding the Button hit-rect to the dropdown size.
local function MSUF_ExpandDropdownClickArea(dropdown)
    if not dropdown or dropdown._msufClickAreaExpanded then return end
    dropdown._msufClickAreaExpanded = true

    local function Apply()
        local name = dropdown.GetName and dropdown:GetName()
        local btn = dropdown.Button or (name and _G[name .. "Button"])
        if not btn or not btn.SetHitRectInsets then return end

        local dw = tonumber(dropdown:GetWidth()) or 0
        local dh = tonumber(dropdown:GetHeight()) or 0
        local bw = tonumber(btn:GetWidth()) or 0
        local bh = tonumber(btn:GetHeight()) or 0

        local fallbackW = tonumber(dropdown._msufDropWidth) or 0
        if dw <= 1 and fallbackW > 1 then dw = fallbackW end

        -- Defer until we have real sizes (happens after layout/scale is applied).
        if dw <= 1 or dh <= 1 or bw <= 1 or bh <= 1 then
            if _G.C_Timer and type(_G.C_Timer.After) == "function" then
                _G.C_Timer.After(0, Apply)
            end
            return
        end

        local extendLeft = math.max(0, dw - bw)
        local extendTop  = math.max(0, (dh - bh) / 2)

        -- Negative insets expand the hit rect.
        btn:SetHitRectInsets(-extendLeft - 2, -2, -extendTop - 2, -extendTop - 2)
    end

    if dropdown.HookScript then
        dropdown:HookScript("OnShow", Apply)
        dropdown:HookScript("OnSizeChanged", Apply)
    end

    local name = dropdown.GetName and dropdown:GetName()
    local btn = dropdown.Button or (name and _G[name .. "Button"])
    if btn and btn.HookScript then
        btn:HookScript("OnSizeChanged", Apply)
    end

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Apply)
    else
        Apply()
    end
end

local function CreateCheck(parent, name, label, x, y)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if cb.Text then
        cb.Text:SetText(label)
    else
        local t = _G[name .. "Text"]
        if t then t:SetText(label) end
    end
    return cb
end

local function ResizeStepper(stepper, width, editWidth)
    if not stepper or not width then return end
    stepper:SetWidth(width)
    if stepper.editBox and editWidth then
        stepper.editBox:SetWidth(editWidth)
    end
end

-- Restyle a CreateAxisStepper() control to match the requested "no box" look:
-- Only +/- buttons are visible, with the axis label above.
local function RestyleStepperButtonsNoBox(stepper)
    if not stepper then return end
    local eb = stepper.editBox
    local minus = stepper.minusButton
    local plus  = stepper.plusButton

    -- Hide the numeric box entirely (user requested no boxes).
    if eb then
        eb:Hide()
        eb:SetAlpha(0)
        eb:EnableMouse(false)
        eb:ClearAllPoints()
        -- Park it off-screen so it can't affect layout/anchoring.
        eb:SetPoint("TOPLEFT", stepper, "TOPLEFT", -2000, 0)
        eb:SetWidth(1)
    end

    -- Place buttons centered under the label.
    if minus then
        minus:ClearAllPoints()
        minus:SetPoint("LEFT", stepper, "LEFT", 0, 0)
    end
    if plus then
        plus:ClearAllPoints()
        plus:SetPoint("LEFT", (minus or stepper), "RIGHT", 2, 0)
    end

    -- Make the overall control compact.
    local w = 46
    if minus and minus.GetWidth then w = (minus:GetWidth() or 22) + (plus and (plus:GetWidth() or 22) or 0) + 2 end
    stepper:SetWidth(w)
end


local function ClampNumber(v, minVal, maxVal)
    v = tonumber(v) or 0
    if minVal and v < minVal then v = minVal end
    if maxVal and v > maxVal then v = maxVal end
    return v
end

local function FormatSliderValue(slider, value)
    local step = (slider and slider.step) or (slider and slider.GetValueStep and slider:GetValueStep()) or 1
    if step and step >= 1 then
        return tostring(math.floor((value or 0) + 0.5))
    end
    -- keep it simple (2 decimals)
    local precision = 2
    return string.format("%." .. precision .. "f", tonumber(value) or 0)
end

local function ForceSliderEditBox(slider)
    if not slider or not slider.editBox then return end
    if slider.editBox:HasFocus() then return end
    local v = slider.GetValue and slider:GetValue() or 0
    slider.editBox:SetText(FormatSliderValue(slider, v))
end

-- Stepper modifier support (requested):
-- default = 1px, Shift = 5px, Ctrl = 10px
-- Alt = grid step (matches Edit Mode)
-- (Alt > Ctrl > Shift priority)
local function MSUF_GetCurrentGridStep()
    local MIN, MAX = 8, 64
    local step

    local slider = _G and _G["MSUF_EditModeGridSlider"]
    if slider and slider.GetValue then
        step = slider:GetValue()
    elseif MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeGridStep) == "number" then
        step = MSUF_DB.general.editModeGridStep
    else
        step = 20
    end

    step = tonumber(step) or 20
    if step < MIN then step = MIN end
    if step > MAX then step = MAX end
    return step
end

local function MSUF_GetModifierStep(baseStep)
    baseStep = tonumber(baseStep) or 1

    -- Alt: grid step
    if IsAltKeyDown and IsAltKeyDown() then
        return MSUF_GetCurrentGridStep()
    end

    local mult = 1
    if IsControlKeyDown and IsControlKeyDown() then
        mult = 10
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        mult = 5
    end
    return baseStep * mult
end

-- One-time session tip popup for stepper modifiers (Options menu)
local function MSUF_ShowStepperTipOnce(stepper)
    if _G.MSUF_OptionsStepperTipShown then return end
    _G.MSUF_OptionsStepperTipShown = true

    local parent = (stepper and stepper.GetParent and stepper:GetParent()) or UIParent
    if not parent then parent = UIParent end

    local f = parent._msufStepperTipFrame
    if not f then
        f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetSize(430, 22)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0, 0, 0, 0.45)
        f:SetBackdropBorderColor(1, 1, 1, 0.12)

        local t = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetPoint("CENTER", f, "CENTER", 0, 0)
        t:SetText("Tip: Hold SHIFT (5) / CTRL (10) / ALT (grid step) for bigger steps.")
        f.text = t

        f:Hide()
        parent._msufStepperTipFrame = f
    end

    f:ClearAllPoints()
    f:SetPoint("BOTTOM", parent, "BOTTOM", 0, 8)

    local lvl = (parent.GetFrameLevel and parent:GetFrameLevel()) or 0
    if f.SetFrameLevel then f:SetFrameLevel(lvl + 50) end

    f:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function()
            if f and f.Hide then f:Hide() end
        end)
    end
end

local function MSUF_ApplyModifierStepper(stepper)
    if not stepper or not stepper.minusButton or not stepper.plusButton then return end

    stepper.minusButton:SetScript("OnClick", function()
        MSUF_ShowStepperTipOnce(stepper)
        local delta = MSUF_GetModifierStep(stepper.step or 1)
        stepper:SetValue((stepper:GetValue() or 0) - delta, true)
    end)

    stepper.plusButton:SetScript("OnClick", function()
        MSUF_ShowStepperTipOnce(stepper)
        local delta = MSUF_GetModifierStep(stepper.step or 1)
        stepper:SetValue((stepper:GetValue() or 0) + delta, true)
    end)
end

-- BUILD
function ns.MSUF_Options_Player_Build(panel, frameGroup, helpers)
    if not panel or not frameGroup or not helpers then return end

    local CreateAxisStepper = helpers.CreateAxisStepper
    local CreateLabeledSlider = helpers.CreateLabeledSlider
    local texWhite = helpers.texWhite
    local texWhite2 = helpers.texWhite2
    -- Layout constants (GOOD layout)
    local leftX, topY = 8, -110
    local leftW = 250
    local gap = 16
    local rightX = leftX + leftW + gap
    local rightW = 410

    -- Make slider track/line more visible (especially on dark MSUF panels)
    local function MSUF_EnhanceSliderTrack(slider)
        if not slider or slider._msufTrackEnhanced then return end

        -- Create a higher-contrast "rail" behind the slider bar
        local rail = slider:CreateTexture(nil, "BACKGROUND")
        rail:SetPoint("LEFT", slider, "LEFT", 2, 0)
        rail:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
        rail:SetHeight(10)
        rail:SetColorTexture(0, 0, 0, 0.85)

        -- Add a brighter center line to improve readability
        local line = slider:CreateTexture(nil, "BORDER")
        line:SetPoint("LEFT", rail, "LEFT", 0, 0)
        line:SetPoint("RIGHT", rail, "RIGHT", 0, 0)
        line:SetHeight(3)
        line:SetColorTexture(1, 1, 1, 0.65)

        -- Subtle border around the rail (helps against dark backgrounds)
        local bTop = slider:CreateTexture(nil, "BORDER")
        bTop:SetPoint("TOPLEFT", rail, "TOPLEFT", -1, 1)
        bTop:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 1, 1)
        bTop:SetHeight(1)
        bTop:SetColorTexture(1, 1, 1, 0.18)

        local bBot = slider:CreateTexture(nil, "BORDER")
        bBot:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", -1, -1)
        bBot:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 1, -1)
        bBot:SetHeight(1)
        bBot:SetColorTexture(1, 1, 1, 0.18)

        -- Larger thumb for easier grabbing
        local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
        if thumb and thumb.SetSize then
            thumb:SetSize(18, 18)
        end

        slider._msufTrackEnhanced = true
        slider._msufTrackRail = rail
        slider._msufTrackLine = line
        slider._msufTrackBorderTop = bTop
        slider._msufTrackBorderBot = bBot
    end



    -- Animated "fill" for alpha sliders (visualizes current alpha as a shrinking/growing bar).
    -- Designed to look like Blizzard slider fill (UI-SliderBar-Fill) and animate from filled->empty smoothly.
    function MSUF_EnableAnimatedAlphaFill(slider)
        if not slider or slider._msufAlphaFillEnabled then return end

        -- Ensure we have the enhanced rail to anchor into
        if not slider._msufTrackRail then
            if MSUF_EnhanceSliderTrack then MSUF_EnhanceSliderTrack(slider) end
        end

        local rail = slider._msufTrackRail
        if not rail then return end

        local insetX, insetY = 2, 2

        local fill = slider:CreateTexture(nil, "ARTWORK")
        fill:SetTexture("Interface\\Buttons\\UI-SliderBar-Fill")
        if fill.SetHorizTile then fill:SetHorizTile(true) end
        fill:SetPoint("TOPLEFT", rail, "TOPLEFT", insetX, -insetY)
        fill:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", insetX, insetY)
        fill:SetWidth(1)
        fill:SetAlpha(0.90)

        slider._msufAlphaFill = fill
        slider._msufAlphaFillInsetX = insetX
        slider._msufAlphaFillInsetY = insetY
        slider._msufAlphaFillCur = nil
        slider._msufAlphaFillTarget = nil
        slider._msufAlphaFillEnabled = true

        -- Dedicated animation driver so we don't stomp any existing OnUpdate on the slider
        local anim = CreateFrame("Frame", nil, slider)
        anim:Hide()
        slider._msufAlphaFillAnim = anim

        local function GetMaxValue()
            if slider.maxVal then return slider.maxVal end
            if slider.GetMinMaxValues then
                local _, mx = slider:GetMinMaxValues()
                return mx
            end
            return 1
        end

        local function Clamp01(x)
            if x < 0 then return 0 end
            if x > 1 then return 1 end
            return x
        end

        local function GetUsableWidth()
            local w = rail.GetWidth and rail:GetWidth() or 0
            if not w or w <= 0 then
                w = slider.GetWidth and slider:GetWidth() or 0
            end
            w = (w or 0) - (insetX * 2)
            if w < 1 then w = 1 end
            return w
        end

        local function ApplyFrac(frac)
            frac = Clamp01(frac or 0)
            local w = GetUsableWidth()
            fill:SetWidth(w * frac)
        end

        local function SetTarget(frac, instant)
            frac = Clamp01(frac or 0)

            if slider._msufAlphaFillCur == nil then
                slider._msufAlphaFillCur = frac
                slider._msufAlphaFillTarget = frac
                ApplyFrac(frac)
                return
            end

            slider._msufAlphaFillTarget = frac

            if instant then
                slider._msufAlphaFillCur = frac
                ApplyFrac(frac)
                anim:Hide()
                return
            end

            -- Start anim
            slider._msufAlphaFillStart = slider._msufAlphaFillCur
            slider._msufAlphaFillStartTime = GetTime()
            slider._msufAlphaFillDur = 0.14
            anim:Show()
        end

        anim:SetScript("OnUpdate", function(self)
            local t0 = slider._msufAlphaFillStartTime
            local dur = slider._msufAlphaFillDur or 0.14
            if not t0 then self:Hide(); return end

            local p = (GetTime() - t0) / dur
            if p >= 1 then
                slider._msufAlphaFillCur = slider._msufAlphaFillTarget
                ApplyFrac(slider._msufAlphaFillCur)
                self:Hide()
                return
            end

            -- easeOutQuad
            local e = 1 - (1 - p) * (1 - p)
            local a = slider._msufAlphaFillStart or 0
            local b = slider._msufAlphaFillTarget or a
            local cur = a + (b - a) * e
            slider._msufAlphaFillCur = cur
            ApplyFrac(cur)
        end)

        local function UpdateFromValue(value, instant)
            local mx = GetMaxValue()
            if not mx or mx <= 0 then mx = 1 end
            local frac = (value or 0) / mx
            SetTarget(frac, instant)
        end

        -- Dragging should feel snappy (no laggy animation while moving the thumb)
        slider:HookScript("OnMouseDown", function() slider._msufAlphaFillDragging = true end)
        slider:HookScript("OnMouseUp", function()
            slider._msufAlphaFillDragging = false
            if slider.GetValue then
                UpdateFromValue(slider:GetValue(), true)
            end
        end)

        slider:HookScript("OnValueChanged", function(_, value)
            UpdateFromValue(value, slider._msufAlphaFillDragging)
        end)

        -- Size changes / first layout pass
        slider:HookScript("OnSizeChanged", function()
            if slider.GetValue then
                UpdateFromValue(slider:GetValue(), true)
            end
        end)

        -- Initial sync next tick (rail width is 0 at creation time sometimes)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if slider and slider.GetValue then
                    UpdateFromValue(slider:GetValue(), true)
                end
            end)
        else
            if slider.GetValue then UpdateFromValue(slider:GetValue(), true) end
        end
    end

    local basicsH = 178
    local sizeH = 170
    local bossExtraH = 60
    local sizeBossH = sizeH + bossExtraH

    -- Left: Frame Basics
    local basicsBox = CreateGroupBox(frameGroup, "Frame Basics", leftX, topY, leftW, basicsH, texWhite, texWhite2)
    basicsBox:Hide()
    panel.playerBasicsBox = basicsBox

    -- Enable/Disable + Display toggles (spec-driven; keep widget names)
    local BASIC_TOGGLES = {
        { field = "playerEnableFrameCB", name = "MSUF_UF_EnableFrameCB", label = "Enable this frame", x = 12, y = -34 },
        { field = "playerShowNameCB",    name = "MSUF_UF_ShowNameCB",   label = "Show name",         x = 12, y = -58 },
        { field = "playerShowHPCB",      name = "MSUF_UF_ShowHPCB",     label = "Show HP text",      x = 12, y = -82 },
        { field = "playerShowPowerCB",   name = "MSUF_UF_ShowPowerCB",  label = "Show power text",   x = 12, y = -106 },
    }
    for _, s in ipairs(BASIC_TOGGLES) do
        panel[s.field] = CreateCheck(basicsBox, s.name, s.label, s.x, s.y)
    end

    -- Portrait dropdown under display toggles.

    local dd = CreateFrame("Frame", "MSUF_UF_PortraitDropDown", basicsBox, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", basicsBox, "TOPLEFT", -6, -130)
    dd:Show() -- portrait dropdown (all unitframes)
    panel.playerPortraitDropDown = dd

    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dd, 170)
    end
    
    dd._msufDropWidth = 170
    MSUF_ExpandDropdownClickArea(dd)

    -- Left: Unit Alpha
    local sizeBox = CreateGroupBox(frameGroup, "Unit Alpha", leftX, topY - basicsH - 12, leftW, sizeH, texWhite, texWhite2)
    sizeBox:Hide()
    panel.playerSizeBox = sizeBox

    -- Store base/boss heights for dynamic boss-only extension
    panel._msufBasicsH = basicsH
    panel._msufSizeBaseH = sizeH
    panel._msufSizeBossH = sizeBossH

    -- Unit Alpha controls (in/out of combat)

    -- Top-right toggle: sync both sliders
    local alphaSyncCB = CreateFrame("CheckButton", "MSUF_UF_AlphaSyncCB", sizeBox, "UICheckButtonTemplate")
    alphaSyncCB:SetPoint("TOPRIGHT", sizeBox, "TOPRIGHT", -12, -6)
    if alphaSyncCB.Text then
        alphaSyncCB.Text:SetText("Sync both")
        alphaSyncCB.Text:ClearAllPoints()
        alphaSyncCB.Text:SetPoint("RIGHT", alphaSyncCB, "LEFT", -4, 0)
        alphaSyncCB.Text:SetJustifyH("RIGHT")
    end
    panel.playerAlphaSyncCB = alphaSyncCB

    local function FinalizeCompactSlider(slider, width, opts)
        if not slider then return end
        slider:SetWidth(width or (leftW - 24))
        if slider.editBox then slider.editBox:Hide() end
        if slider.minusButton then slider.minusButton:Hide() end
        if slider.plusButton then slider.plusButton:Hide() end
        if MSUF_EnhanceSliderTrack then
            MSUF_EnhanceSliderTrack(slider)
        end
        if opts and opts.animatedFill and MSUF_EnableAnimatedAlphaFill then
            MSUF_EnableAnimatedAlphaFill(slider)
        end
    end

    local ALPHA_SPECS = {
        { field = "playerAlphaInCombatSlider",  name = "MSUF_UF_AlphaInCombatSlider",  label = "Alpha in combat",      y = -56 },
        { field = "playerAlphaOutCombatSlider", name = "MSUF_UF_AlphaOutCombatSlider", label = "Alpha out of combat", y = -106 },
    }
    for _, s in ipairs(ALPHA_SPECS) do
        panel[s.field] = CreateLabeledSlider(s.name, s.label, sizeBox, 0.10, 1.00, 0.05, 12, s.y)
        FinalizeCompactSlider(panel[s.field], (leftW - 24), { animatedFill = true })
    end


    -- Right: Text group
    local textGroup = CreateGroupBox(frameGroup, "Castbar", rightX, topY, rightW, basicsH + sizeH + 12, texWhite, texWhite2)
    textGroup:Hide()
    panel.playerTextLayoutGroup = textGroup
    panel._msufTextGroup = textGroup


-- ToT-only utility: show Target-of-Target name inline in the Target frame name line.
panel.totShowInTargetCB = CreateCheck(textGroup, "MSUF_ToTInlineInTargetCB", "Show ToT text in Target frame", 12, -32)
panel.totShowInTargetCB:Hide()

-- Separator dropdown (no title) directly under the toggle.
local totSepDD = CreateFrame("Frame", "MSUF_ToTInlineSeparatorDropDown", textGroup, "UIDropDownMenuTemplate")
-- Anchor to the toggle (not the box) so any future/reflowed layout changes can't "strand" the dropdown.
-- UIDropDownMenuTemplate is left-shifted vs. CheckButtons, hence the -18 X offset.
if panel.totShowInTargetCB then
    totSepDD:SetPoint("TOPLEFT", panel.totShowInTargetCB, "BOTTOMLEFT", -18, -6)
    if totSepDD.SetFrameLevel and panel.totShowInTargetCB.GetFrameLevel then
        totSepDD:SetFrameLevel((panel.totShowInTargetCB:GetFrameLevel() or 0) + 2)
    end
else
    totSepDD:SetPoint("TOPLEFT", textGroup, "TOPLEFT", -6, -52)
end
totSepDD:Hide()
panel.totInlineSeparatorDD = totSepDD
if UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(totSepDD, 170)
end
totSepDD._msufDropWidth = 170
if MSUF_ExpandDropdownClickArea then
    MSUF_ExpandDropdownClickArea(totSepDD)
end


    

    -- Player-only: Player castbar toggles live in the Frames tab -> Text box.

    -- Castbar toggles (Player/Target/Focus/Boss) live in the Frames tab -> Castbar box.
    -- These overlap each other and are shown/hidden based on the selected unitframe tab.
    local CASTBAR_UI_SPECS = {
        { key = "player", cap = "Player", enableText = "Enable player castbar", timeText = "Show player cast time", defaultVisible = true },
        { key = "target", cap = "Target", enableText = "Enable target castbar", timeText = "Show target cast time" },
        { key = "focus",  cap = "Focus",  enableText = "Enable focus castbar",  timeText = "Show focus cast time"  },
        { key = "boss",   cap = "Boss",   enableText = "Enable boss castbars", timeText = "Show boss cast time"   },
    }

    for _, spec in ipairs(CASTBAR_UI_SPECS) do
        local key, cap = spec.key, spec.cap

        panel[key .. "CastbarEnableCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarEnableCB", spec.enableText, 12, -34)
        panel[key .. "CastbarShowIconCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarShowIconCB", "Icon", 230, -34)
        panel[key .. "CastbarShowTextCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarShowTextCB", "Text", 300, -34)
        panel[key .. "CastbarTimeCB"]   = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarTimeCB",   spec.timeText, 12, -58)
        panel[key .. "CastbarInterruptCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarInterruptCB", "Show interrupt", 12, -82)

        if not spec.defaultVisible then
            if panel[key .. "CastbarEnableCB"] then panel[key .. "CastbarEnableCB"]:Hide() end
            if panel[key .. "CastbarShowIconCB"] then panel[key .. "CastbarShowIconCB"]:Hide() end
            if panel[key .. "CastbarShowTextCB"] then panel[key .. "CastbarShowTextCB"]:Hide() end
            if panel[key .. "CastbarTimeCB"] then panel[key .. "CastbarTimeCB"]:Hide() end
            if panel[key .. "CastbarInterruptCB"] then panel[key .. "CastbarInterruptCB"]:Hide() end
        end
    end





		---------------------------------------------------------------------
		-- Indicator (Leader / Raid Marker / Level) — spec-driven build
		-- All layout for other unit tabs is handled by LayoutIndicatorTemplate().
		---------------------------------------------------------------------

		-- Section title (anchored to first divider in LayoutIndicatorTemplate)
		if not panel.playerLeaderIndicatorHeader then
			panel.playerLeaderIndicatorHeader = textGroup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		end
		panel.playerLeaderIndicatorHeader:SetText("Indicator")
		panel.playerLeaderIndicatorHeader:Hide()

		-- Shared layout constants for the indicator template
		local IND_COL_X          = 175
		local IND_BASE_TOGGLE_Y  = -163
		local IND_BASE_CTRL_Y    = -178
		local IND_ROW_STEP       = -64  -- Y offsets are negative: going "down" means more negative.
		local IND_DIVIDER_OFFSET = 23

		panel._msufIndicatorLayout = panel._msufIndicatorLayout or {}
		panel._msufIndicatorLayout.colX          = IND_COL_X
		panel._msufIndicatorLayout.leaderToggleY = IND_BASE_TOGGLE_Y
		panel._msufIndicatorLayout.leaderCtrlY   = IND_BASE_CTRL_Y
		panel._msufIndicatorLayout.rowStep       = IND_ROW_STEP
		panel._msufIndicatorLayout.dividerOffset = IND_DIVIDER_OFFSET

		-- Boss-only: spacing slider (shown only on boss pages by LayoutIndicatorTemplate)
		local bossSpacingY = (IND_BASE_CTRL_Y + (2 * IND_ROW_STEP)) - 42
		panel.playerBossSpacingSlider = panel.playerBossSpacingSlider or CreateLabeledSlider("MSUF_UF_BossSpacingSlider", "Boss spacing", textGroup, -200, 0, 1, 12, bossSpacingY)
		FinalizeCompactSlider(panel.playerBossSpacingSlider, (rightW - 24))
		panel.playerBossSpacingSlider:Hide()
		-- Safety: older refactors called this; now it's not needed (layout is already relative).
		MSUF_PositionLeaderMiniHeaders = MSUF_PositionLeaderMiniHeaders or function() end

		local function _MSUF_GetCheckboxIcon(cb)
			if not cb then return nil end
			return cb.Check or (cb.GetName and _G[cb:GetName() .. "Check"]) or nil
		end

		local function _MSUF_CreateResetButton(field, cb)
			if panel[field] then
				panel[field]:Hide()
				panel[field]:ClearAllPoints()
			else
				panel[field] = CreateFrame("Button", nil, textGroup, "UIPanelButtonTemplate")
				panel[field]:SetSize(20, 20)
				panel[field]:SetText("R")

				local fs = panel[field].GetFontString and panel[field]:GetFontString()
				if fs then
					fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
					fs:ClearAllPoints()
					fs:SetPoint("CENTER", panel[field], "CENTER", 0, 0)
				end

				panel[field]:SetScript("OnEnter", function(self)
					if not GameTooltip then return end
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText("Resets current indicator", 1, 1, 1)
					GameTooltip:AddLine("Resets X/Y, Anchor and Size back to defaults.", 0.85, 0.85, 0.85, true)
					GameTooltip:Show()
				end)
				panel[field]:SetScript("OnLeave", function()
					if GameTooltip then GameTooltip:Hide() end
				end)
			end

			local chk = _MSUF_GetCheckboxIcon(cb)
			if chk then
				panel[field]:SetPoint("TOP", chk, "BOTTOM", 0, -2)
			elseif cb then
				panel[field]:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 2, 2)
			else
				panel[field]:SetPoint("TOPLEFT", textGroup, "TOPLEFT", 12, IND_BASE_CTRL_Y + 2)
			end

			panel[field]:Hide()
			return panel[field]
		end

		local function _MSUF_MakeDivider(field)
			if panel[field] then
				panel[field]:Hide()
				return panel[field]
			end
			local tex = textGroup:CreateTexture(nil, "ARTWORK")
			tex:SetHeight(1)
			tex:SetColorTexture(1, 1, 1, 0.08)
			tex:Hide()
			panel[field] = tex
			return tex
		end

		local function _MSUF_MakeDrop(field, globalName, width)
			if panel[field] then
				panel[field]:Hide()
				return panel[field]
			end
			local dd = CreateFrame("Frame", globalName, textGroup, "UIDropDownMenuTemplate")
			if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, width) end
			dd._msufDropWidth = width
			if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(dd) end
			dd:SetScale(0.80)
			dd:Hide()
			panel[field] = dd
			return dd
		end

		local function _MSUF_MakeLabel(field, text)
			if panel[field] then
				panel[field]:SetText(text)
				panel[field]:Hide()
				return panel[field]
			end
			local fs = textGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetText(text)
			fs:Hide()
			panel[field] = fs
			return fs
		end

		local function _MSUF_MakeSizeEdit(field, globalName)
			if panel[field] then
				panel[field]:Hide()
				return panel[field]
			end
			local eb = CreateFrame("EditBox", globalName, textGroup, "InputBoxTemplate")
			eb:SetAutoFocus(false)
			eb:SetSize(46, 18)
			eb:SetNumeric(true)
			eb:SetMaxLetters(3)
			local font = eb.GetFont and eb:GetFont()
			if font then
				eb:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
			else
				eb:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
			end
			eb:Hide()
			panel[field] = eb
			return eb
		end

		local function _MSUF_LayoutIndicatorRow(cb, stepperX, stepperY, anchorDrop, anchorLabel, sizeEdit, sizeLabel, colX, ctrlY)
			-- X stepper is anchored to container; everything else is relative to it
			if stepperX then
				stepperX:ClearAllPoints()
				stepperX:SetPoint("TOPLEFT", textGroup, "TOPLEFT", colX, ctrlY)
				ResizeStepper(stepperX, 46, 1)
				RestyleStepperButtonsNoBox(stepperX)
				if MSUF_ApplyModifierStepper then MSUF_ApplyModifierStepper(stepperX, 1) end
				if stepperX.label then
					stepperX.label:Show()
					stepperX.label:ClearAllPoints()
					stepperX.label:SetPoint("BOTTOM", stepperX, "TOP", 0, 6)
				end
				stepperX:Hide()
			end

			if stepperY and stepperX then
				stepperY:ClearAllPoints()
				stepperY:SetPoint("LEFT", stepperX, "RIGHT", 6, 0)
				ResizeStepper(stepperY, 46, 1)
				RestyleStepperButtonsNoBox(stepperY)
				if MSUF_ApplyModifierStepper then MSUF_ApplyModifierStepper(stepperY, 1) end
				if stepperY.label then
					stepperY.label:Show()
					stepperY.label:ClearAllPoints()
					stepperY.label:SetPoint("BOTTOM", stepperY, "TOP", 0, 6)
				end
				stepperY:Hide()
			end

			if anchorDrop and stepperY then
				anchorDrop:ClearAllPoints()
				anchorDrop:SetPoint("LEFT", stepperY, "RIGHT", 1, 0)
				if anchorLabel then
					anchorLabel:ClearAllPoints()
					anchorLabel:SetPoint("BOTTOM", anchorDrop, "TOP", 0, 6)
					anchorLabel:Hide()
				end
				anchorDrop:Hide()
			end

			if sizeEdit and anchorDrop then
				sizeEdit:ClearAllPoints()
				sizeEdit:SetPoint("LEFT", anchorDrop, "RIGHT", 1, 2)
				if sizeLabel then
					sizeLabel:ClearAllPoints()
					sizeLabel:SetPoint("BOTTOM", sizeEdit, "TOP", 0, 6)
					sizeLabel:Hide()
				end
				sizeEdit:Hide()
			end

			if cb then cb:Hide() end
		end

		local _MSUF_IND_UI = {
			leader = {
				cbField = "playerLeaderIconCB",
				cbName  = "MSUF_PlayerLeaderIconCB",
				cbText  = "Show leader/assist icon",
				xField  = "playerLeaderOffsetXStepper",
				xName   = "MSUF_PlayerLeaderIconOffsetX",
				yField  = "playerLeaderOffsetYStepper",
				yName   = "MSUF_PlayerLeaderIconOffsetY",
				dropField = "playerLeaderAnchorDrop",
				dropName  = "MSUF_PlayerLeaderIconAnchorDropdown",
				dropW     = 70,
				anchorLabelField = "playerLeaderAnchorLabel",
				sizeField  = "playerLeaderSizeEdit",
				sizeName   = "MSUF_PlayerLeaderIconSizeEdit",
				sizeLabelField = "playerLeaderSizeLabel",
				resetField = "playerLeaderResetBtn",
				dividerField = "playerLeaderGroupDivider",
			},
			raidmarker = {
				cbField = "playerRaidMarkerCB",
				cbName  = "MSUF_PlayerRaidMarkerCB",
				cbText  = "Show raid marker icon",
				xField  = "playerRaidMarkerOffsetXStepper",
				xName   = "MSUF_PlayerRaidMarkerOffsetX",
				yField  = "playerRaidMarkerOffsetYStepper",
				yName   = "MSUF_PlayerRaidMarkerOffsetY",
				dropField = "playerRaidMarkerAnchorDrop",
				dropName  = "MSUF_PlayerRaidMarkerAnchorDropdown",
				dropW     = 70,
				anchorLabelField = "playerRaidMarkerAnchorLabel",
				sizeField  = "playerRaidMarkerSizeEdit",
				sizeName   = "MSUF_PlayerRaidMarkerSizeEdit",
				sizeLabelField = "playerRaidMarkerSizeLabel",
				resetField = "playerRaidMarkerResetBtn",
				dividerField = "playerRaidMarkerGroupDivider",
			},
			level = {
				cbField = "playerLevelIndicatorCB",
				cbName  = "MSUF_PlayerLevelIndicatorCB",
				cbText  = "Show level",
				xField  = "playerLevelOffsetXStepper",
				xName   = "MSUF_PlayerLevelOffsetX",
				yField  = "playerLevelOffsetYStepper",
				yName   = "MSUF_PlayerLevelOffsetY",
				dropField = "playerLevelAnchorDrop",
				dropName  = "MSUF_PlayerLevelAnchorDropdown",
				dropW     = 130,
				anchorLabelField = "playerLevelAnchorLabel",
				resetField = "playerLevelResetBtn",
				dividerField = "playerLevelGroupDivider",
			},
		}

		for idx, id in ipairs({ "leader", "raidmarker", "level" }) do
			local spec = _MSUF_INDICATOR_SPECS and _MSUF_INDICATOR_SPECS[id]
			local ui = _MSUF_IND_UI[id]
			if spec and ui then
				-- Divider texture
				_MSUF_MakeDivider(ui.dividerField)

				-- Toggle
				if not panel[ui.cbField] then
					panel[ui.cbField] = CreateCheck(textGroup, ui.cbName, ui.cbText, 12, (IND_BASE_TOGGLE_Y + ((idx - 1) * IND_ROW_STEP)))
				end
				panel[ui.cbField]:Hide()

				-- Reset button
				_MSUF_CreateResetButton(ui.resetField, panel[ui.cbField])

				-- X/Y steppers
				if not panel[ui.xField] then
					panel[ui.xField] = CreateAxisStepper(ui.xName, "X", textGroup, spec.xDefault or 0, 0, -200, 200, 1)
				end
				if not panel[ui.yField] then
					panel[ui.yField] = CreateAxisStepper(ui.yName, "Y", textGroup, spec.yDefault or 0, 0, -200, 200, 1)
				end

				-- Anchor drop + label
				if ui.dropField then
					panel[ui.dropField] = _MSUF_MakeDrop(ui.dropField, ui.dropName, ui.dropW or 70)
					panel[ui.anchorLabelField] = _MSUF_MakeLabel(ui.anchorLabelField, "Anchor")
				end

				-- Size edit + label (optional)
				if ui.sizeField then
					panel[ui.sizeField] = _MSUF_MakeSizeEdit(ui.sizeField, ui.sizeName)
					panel[ui.sizeLabelField] = _MSUF_MakeLabel(ui.sizeLabelField, "Size")
				end

				-- Relative layout: only X stepper is absolute, everything else follows.
				_MSUF_LayoutIndicatorRow(
					panel[ui.cbField],
					panel[ui.xField],
					panel[ui.yField],
					panel[ui.dropField],
					panel[ui.anchorLabelField],
					panel[ui.sizeField],
					panel[ui.sizeLabelField],
					IND_COL_X,
					IND_BASE_CTRL_Y + ((idx - 1) * IND_ROW_STEP)
				)
			end
		end

    local function _MSUF_BuildCopyUI(spec)
        local prefix    = spec.prefix
        local destVar   = spec.destVar
        local default   = spec.defaultDest
        local items     = spec.items or {}
        local hintText  = spec.hintText or "Copies compatible settings."
        local dropName  = spec.dropName

        local labelKey  = prefix .. "CopyToLabel"
        local dropKey   = prefix .. "CopyToDrop"
        local btnKey    = prefix .. "CopyToButton"
        local hintKey   = prefix .. "CopyToHint"

        if not panel[labelKey] then
            panel[labelKey] = textGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            panel[labelKey]:SetText("Copy to")
            panel[labelKey]:Hide()
        end

        if not panel[dropKey] then
            panel[dropKey] = CreateFrame("Frame", dropName, textGroup, "UIDropDownMenuTemplate")
            if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(panel[dropKey], 150) end
            panel[dropKey]._msufDropWidth = 150
            if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(panel[dropKey]) end
            panel[dropKey]:SetScale(0.86)
            panel[dropKey]:Hide()

            panel[destVar] = panel[destVar] or default

            local function Init(self, level)
                if not level then return end

                local function AddItem(text, value)
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = text
                    info.value = value
                    info.func = function(btn)
                        local v = (btn and btn.value) or value or default
                        panel[destVar] = v
                        self.selectedValue = v
                        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, v) end
                        local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(v)) or tostring(v)
                        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
                        if CloseDropDownMenus then CloseDropDownMenus() end
                    end
                    info.checked = function()
                        return (panel[destVar] == value)
                    end
                    UIDropDownMenu_AddButton(info, level)
                end

                for i = 1, #items do
                    local it = items[i]
                    AddItem(it[1], it[2])
                end

                local sep = UIDropDownMenu_CreateInfo()
                sep.text = " "
                sep.isTitle = true
                sep.notCheckable = true
                UIDropDownMenu_AddButton(sep, level)
                AddItem("All", "all")
            end

            UIDropDownMenu_Initialize(panel[dropKey], Init)

            if not panel[dropKey]._msufCopySyncHooked and panel[dropKey].HookScript then
                panel[dropKey]._msufCopySyncHooked = true
                panel[dropKey]:HookScript("OnShow", function(self)
                    local k = panel[destVar] or default
                    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, k) end
                    local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(k)) or tostring(k)
                    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
                end)
            end
        end

        if not panel[btnKey] then
            panel[btnKey] = CreateFrame("Button", nil, textGroup, "UIPanelButtonTemplate")
            panel[btnKey]:SetSize(64, 20)
            panel[btnKey]:SetText("Copy")
            panel[btnKey]:Hide()
        end

        if not panel[hintKey] then
            panel[hintKey] = textGroup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            panel[hintKey]:SetText(hintText)
            panel[hintKey]:Hide()
        end

        -- Single, stable anchor for all copy UIs (above the Edit Mode button, avoids indicator overlap)
        panel[dropKey]:ClearAllPoints()
        panel[dropKey]:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 52, 96)

        panel[labelKey]:ClearAllPoints()
        panel[labelKey]:SetPoint("LEFT", panel[dropKey], "LEFT", -40, 2)

        panel[btnKey]:ClearAllPoints()
        panel[btnKey]:SetPoint("LEFT", panel[dropKey], "RIGHT", -14, 2)

        panel[hintKey]:ClearAllPoints()
        panel[hintKey]:SetPoint("TOPLEFT", panel[dropKey], "BOTTOMLEFT", -32, -2)
    end

    local _MSUF_COPY_UI_SPECS = {
        {
            prefix = "player",
            dropName = "MSUF_PlayerCopyToDropdown",
            destVar = "_msufCopyDestKey",
            defaultDest = "target",
            hintText = "Copies compatible settings (castbar -> Target/Focus only).",
            items = {
                { "Target", "target" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "target",
            dropName = "MSUF_TargetCopyToDropdown",
            destVar = "_msufCopyDestKey_target",
            defaultDest = "player",
            hintText = "Copies compatible settings (castbar -> Player/Focus only).",
            items = {
                { "Player", "player" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "focus",
            dropName = "MSUF_FocusCopyToDropdown",
            destVar = "_msufCopyDestKey_focus",
            defaultDest = "target",
            hintText = "Copies compatible settings (castbar -> Player/Target only).",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "boss",
            dropName = "MSUF_BossCopyToDropdown",
            destVar = "_msufCopyDestKey_boss",
            defaultDest = "target",
            hintText = "Copies compatible settings (boss castbar keys included).",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Focus", "focus" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "tot",
            dropName = "MSUF_ToTCopyToDropdown",
            destVar = "_msufCopyDestKey_tot",
            defaultDest = "player",
            hintText = "Copies compatible settings (castbar ignored).",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
            },
        },
        {
            prefix = "pet",
            dropName = "MSUF_PetCopyToDropdown",
            destVar = "_msufCopyDestKey_pet",
            defaultDest = "target",
            hintText = "Copies compatible settings (castbar ignored).",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Target of Target", "targettarget" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
            },
        },
    }

    for i = 1, #_MSUF_COPY_UI_SPECS do
        _MSUF_BuildCopyUI(_MSUF_COPY_UI_SPECS[i])
    end

    if false and not panel.petEditModeButton then
        panel.petEditModeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        panel.petEditModeButton:SetSize(220, 28)
        panel.petEditModeButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 20)
        panel.petEditModeButton:SetText("Edit Mode")
        panel.petEditModeButton:SetScript("OnClick", function()
            local fn = _G and _G.MSUF_SetMSUFEditModeDirect
            if type(fn) == "function" then
                local active = _G.MSUF_UnitEditModeActive and true or false
                local cur = _G.MSUF_CurrentEditUnitKey
                if active and cur == "pet" then
                    fn(false)
                else
                    fn(true, "pet")
                end
            end
        end)
        panel.petEditModeButton:Hide()
    end

    end


-- APPLY FROM DB (called from Options Core)


-- Reuse the Player indicator block layout as a template for other unitframe pages.
-- Leader/Assist is only shown on Player + Target; Raid Marker + Level are available for all.
function ns.MSUF_Options_Player_LayoutIndicatorTemplate(panel, currentKey)
    if not panel or not panel._msufIndicatorLayout then return end

    local l = panel._msufIndicatorLayout
    local container = panel._msufTextGroup or panel.playerTextLayoutGroup or panel
    if not container then return end

    local isFramesTab = true
    if type(panel._msufIsFramesTab) == "function" then
        isFramesTab = panel._msufIsFramesTab()
    end

    local function SetShownByName(name, show)
        if not name then return end
        local w = panel[name]
        if w then w:SetShown(show) end
    end

    -- If we're not on the Frames tab, hard-hide the whole indicator template to avoid stray UI.
    if not isFramesTab then
        if panel.playerLeaderIndicatorHeader then panel.playerLeaderIndicatorHeader:Hide() end
        for _, spec in pairs(_MSUF_INDICATOR_SPECS) do
            SetShownByName(spec.showCB, false)
            SetShownByName(spec.xStepper, false)
            SetShownByName(spec.yStepper, false)
            SetShownByName(spec.anchorDrop, false)
            SetShownByName(spec.anchorLabel, false)
            SetShownByName(spec.sizeEdit, false)
            SetShownByName(spec.sizeLabel, false)
            SetShownByName(spec.divider, false)
            SetShownByName(spec.resetBtn, false)
        end
        if panel.playerBossSpacingSlider then panel.playerBossSpacingSlider:Hide() end
        return
    end

    -- Header: keep it present for all frames pages.
    if panel.playerLeaderIndicatorHeader then
        panel.playerLeaderIndicatorHeader:Show()
        panel.playerLeaderIndicatorHeader:SetJustifyH("LEFT")
    end

    local baseToggleY = l.leaderToggleY or -163
    local baseCtrlY   = l.leaderCtrlY   or -178
    local step        = l.rowStep       or -64
    local dividerOffset = l.dividerOffset or 23

    -- Pet tab has no Castbar section in this panel; move Indicator up to occupy that space.
    -- This aligns the first indicator row roughly where other tabs place the Castbar controls.
    if currentKey == "pet" then
        baseToggleY = -34
        baseCtrlY   = -49
    end


    local function PlaceToggle(cb, y)
        if not cb then return end
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", container, "TOPLEFT", 12, y)
    end

    local function PlaceXStepper(stepper, y)
        if not stepper then return end
        stepper:ClearAllPoints()
        stepper:SetPoint("TOPLEFT", container, "TOPLEFT", l.colX or 175, y)
    end

    local function PlaceDivider(tex, toggleY)
        if not tex then return end
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", container, "TOPLEFT", 15, toggleY + dividerOffset)
        tex:SetPoint("TOPRIGHT", container, "TOPRIGHT", -15, toggleY + dividerOffset)
    end

    local row = 0
    local firstDivider = nil

    for _, id in ipairs({ "leader", "raidmarker", "level" }) do
        local spec = _MSUF_INDICATOR_SPECS[id]
        if spec then
            local show = (spec.allowed and spec.allowed(currentKey)) and true or false

            SetShownByName(spec.showCB, show)
            SetShownByName(spec.xStepper, show)
            SetShownByName(spec.yStepper, show)
            SetShownByName(spec.anchorDrop, show)
            SetShownByName(spec.anchorLabel, show)
            SetShownByName(spec.sizeEdit, show)
            SetShownByName(spec.sizeLabel, show)
            SetShownByName(spec.divider, show)
            SetShownByName(spec.resetBtn, show)

            if show then
                local toggleY = baseToggleY + (row * step)
                local ctrlY   = baseCtrlY + (row * step)

                PlaceToggle(panel[spec.showCB], toggleY)
                PlaceXStepper(panel[spec.xStepper], ctrlY)
                PlaceDivider(panel[spec.divider], toggleY)

                if not firstDivider and spec.divider and panel[spec.divider] then
                    firstDivider = panel[spec.divider]
                end

                row = row + 1
            end
        end
    end

    if panel.playerLeaderIndicatorHeader and firstDivider then
        panel.playerLeaderIndicatorHeader:ClearAllPoints()
        panel.playerLeaderIndicatorHeader:SetPoint("LEFT", firstDivider, "LEFT", 0, 0)
    end

    -- Boss-only: spacing control lives under the indicator template on boss pages.
    local isBossKey = false
    if type(currentKey) == "string" then
        if currentKey == "boss" or currentKey:match("^boss") then
            isBossKey = true
        end
    end

    if panel.playerBossSpacingSlider then
        local show = isBossKey and true or false
        panel.playerBossSpacingSlider:SetShown(show)
        if panel.playerBossSpacingSlider.editBox then panel.playerBossSpacingSlider.editBox:SetShown(show) end
        if panel.playerBossSpacingSlider.minusButton then panel.playerBossSpacingSlider.minusButton:SetShown(show) end
        if panel.playerBossSpacingSlider.plusButton then panel.playerBossSpacingSlider.plusButton:SetShown(show) end

        local n = panel.playerBossSpacingSlider.GetName and panel.playerBossSpacingSlider:GetName()
        if n then
            local low  = _G[n .. "Low"]
            local high = _G[n .. "High"]
            local text = _G[n .. "Text"]
            if low  then low:SetShown(show) end
            if high then high:SetShown(show) end
            if text then text:SetShown(show) end
        end

        if show then
            local ctrlY = baseCtrlY + (row * step)
            panel.playerBossSpacingSlider:ClearAllPoints()
            panel.playerBossSpacingSlider:SetPoint("TOPLEFT", container, "TOPLEFT", 12, ctrlY)
        end
    end
end

function ns.MSUF_Options_Player_ApplyFromDB(panel, currentKey, conf, g, GetOffsetValue)
    if not panel or not currentKey then return end

    -- Be robust when the core passes nil conf/g (e.g. first time opening a unit tab).
    EnsureDB()
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    g = MSUF_DB.general

    local key = currentKey
    if key == "tot" or key == "targetoftarget" then key = "targettarget" end
    MSUF_DB[key] = MSUF_DB[key] or conf or {}
    conf = MSUF_DB[key]
    currentKey = key
    panel._msufLastApplyKey = currentKey

    -- If the core is still in player-only mode, it will only show this UI for player.
    -- We still keep ApplyFromDB working for any key (multi-unit core).

    -- Basics

    -- Unit Alpha: make the left box title reflect the selected unit (Player/Target/Focus/etc.).
    if panel.playerSizeBox and panel.playerSizeBox._msufTitleText then
        local k = currentKey
        if k == "tot" or k == "targetoftarget" then k = "targettarget" end
        local titleMap = {
            player = "Player Alpha",
            target = "Target Alpha",
            focus = "Focus Alpha",
            pet = "Pet Alpha",
            boss = "Boss Alpha",
            targettarget = "Target of Target Alpha",
        }
        panel.playerSizeBox._msufTitleText:SetText(titleMap[k] or "Unit Alpha")
    end
    for _, s in ipairs(MSUF_BASIC_CB_SPECS) do
        local w = panel[s.w]
        if w and w.SetChecked then
            w:SetChecked((s.eval and s.eval(conf)) and true or false)
        end
    end

    -- Player-only: Player castbar toggles (Frames tab -> Text box)
    local isPlayerKey = (currentKey == "player")
    local isTargetKey = (currentKey == "target")
    local isFocusKey  = (currentKey == "focus")
    local isBossKey   = (currentKey == "boss")
    local isToTKey    = (currentKey == "targettarget" or currentKey == "tot" or currentKey == "targetoftarget")
    local isPetKey    = (currentKey == "pet")
    local isFramesTab = (panel._msufIsFramesTab and panel._msufIsFramesTab()) or true

    -- ToT-only: inline ToT text in Target name line toggle lives in the right "Castbar" box.
    if panel.totShowInTargetCB then
        panel.totShowInTargetCB:SetShown(isToTKey and isFramesTab)
        if isToTKey and isFramesTab then
            panel.totShowInTargetCB:SetChecked(conf.showToTInTargetName == true)
        end
        -- Separator dropdown directly under the toggle.
        if panel.totInlineSeparatorDD then
            local show = (isToTKey and isFramesTab)
            panel.totInlineSeparatorDD:SetShown(show)
            if show then
                -- Keep anchoring stable even if other reflow/layout code touches the parent group.
                if panel.totShowInTargetCB then
                    panel.totInlineSeparatorDD:ClearAllPoints()
                    panel.totInlineSeparatorDD:SetPoint("TOPLEFT", panel.totShowInTargetCB, "BOTTOMLEFT", -18, -6)
                    if panel.totInlineSeparatorDD.SetFrameLevel and panel.totShowInTargetCB.GetFrameLevel then
                        panel.totInlineSeparatorDD:SetFrameLevel((panel.totShowInTargetCB:GetFrameLevel() or 0) + 2)
                    end
                end

                local token = MSUF_ReadString(conf, g, "totInlineSeparator", "|")
                token = MSUF_ToTInlineSepTokenText(token)
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel.totInlineSeparatorDD, token) end
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(panel.totInlineSeparatorDD, token) end

                -- Grey/disable when inline is off (safe UX, avoids accidental confusion).
                local enabled = (conf.showToTInTargetName == true)
                if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
                    if enabled then UIDropDownMenu_EnableDropDown(panel.totInlineSeparatorDD) else UIDropDownMenu_DisableDropDown(panel.totInlineSeparatorDD) end
                elseif panel.totInlineSeparatorDD.Button then
                    if enabled and panel.totInlineSeparatorDD.Button.Enable then panel.totInlineSeparatorDD.Button:Enable() end
                    if (not enabled) and panel.totInlineSeparatorDD.Button.Disable then panel.totInlineSeparatorDD.Button:Disable() end
                end
            end
        end

    -- Title: Target of Target uses "Inline Text" (it is not a castbar).
    -- Pet uses this box for indicator settings, so we hide the "Castbar" title there.
    if panel.playerTextLayoutGroup and panel.playerTextLayoutGroup._msufTitleText then
        local t = panel.playerTextLayoutGroup._msufTitleText
        if isFramesTab and isPetKey then
            t:SetText("")
            t:Hide()
        elseif isToTKey and isFramesTab then
            t:SetText("Inline Text")
            t:Show()
        else
            t:SetText("Castbar")
            t:Show()
        end
    end

    end


    -- Copy-to UI visibility (refactored)
    local function _MSUF_SetCopyVisible(prefix, destVar, defaultDest, active)
        local labelKey = prefix .. "CopyToLabel"
        local dropKey  = prefix .. "CopyToDrop"
        local btnKey   = prefix .. "CopyToButton"
        local hintKey  = prefix .. "CopyToHint"

        if panel[labelKey] then panel[labelKey]:SetShown(active) end
        if panel[btnKey] then panel[btnKey]:SetShown(active) end
        if panel[hintKey] then panel[hintKey]:SetShown(active) end

        local drop = panel[dropKey]
        if drop then
            drop:SetShown(active)
            if active then
                local k = panel[destVar] or defaultDest
                panel[destVar] = k
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, k) end
                local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(k)) or tostring(k)
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, label) end
            end
        end
    end

    _MSUF_SetCopyVisible("player", "_msufCopyDestKey",        "target", isPlayerKey and isFramesTab)
    _MSUF_SetCopyVisible("target", "_msufCopyDestKey_target", "player", isTargetKey and isFramesTab)
    _MSUF_SetCopyVisible("focus",  "_msufCopyDestKey_focus",  "target", isFocusKey  and isFramesTab)
    _MSUF_SetCopyVisible("boss",   "_msufCopyDestKey_boss",   "target", isBossKey   and isFramesTab)
    _MSUF_SetCopyVisible("pet",    "_msufCopyDestKey_pet",    "target", isPetKey    and isFramesTab)
    _MSUF_SetCopyVisible("tot",    "_msufCopyDestKey_tot",    "player", isToTKey    and isFramesTab)

-- Castbar toggles (Enable / Time / Interrupt) per unit (Frames tab) [spec-driven]
    for _, spec in ipairs(MSUF_CASTBAR_FRAME_TOGGLE_SPECS) do
        local show = (isFramesTab and currentKey == spec.key)
        MSUF_ApplyCheck(panel, spec.enableW, show, (g[spec.enableK] ~= false))
        MSUF_ApplyCheck(panel, spec.timeW, show, (g[spec.timeK] ~= false))
        MSUF_ApplyCheck(panel, spec.interruptW, show, (conf.showInterrupt ~= false))
    end

-- Indicators (spec-driven)
    for _, id in ipairs(MSUF_INDICATOR_ORDER) do
        local spec = _MSUF_INDICATOR_SPECS[id]
        if spec then
            -- Checkbox
            if spec.showCB and spec.showField and panel[spec.showCB] and panel[spec.showCB].SetChecked then
                panel[spec.showCB]:SetChecked(MSUF_ReadBool(conf, g, spec.showField, spec.showDefault) and true or false)
            end

            -- X/Y offsets
            if spec.xStepper and spec.xField and panel[spec.xStepper] and panel[spec.xStepper].SetValue then
                panel[spec.xStepper]:SetValue(MSUF_ReadNumber(conf, g, spec.xField, spec.xDefault), false)
            end
            if spec.yStepper and spec.yField and panel[spec.yStepper] and panel[spec.yStepper].SetValue then
                panel[spec.yStepper]:SetValue(MSUF_ReadNumber(conf, g, spec.yField, spec.yDefault), false)
            end

            -- Anchor dropdown
            if spec.anchorDrop and spec.anchorField and panel[spec.anchorDrop] then
                local v = MSUF_ReadString(conf, g, spec.anchorField, spec.anchorDefault)
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel[spec.anchorDrop], v) end
                if UIDropDownMenu_SetText and spec.anchorText then UIDropDownMenu_SetText(panel[spec.anchorDrop], spec.anchorText(v)) end
            end

            -- Optional size editbox
            if spec.sizeEdit and spec.sizeField and panel[spec.sizeEdit] then
                MSUF_SetNumericEditBoxValue(panel[spec.sizeEdit], MSUF_ReadNumber(conf, g, spec.sizeField, spec.sizeDefault))
            end
        end
    end

-- Reflow the indicator block rows depending on which unitframe tab we are on.
if ns and ns.MSUF_Options_Player_LayoutIndicatorTemplate then
    ns.MSUF_Options_Player_LayoutIndicatorTemplate(panel, currentKey)
end


    
-- Castbar icon/text toggles (per-unit overrides with global fallback) [spec-driven]
    for _, spec in ipairs(MSUF_CASTBAR_TEXTICON_SPECS) do
        local show = (isFramesTab and currentKey == spec.key)

        local iconChecked = MSUF_GetShowWithFallback(g[spec.iconK], g.castbarShowIcon)
        local textChecked
        if spec.textDirect then
            textChecked = (g[spec.textK] ~= false)
        else
            textChecked = MSUF_GetShowWithFallback(g[spec.textK], g.castbarShowSpellName)
        end

        MSUF_ApplyCheck(panel, spec.iconW, show, iconChecked)
        MSUF_ApplyCheck(panel, spec.textW, show, textChecked)
    end


-- Portrait dropdown (all unitframes) [spec-driven]
    if panel.playerPortraitDropDown and UIDropDownMenu_SetSelectedValue and UIDropDownMenu_SetText then
        panel.playerPortraitDropDown:Show()

        local mode = MSUF_GetPortraitDropdownValue(conf)
        UIDropDownMenu_SetSelectedValue(panel.playerPortraitDropDown, mode)
        UIDropDownMenu_SetText(panel.playerPortraitDropDown, MSUF_PortraitModeText(mode))
    end



    -- Unit Alpha (in/out of combat) [spec-driven]
    local aIn  = tonumber(conf.alphaInCombat) or 1
    local aOut = tonumber(conf.alphaOutOfCombat) or 1
    local sync = (conf.alphaSync == true)
    if sync then
        aOut = aIn
    end

    if panel.playerAlphaSyncCB then
        panel.playerAlphaSyncCB:SetChecked(sync and true or false)
    end

    local alphaValues = {
        playerAlphaInCombatSlider = aIn,
        playerAlphaOutCombatSlider = aOut,
    }

    for _, spec in ipairs(MSUF_ALPHA_SLIDER_SPECS) do
        local s = panel[spec.field]
        if s and s.SetValue then
            s.MSUF_SkipCallback = true
            s:SetValue(alphaValues[spec.field] or 1)
            s.MSUF_SkipCallback = false
        end
    end


    -- Boss-only extension: grow the right-side box for boss-only controls (Boss spacing lives under Indicator now).
    local isBoss = (currentKey == "boss")
    if panel.playerSizeBox and panel._msufSizeBaseH then
        panel.playerSizeBox:SetHeight(panel._msufSizeBaseH)
    end
    if panel.playerTextLayoutGroup and panel._msufBasicsH and panel._msufSizeBaseH and panel._msufSizeBossH then
        local h = panel._msufBasicsH + panel._msufSizeBaseH + 12
        panel.playerTextLayoutGroup:SetHeight(h)
    end


    -- Frame size

    -- Boss Spacing (boss only) [spec-driven]
    if panel.playerBossSpacingSlider then
        local show = (currentKey == "boss")
        if panel.playerBossSpacingSlider.SetShown then
            panel.playerBossSpacingSlider:SetShown(show)
        else
            if show then panel.playerBossSpacingSlider:Show() else panel.playerBossSpacingSlider:Hide() end
        end
        if show then
            panel.playerBossSpacingSlider.MSUF_SkipCallback = true
            panel.playerBossSpacingSlider:SetValue(conf.spacing or -36)
            panel.playerBossSpacingSlider.MSUF_SkipCallback = false
            ForceSliderEditBox(panel.playerBossSpacingSlider)
        end
    end

    -- Copy settings button (Player menu)
    MSUF_BindAllCopyButtons(panel)

    -- Copy settings button (Target menu)
    -- (bound by MSUF_BindAllCopyButtons)

    -- Copy settings button (Focus menu)
    -- (bound by MSUF_BindAllCopyButtons)

    -- Copy settings button (Target of Target menu)
    -- (bound by MSUF_BindAllCopyButtons)


    -- Text positioning controls removed (Text group is a placeholder only).


    -- Keep mini headers aligned with the "Indicator" title line after layout has settled.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            MSUF_PositionLeaderMiniHeaders(panel)
        end)
    else
        MSUF_PositionLeaderMiniHeaders(panel)
    end

end

-- INSTALL HANDLERS (called from Options Core)
function ns.MSUF_Options_Player_InstallHandlers(panel, api)
    if not panel or not api then return end

    local function IsFramesTab()
        return (api.getTabKey and api.getTabKey() == "frames")
    end

    local function CurrentKey()
        return (api.getKey and api.getKey()) or "player"
    end

    -- Make current unit key available to CreatePanel callbacks (dropdowns / edits).
    panel._msufGetCurrentKey = CurrentKey

    panel._msufIsFramesTab = IsFramesTab

    -- Expose API for lightweight UI callbacks (e.g. Copy dropdown)
    panel._msufAPI = api

    local function ApplyCurrent()
        if api.ApplySettingsForKey then
            api.ApplySettingsForKey(CurrentKey())
        end
end

local function ApplyLayoutCurrent(reason)
    local key = CurrentKey()
    local fn = _G and _G.MSUF_UFCore_RequestLayoutForUnit
    if type(fn) == "function" then
        local urgent = (key == "target" or key == "targettarget" or key == "focus")
        pcall(fn, key, reason or "OPTIONS_LAYOUT", urgent)
        return
    end
    ApplyCurrent()
end

    local function EnsureKeyDB()
        if api.EnsureDB then api.EnsureDB() end
        local key = (CurrentKey and CurrentKey()) or "player"
        if key == "tot" then key = "targettarget" end -- back-compat / alias safety
        if panel then panel._msufLastApplyKey = key end
        MSUF_DB[key] = MSUF_DB[key] or {}
        return MSUF_DB[key]
    end

    -- Indicator reset binding (shared helper for Leader / Raid Marker / Level)
    local function MSUF_ApplyStepper(stepper, v)
        if not stepper then return end
        stepper:SetValue(v, false)
        if stepper.editBox and (not stepper.editBox:HasFocus()) then
            stepper.editBox:SetText(tostring(v))
        end
    end

    local function MSUF_ApplyDropdown(drop, value, textFunc)
        if not drop then return end
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, value) end
        if UIDropDownMenu_SetText and textFunc then UIDropDownMenu_SetText(drop, textFunc(value)) end
    end
    -- Indicator row specs (shared)
    local INDICATOR_SPECS = _MSUF_INDICATOR_SPECS

local function MSUF_CanonIndicatorKey()
    local key = (CurrentKey and CurrentKey()) or "player"
    if key == "tot" then key = "targettarget" end
    if type(key) == "string" and key:match("^boss") then key = "boss" end
    return key
end

local function MSUF_GetIndicatorConfAndGeneral()
    EnsureDB()
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local key = MSUF_CanonIndicatorKey()
    MSUF_DB[key] = MSUF_DB[key] or {}
    local conf = MSUF_DB[key]
    return conf, g, key
end

-- Use shared MSUF_ReadBool / MSUF_ReadNumber / MSUF_ReadString helpers (file-scope)

local function MSUF_CallIndicatorRefresh(spec)
    if not spec then return end

    -- Some indicator systems still have dedicated refresh helpers (e.g. leader/assist icon rebuild).
    local fnName = spec.refreshFnName
    if fnName then
        local fn = _G and _G[fnName]
        if type(fn) == "function" then
            pcall(fn)
        end
    end

    -- Always request a layout pass so size/anchor changes apply without forcing full updates.
    ApplyLayoutCurrent("INDICATOR")
end

local function MSUF_ApplyIndicatorUI(spec)
    if not spec then return end
    if not IsFramesTab() then return end

    local conf, g, key = MSUF_GetIndicatorConfAndGeneral()
    if spec.allowed and (not spec.allowed(key)) then return end

    if spec.showCB and panel[spec.showCB] and spec.showField then
        panel[spec.showCB]:SetChecked(MSUF_ReadBool(conf, g, spec.showField, spec.showDefault))
    end
    if spec.xStepper and panel[spec.xStepper] and spec.xField then
        MSUF_ApplyStepper(panel[spec.xStepper], MSUF_ReadNumber(conf, g, spec.xField, spec.xDefault))
    end
    if spec.yStepper and panel[spec.yStepper] and spec.yField then
        MSUF_ApplyStepper(panel[spec.yStepper], MSUF_ReadNumber(conf, g, spec.yField, spec.yDefault))
    end
    if spec.anchorDrop and panel[spec.anchorDrop] and spec.anchorField then
        local a = MSUF_ReadString(conf, g, spec.anchorField, spec.anchorDefault)
        MSUF_ApplyDropdown(panel[spec.anchorDrop], a, spec.anchorText)
    end
    if spec.sizeEdit and panel[spec.sizeEdit] and spec.sizeField then
        local v = conf and conf[spec.sizeField]
        if type(v) ~= "number" and g then v = g[spec.sizeField] end
        v = tonumber(v) or spec.sizeDefault or 14
        v = math.floor(v + 0.5)
        if v < 8 then v = 8 end
        if v > 64 then v = 64 end
        MSUF_SetNumericEditBoxValue(panel[spec.sizeEdit], v)
    end
end

local function MSUF_ResetIndicatorRow(rowId)
    if not IsFramesTab() then return end
    if not rowId then return end

    local spec = INDICATOR_SPECS[rowId]
    if not spec then return end

    local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
    if spec.allowed and (not spec.allowed(key)) then return end

    if spec.xField then conf[spec.xField] = nil end
    if spec.yField then conf[spec.yField] = nil end
    if spec.anchorField then conf[spec.anchorField] = nil end
    if spec.sizeField then conf[spec.sizeField] = nil end

    MSUF_ApplyIndicatorUI(spec)

    ApplyLayoutCurrent("INDICATOR_RESET")
    MSUF_CallIndicatorRefresh(spec)
end

    local function MSUF_BindIndicatorResetButton(btn, rowId)
        if not btn then return end
        btn:SetScript("OnClick", function()
            MSUF_ResetIndicatorRow(rowId)
        end)
    end

    for _, rowId in ipairs(MSUF_INDICATOR_ORDER) do
        local spec = INDICATOR_SPECS[rowId]
        if spec and spec.resetBtn then
            MSUF_BindIndicatorResetButton(panel[spec.resetBtn], rowId)
        end
    end

-- Bind all indicator-row controls from a single spec table
local function MSUF_BindIndicatorRow(spec)
    if not spec then return end

    local function AllowedNow()
        local _, _, key = MSUF_GetIndicatorConfAndGeneral()
        if spec.allowed and (not spec.allowed(key)) then return false end
        return true
    end

    local function Refresh()
        MSUF_CallIndicatorRefresh(spec)
    end

    -- Checkbox
    if spec.showCB and panel[spec.showCB] and spec.showField then
        local cb = panel[spec.showCB]
        cb:SetScript("OnClick", function(self)
            if not IsFramesTab() then return end
            if not AllowedNow() then return end

            local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
            conf[spec.showField] = self:GetChecked() and true or false

            Refresh()
            -- Best-effort: immediately refresh current unitframe if present (coalesced)
            local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
            local fr = (uf and key) and uf[key] or nil
            if fr and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                _G.MSUF_RequestUnitframeUpdate(fr, true, true, "IndicatorToggle")
            elseif fr and type(_G.UpdateSimpleUnitFrame) == "function" then
                _G.UpdateSimpleUnitFrame(fr)
            end
        end)
        cb:HookScript("OnShow", function() MSUF_ApplyIndicatorUI(spec) end)
    end

    -- Steppers (offsets)
    local function BindStepper(stepperName, fieldName, defaultVal)
        if not stepperName or not fieldName then return end
        local st = panel[stepperName]
        if not st then return end

        st.onValueChanged = function(_, v)
            if not IsFramesTab() then return end
            if not AllowedNow() then return end
            local conf = MSUF_GetIndicatorConfAndGeneral()
            conf[fieldName] = tonumber(v) or (defaultVal or 0)
            Refresh()
        end

        st:SetScript("OnShow", function() MSUF_ApplyIndicatorUI(spec) end)
    end

    BindStepper(spec.xStepper, spec.xField, spec.xDefault)
    BindStepper(spec.yStepper, spec.yField, spec.yDefault)

    
    -- Dropdown (anchor)
    if spec.anchorDrop and panel[spec.anchorDrop] and spec.anchorField and UIDropDownMenu_Initialize then
        local drop = panel[spec.anchorDrop]

        UIDropDownMenu_Initialize(drop, function(self, level)
            if not level or level ~= 1 then return end
            if not AllowedNow() then return end

            local function GetCurrent()
                local conf, g = MSUF_GetIndicatorConfAndGeneral()
                return MSUF_ReadString(conf, g, spec.anchorField, spec.anchorDefault)
            end

            local function IsChecked(v)
                return (GetCurrent() == v)
            end

            local function OnSelect(btn, value, textLabel)
                if not IsFramesTab() then return end

                local conf2, _, key2 = MSUF_GetIndicatorConfAndGeneral()
                if spec.allowed and (not spec.allowed(key2)) then return end

                local v = (btn and btn.value) or value or spec.anchorDefault
                conf2[spec.anchorField] = v

                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, v) end
                if UIDropDownMenu_SetText then
                    -- Prefer spec.anchorText() for consistent labels, but fall back to the item label.
                    local label = (spec.anchorText and spec.anchorText(v)) or textLabel or tostring(v)
                    UIDropDownMenu_SetText(drop, label)
                end

                if CloseDropDownMenus then CloseDropDownMenus() end

                -- Live-apply
                Refresh()
            end

            for _, pair in ipairs(spec.anchorChoices or {}) do
                local textLabel, value = pair[1], pair[2]
                local info = UIDropDownMenu_CreateInfo()
                info.text  = textLabel
                info.value = value
                info.func  = function(btn) OnSelect(btn, value, textLabel) end
                info.checked = function() return IsChecked(value) end
                info.isNotRadio = false
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        drop:SetScript("OnShow", function() MSUF_ApplyIndicatorUI(spec) end)
    end


    -- Numeric edit box (size)
    if spec.sizeEdit and panel[spec.sizeEdit] and spec.sizeField then
        local edit = panel[spec.sizeEdit]

        local function ApplySize()
            if not IsFramesTab() then return end
            if not AllowedNow() then return end

            local conf, g = MSUF_GetIndicatorConfAndGeneral()

            local v = tonumber(edit:GetText())
            if not v then
                v = MSUF_ReadNumber(conf, g, spec.sizeField, spec.sizeDefault or 14)
            end

            v = math.floor((tonumber(v) or (spec.sizeDefault or 14)) + 0.5)
            if v < 8 then v = 8 end
            if v > 64 then v = 64 end

            conf[spec.sizeField] = v
            MSUF_SetNumericEditBoxValue(edit, v)

            Refresh()
        end

        edit:SetScript("OnEnterPressed", function(self) ApplySize(); self:ClearFocus() end)
        edit:SetScript("OnEditFocusLost", function(self) ApplySize() end)
        edit:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            self._msufIndSizeSeq = (self._msufIndSizeSeq or 0) + 1
            local seq = self._msufIndSizeSeq
            if C_Timer and C_Timer.After then
                C_Timer.After(0.25, function()
                    if self._msufIndSizeSeq == seq and self:HasFocus() then
                        ApplySize()
                    end
                end)
            end
        end)
        edit:HookScript("OnShow", function() MSUF_ApplyIndicatorUI(spec) end)
    end
end

for _, rowId in ipairs(MSUF_INDICATOR_ORDER) do
    MSUF_BindIndicatorRow(INDICATOR_SPECS[rowId])
end

-- ToT inline-in-Target toggle (stored under MSUF_DB.targettarget)
if panel.totShowInTargetCB then
    panel.totShowInTargetCB:SetScript("OnClick", function(self)
        EnsureDB()
        EnsureKeyDB()
        MSUF_DB.targettarget = MSUF_DB.targettarget or {}
        MSUF_DB.targettarget.showToTInTargetName = self:GetChecked() and true or false
        ApplyLayoutCurrent("TOTINLINE_TOGGLE")
        if type(_G.MSUF_UpdateTargetToTInlineNow) == "function" then
            _G.MSUF_UpdateTargetToTInlineNow()
        end

        -- Keep separator dropdown greyed/active in sync with the toggle.
        if panel.totInlineSeparatorDD then
            local enabled = (MSUF_DB and MSUF_DB.targettarget and MSUF_DB.targettarget.showToTInTargetName == true)
            if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
                if enabled then UIDropDownMenu_EnableDropDown(panel.totInlineSeparatorDD) else UIDropDownMenu_DisableDropDown(panel.totInlineSeparatorDD) end
            elseif panel.totInlineSeparatorDD.Button then
                if enabled and panel.totInlineSeparatorDD.Button.Enable then panel.totInlineSeparatorDD.Button:Enable() end
                if (not enabled) and panel.totInlineSeparatorDD.Button.Disable then panel.totInlineSeparatorDD.Button:Disable() end
            end
        end
    end)
end

-- ToT-inline separator dropdown (target-only).
if panel.totInlineSeparatorDD and UIDropDownMenu_Initialize then
    local drop = panel.totInlineSeparatorDD

    local function EnsureToTConf()
        EnsureDB()
        if not MSUF_DB then return nil end
        if type(MSUF_DB.targettarget) ~= "table" then MSUF_DB.targettarget = {} end
        -- Migration fallback: some older builds may have stored the value under target.
        if MSUF_DB.targettarget.totInlineSeparator == nil and type(MSUF_DB.target) == "table" and type(MSUF_DB.target.totInlineSeparator) == "string" then
            MSUF_DB.targettarget.totInlineSeparator = MSUF_DB.target.totInlineSeparator
        end
        MSUF_DB.targettarget.totInlineSeparator = MSUF_ToTInlineSepTokenText(MSUF_DB.targettarget.totInlineSeparator)
        return MSUF_DB.targettarget
    end

    local function OnSelect(btn, arg1)
        local conf = EnsureToTConf()
        if not conf then return end
        local value = (btn and btn.value) or arg1 or "|"
        value = MSUF_ToTInlineSepTokenText(value)
        conf.totInlineSeparator = value

        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, value) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, value) end
        if CloseDropDownMenus then CloseDropDownMenus() end

        -- Targeted live refresh (coalesced entry point if available).
        if type(_G.MSUF_ToTInline_RequestRefresh) == "function" then
            _G.MSUF_ToTInline_RequestRefresh("TOTINLINE_SEP")
        elseif type(_G.MSUF_UpdateTargetToTInlineNow) == "function" then
            _G.MSUF_UpdateTargetToTInlineNow()
        end
    end

    UIDropDownMenu_Initialize(drop, function(self, level)
        if not level or level ~= 1 then return end
        local conf = EnsureToTConf()
        local cur = conf and conf.totInlineSeparator

        for _, opt in ipairs(MSUF_TOTINLINE_SEP_OPTIONS) do
            local v = opt.value
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = v
            info.arg1 = v
            info.func = OnSelect
            info.checked = function() return (cur == v) end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end


    -- Checkboxes
    local function HookCheck(cb, field)
        if not cb then return end
        cb:SetScript("OnClick", function(self)
            if not IsFramesTab() then return end
            local conf = EnsureKeyDB()
            conf[field] = self:GetChecked() and true or false
            ApplyCurrent()
            if type(_G.MSUF_SyncUnitPositionPopup) == "function" then
                _G.MSUF_SyncUnitPositionPopup(CurrentKey(), conf)
            end
        end)
    end

    local _basicChecks = {
        {"playerEnableFrameCB", "enabled"},
        {"playerShowNameCB",    "showName"},
        {"playerShowHPCB",      "showHP"},
        {"playerShowPowerCB",   "showPower"},
    }
    for i = 1, #_basicChecks do
        local wKey, field = _basicChecks[i][1], _basicChecks[i][2]
        HookCheck(panel[wKey], field)
    end


    
-- Castbar toggles (Enable / Time / Interrupt / Icon / Text)
local function _MSUF_SetCastTimeTextVisible(bar, show)
    if not bar or not bar.timeText then return end
    if show then
        bar.timeText:Show()
        bar.timeText:SetAlpha(1)
    else
        bar.timeText:SetText("")
        bar.timeText:Show()
        bar.timeText:SetAlpha(0)
    end
end

local function _MSUF_ClearInterruptFeedback(bar)
    if not bar or not bar.interruptFeedbackEndTime then return end
    bar.interruptFeedbackEndTime = nil
    if bar.castText then bar.castText:SetText("") end
    if bar.timeText then bar.timeText:SetText("") end
    bar:Hide()
end

local function _MSUF_ClearInterruptFeedback_Boss()
    local frames = _G.MSUF_BossCastbars
    if not frames then return end
    for i = 1, #frames do
        local b = frames[i]
        if b and b.interruptFeedbackEndTime then
            b.interruptFeedbackEndTime = nil
            if b.castText then b.castText:SetText("") end
            if b.timeText then b.timeText:SetText("") end
            b:Hide()
        end
    end
end

local function _MSUF_ForceRefreshCastbarIfCasting(bar, unitToken)
    if not bar or not bar.Cast then return end
    local casting = (UnitCastingInfo and UnitCastingInfo(unitToken)) or (UnitChannelInfo and UnitChannelInfo(unitToken))
    if casting then
        pcall(bar.Cast, bar)
    end
end

local CASTBAR_HANDLER_SPECS = {
    player = {
        requireKey = nil, -- keep legacy behavior (no CurrentKey check)
        enableW = "playerCastbarEnableCB", enableK = "enablePlayerCastbar",
        timeW   = "playerCastbarTimeCB",   timeK   = "showPlayerCastTime",
        interruptW = "playerCastbarInterruptCB",
        iconW = "playerCastbarShowIconCB", iconK = "castbarPlayerShowIcon",
        textW = "playerCastbarShowTextCB", textK = "castbarPlayerShowSpellName",
        bar = function() return _G.MSUF_PlayerCastbar end,
        reanchor = function() if _G.MSUF_ReanchorPlayerCastBar then _G.MSUF_ReanchorPlayerCastBar() end end,
        preview  = function() if _G.MSUF_PositionPlayerCastbarPreview then _G.MSUF_PositionPlayerCastbarPreview() end end,
    },
    target = {
        requireKey = "target",
        enableW = "targetCastbarEnableCB", enableK = "enableTargetCastbar",
        timeW   = "targetCastbarTimeCB",   timeK   = "showTargetCastTime",
        interruptW = "targetCastbarInterruptCB",
        iconW = "targetCastbarShowIconCB", iconK = "castbarTargetShowIcon",
        textW = "targetCastbarShowTextCB", textK = "castbarTargetShowSpellName",
        bar = function() return _G.MSUF_TargetCastbar end,
        reanchor = function() if _G.MSUF_ReanchorTargetCastBar then _G.MSUF_ReanchorTargetCastBar() end end,
        preview  = function() if _G.MSUF_PositionTargetCastbarPreview then _G.MSUF_PositionTargetCastbarPreview() end end,
        forceRefreshUnit = "target",
    },
    focus = {
        requireKey = "focus",
        enableW = "focusCastbarEnableCB", enableK = "enableFocusCastbar",
        timeW   = "focusCastbarTimeCB",   timeK   = "showFocusCastTime",
        interruptW = "focusCastbarInterruptCB",
        iconW = "focusCastbarShowIconCB", iconK = "castbarFocusShowIcon",
        textW = "focusCastbarShowTextCB", textK = "castbarFocusShowSpellName",
        bar = function() return _G.MSUF_FocusCastbar end,
        reanchor = function() if _G.MSUF_ReanchorFocusCastBar then _G.MSUF_ReanchorFocusCastBar() end end,
        preview  = function() if _G.MSUF_PositionFocusCastbarPreview then _G.MSUF_PositionFocusCastbarPreview() end end,
        forceRefreshUnit = "focus",
    },
    boss = {
        requireKey = "boss",
        enableW = "bossCastbarEnableCB", enableK = "enableBossCastbar",
        timeW   = "bossCastbarTimeCB",   timeK   = "showBossCastTime",
        interruptW = "bossCastbarInterruptCB",
        iconW = "bossCastbarShowIconCB", iconK = "showBossCastIcon",
        textW = "bossCastbarShowTextCB", textK = "showBossCastName",
        bar = function() return nil end,
        reanchor = function() end,
        preview  = function() end,
    },
}


local function _MSUF_BindCastbarGeneralToggle(spec, widgetKey, dbKey, onBoss, onNormal)
    local w = panel[widgetKey]
    if not w then return end
    w:SetScript("OnClick", function(self)
        if not IsFramesTab() then return end
        if spec.requireKey and CurrentKey() ~= spec.requireKey then return end
        MSUF_EnsureDB_IfPossible(api)
        MSUF_DB = MSUF_DB or {}
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general
        g[dbKey] = self:GetChecked() and true or false
        if spec.requireKey == "boss" then
            if onBoss then onBoss(spec, g) end
        else
            if onNormal then onNormal(spec, g) end
        end
    end)
end

local function _MSUF_BossRefreshCastbarLayout()
    if type(_G.MSUF_RefreshBossCastbarLayout) == "function" then _G.MSUF_RefreshBossCastbarLayout() end
end

local function _MSUF_BossApplyTimeAndLayout()
    if type(_G.MSUF_ApplyBossCastbarTimeSetting) == "function" then _G.MSUF_ApplyBossCastbarTimeSetting() end
    _MSUF_BossRefreshCastbarLayout()
end

local function _MSUF_NonBossVisualRefresh(spec)
    if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
    spec.reanchor()
    spec.preview()
end

local function _MSUF_NonBossTimeRefresh(spec, g)
    _MSUF_SetCastTimeTextVisible(spec.bar(), g[spec.timeK] ~= false)
    spec.reanchor()
    spec.preview()
end


local function _MSUF_BindCastbarEnable(spec)
    local w = panel[spec.enableW]
    if not w then return end
    w:SetScript("OnClick", function(self)
        MSUF_EnsureCastbars()
        if not IsFramesTab() then return end
        if spec.requireKey and CurrentKey() ~= spec.requireKey then return end
        if api.EnsureDB then api.EnsureDB() end
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general[spec.enableK] = self:GetChecked() and true or false

        -- Boss castbars have a dedicated enable pipeline.
        if spec.requireKey == "boss" then
            if type(_G.MSUF_SetBossCastbarsEnabled) == "function" then
                _G.MSUF_SetBossCastbarsEnabled(MSUF_DB.general.enableBossCastbar ~= false)
            elseif type(_G.MSUF_ApplyBossCastbarsEnabled) == "function" then
                _G.MSUF_ApplyBossCastbarsEnabled()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_UpdateBossCastbarPreview() end
            if type(_G.MSUF_RefreshBossCastbarLayout) == "function" then _G.MSUF_RefreshBossCastbarLayout() end
            return
        end

        spec.reanchor()
        spec.preview()

        -- If enabled while unit is already casting/channeling, force-refresh the bar immediately.
        if spec.forceRefreshUnit and MSUF_DB.general[spec.enableK] ~= false then
            _MSUF_ForceRefreshCastbarIfCasting(spec.bar(), spec.forceRefreshUnit)
        end
    end)
end

local function _MSUF_BindCastbarInterrupt(spec)
    local w = panel[spec.interruptW]
    if not w then return end
    w:SetScript("OnClick", function(self)
        if not IsFramesTab() then return end
        if spec.requireKey and CurrentKey() ~= spec.requireKey then return end
        local conf = EnsureKeyDB()
        conf.showInterrupt = self:GetChecked() and true or false

        -- If disabled while interrupt feedback is showing, hide immediately.
        if conf.showInterrupt == false then
            if spec.requireKey == "boss" then
                _MSUF_ClearInterruptFeedback_Boss()
            else
                _MSUF_ClearInterruptFeedback(spec.bar())
            end
        end
    end)
end

for _, spec in pairs(CASTBAR_HANDLER_SPECS) do
    _MSUF_BindCastbarEnable(spec)
    _MSUF_BindCastbarInterrupt(spec)

    _MSUF_BindCastbarGeneralToggle(spec, spec.iconW, spec.iconK, _MSUF_BossRefreshCastbarLayout, _MSUF_NonBossVisualRefresh)
    _MSUF_BindCastbarGeneralToggle(spec, spec.textW, spec.textK, _MSUF_BossRefreshCastbarLayout, _MSUF_NonBossVisualRefresh)
    _MSUF_BindCastbarGeneralToggle(spec, spec.timeW, spec.timeK, _MSUF_BossApplyTimeAndLayout, _MSUF_NonBossTimeRefresh)
end

-- Indicator live refresh (spec-driven)
-- Keep this lean: Options-time refresh only, and we rely on core layout helpers when present.
local MSUF_ALL_UF_TOKENS = { "player","target","focus","pet","tot","targettarget","boss1","boss2","boss3","boss4","boss5" }

local function MSUF_GetUnitFrameToken(unitToken)
    local uf = _G.MSUF_UnitFrames or _G.UnitFrames
    if uf and uf[unitToken] then return uf[unitToken] end
    -- Some builds only store ToT under one key; try common aliases
    if unitToken == "tot" and uf and uf.targettarget then return uf.targettarget end
    if unitToken == "targettarget" and uf and uf.tot then return uf.tot end
    return nil
end

local function MSUF_RefreshFrames(unitList, applyLayoutFnName)
    local update = _G.UpdateSimpleUnitFrame
    local applyLayout = applyLayoutFnName and _G[applyLayoutFnName] or nil

    for i = 1, #unitList do
        local f = MSUF_GetUnitFrameToken(unitList[i])
        if f then
            if update then pcall(update, f) end
            if applyLayout then pcall(applyLayout, f) end
        end
    end
end

-- Leader icon offsets + size/anchor live refresh (player + target)
MSUF_RefreshLeaderIconFrames = function()
    MSUF_RefreshFrames({ "player", "target" }, "MSUF_ApplyLeaderIconLayout")
end

-- Raid marker offset/anchor/size (per-unit): live update
MSUF_RefreshRaidMarkerFrames = function()
    MSUF_RefreshFrames(MSUF_ALL_UF_TOKENS, "MSUF_ApplyRaidMarkerLayout")
end

-- Level indicator offset/anchor (per-unit): live update
MSUF_RefreshLevelIndicatorFrames = function()
    MSUF_RefreshFrames(MSUF_ALL_UF_TOKENS, "MSUF_ApplyLevelIndicatorLayout")
end





    -- Portrait dropdown (all unitframes) [spec-driven]
    MSUF_BindPortraitDropdown(panel, "playerPortraitDropDown", IsFramesTab, EnsureKeyDB, ApplyCurrent)



-- Unit Alpha + Boss spacing sliders [spec-driven]
local function ApplyAlphaOnly()
    local fn = (_G and _G.MSUF_RefreshAllUnitAlphas) or MSUF_RefreshAllUnitAlphas
    if type(fn) == "function" then pcall(fn) end
end

-- Alpha sync checkbox
if panel.playerAlphaSyncCB then
    panel.playerAlphaSyncCB:SetScript("OnClick", function(self)
        if not IsFramesTab() then return end
        local conf = EnsureKeyDB()
        conf.alphaSync = self:GetChecked() and true or false
        if conf.alphaSync then
            local aIn = panel.playerAlphaInCombatSlider
            local v = tonumber(conf.alphaInCombat) or (aIn and aIn.GetValue and aIn:GetValue()) or 1
            v = tonumber(v) or 1
            conf.alphaInCombat, conf.alphaOutOfCombat = v, v
            local aOut = panel.playerAlphaOutCombatSlider
            if aIn then aIn.MSUF_SkipCallback = true; aIn:SetValue(v); aIn.MSUF_SkipCallback = false end
            if aOut then aOut.MSUF_SkipCallback = true; aOut:SetValue(v); aOut.MSUF_SkipCallback = false end
        end
        ApplyAlphaOnly()
        if not (InCombatLockdown and InCombatLockdown()) then ApplyCurrent() end
    end)
end

local function BindAlphaSlider(spec)
    local s = panel[spec.field]
    if not s then return end
    s.onValueChanged = function(self, value)
        if self.MSUF_SkipCallback or not IsFramesTab() then return end
        local conf = EnsureKeyDB()
        local v = tonumber(value) or 1
        conf[spec.key] = v
        if conf.alphaSync == true then
            conf[spec.otherKey] = v
            local o = panel[spec.otherField]
            if o then o.MSUF_SkipCallback = true; o:SetValue(v); o.MSUF_SkipCallback = false end
        end
        ApplyAlphaOnly()
        if not (InCombatLockdown and InCombatLockdown()) then ApplyCurrent() end
    end
    if s.HookScript then s:HookScript("OnShow", function() ForceSliderEditBox(s) end) end
end

for _, spec in ipairs(MSUF_ALPHA_SLIDER_SPECS) do
    BindAlphaSlider(spec)
end

-- Boss spacing slider (boss key only)
local bs = panel.playerBossSpacingSlider
if bs then
    bs.onValueChanged = function(self, value)
        if not IsFramesTab() or CurrentKey() ~= "boss" then return end
        local conf = EnsureKeyDB()
        conf.spacing = math.floor((tonumber(value) or 0) + 0.5)
        ApplyCurrent()
    end
    if bs.HookScript then bs:HookScript("OnShow", function() ForceSliderEditBox(bs) end) end
end

-- Copy settings button (Player menu)
    MSUF_BindAllCopyButtons(panel)


    -- Text positioning controls removed (Text group is a placeholder only).

end
