-- ---------------------------------------------------------------------------
-- MSUF_Options_Bars.lua
-- Split from MSUF_Options_Core.lua — Bars tab BUILD code.
-- Zero feature regression: same widgets, same DB keys, same behaviors.
-- ---------------------------------------------------------------------------
local addonName, addonNS = ...
ns = (_G and _G.MSUF_NS) or addonNS or ns or {}
if _G then _G.MSUF_NS = ns end

-- ---------------------------------------------------------------------------
-- Localization helper (keys are English UI strings; fallback = key)
-- ---------------------------------------------------------------------------
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end
local isEn = (ns and ns.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end

function ns.MSUF_Options_Bars_Build(panel, barGroup, barGroupHost, ctx)
    if not panel or not barGroup then return end
    -- -----------------------------------------------------------------
    -- Compat helpers (resolve from ctx / ns / _G; never assume globals)
    -- -----------------------------------------------------------------
    local CreateLabeledCheckButton    = ctx and ctx.CreateLabeledCheckButton
    local CreateLabeledSlider         = (ctx and ctx.CreateLabeledSlider) or (ns and (ns.MSUF_CreateLabeledSlider or ns.CreateLabeledSlider)) or _G.CreateLabeledSlider
    local MSUF_SetLabeledSliderValue  = (ctx and ctx.MSUF_SetLabeledSliderValue) or (ns and ns.MSUF_SetLabeledSliderValue) or _G.MSUF_SetLabeledSliderValue
    local MSUF_SetLabeledSliderEnabled = (ctx and ctx.MSUF_SetLabeledSliderEnabled) or (ns and ns.MSUF_SetLabeledSliderEnabled) or _G.MSUF_SetLabeledSliderEnabled
    local MSUF_SetCheckboxEnabled      = (ctx and ctx.MSUF_SetCheckboxEnabled) or _G.MSUF_SetCheckboxEnabled
    local MSUF_StyleCheckmark          = (ctx and ctx.MSUF_StyleCheckmark) or _G.MSUF_StyleCheckmark
    local MSUF_StyleToggleText         = (ctx and ctx.MSUF_StyleToggleText) or _G.MSUF_StyleToggleText
    local MSUF_Options_RequestLayoutForKey = (ctx and ctx.MSUF_Options_RequestLayoutForKey) or _G.MSUF_Options_RequestLayoutForKey
    local MSUF_CreateGradientDirectionPad  = (ctx and ctx.MSUF_CreateGradientDirectionPad) or _G.MSUF_CreateGradientDirectionPad
    local MSUF_BarsMenu_QueueScrollUpdate = ctx and ctx.MSUF_BarsMenu_QueueScrollUpdate
    local MSUF_UpdatePowerBarBorderSizeFromEdit = ctx and ctx.MSUF_UpdatePowerBarBorderSizeFromEdit
    local MSUF_UpdatePowerBarHeightFromEdit     = ctx and ctx.MSUF_UpdatePowerBarHeightFromEdit
    local MSUF_InitSimpleDropdown      = _G.MSUF_InitSimpleDropdown
    local MSUF_SyncSimpleDropdown      = _G.MSUF_SyncSimpleDropdown
    local MSUF_ExpandDropdownClickArea = (ns and ns.MSUF_ExpandDropdownClickArea) or _G.MSUF_ExpandDropdownClickArea
    local MSUF_MakeDropdownScrollable  = (ns and ns.MSUF_MakeDropdownScrollable) or _G.MSUF_MakeDropdownScrollable
    local MSUF_SetDropDownEnabled      = (ns and ns.MSUF_SetDropDownEnabled) or _G.MSUF_SetDropDownEnabled
    local MSUF_GetLSM          = (ns and ns.MSUF_GetLSM) or _G.MSUF_GetLSM
    local MSUF_KillMenuPreviewBar = _G.MSUF_KillMenuPreviewBar
    local MSUF_StyleSlider     = (ns and ns.MSUF_StyleSlider) or _G.MSUF_StyleSlider
    local MSUF_TEX_WHITE8      = "Interface\\Buttons\\WHITE8x8"
    if type(CreateLabeledCheckButton) ~= "function" then return end
    if type(MSUF_ExpandDropdownClickArea) ~= "function" then MSUF_ExpandDropdownClickArea = function() end end
    if type(MSUF_MakeDropdownScrollable) ~= "function" then MSUF_MakeDropdownScrollable = function() end end
    if type(MSUF_SetCheckboxEnabled) ~= "function" then MSUF_SetCheckboxEnabled = function() end end
    if type(MSUF_StyleCheckmark) ~= "function" then MSUF_StyleCheckmark = function() end end
    if type(MSUF_StyleToggleText) ~= "function" then MSUF_StyleToggleText = function() end end
    if type(MSUF_Options_RequestLayoutForKey) ~= "function" then MSUF_Options_RequestLayoutForKey = function() end end
    if type(MSUF_UpdatePowerBarBorderSizeFromEdit) ~= "function" then MSUF_UpdatePowerBarBorderSizeFromEdit = function() end end
    if type(MSUF_UpdatePowerBarHeightFromEdit) ~= "function" then MSUF_UpdatePowerBarHeightFromEdit = function() end end
    if type(MSUF_BarsMenu_QueueScrollUpdate) ~= "function" then MSUF_BarsMenu_QueueScrollUpdate = function() end end
    local function EnsureDB() if type(_G.EnsureDB) == "function" then _G.EnsureDB() end end
    local function ApplyAllSettings() if type(_G.ApplyAllSettings) == "function" then _G.ApplyAllSettings() end end
    -- -----------------------------------------------------------------
    -- Forward-declare all bar widget locals
    -- -----------------------------------------------------------------
    local barsTitle, absorbDisplayLabel, absorbDisplayDrop
    local gradientCheck, powerGradientCheck, gradientDirPad
    local gradientStrengthSlider, barOutlineThicknessSlider, highlightBorderThicknessSlider
    local targetPowerBarCheck, bossPowerBarCheck, playerPowerBarCheck, focusPowerBarCheck
    local powerBarHeightEdit, powerBarEmbedCheck, powerBarBorderCheck, powerBarBorderSizeEdit
    local hpModeDrop, barTextureDrop, barBgTextureDrop
    local aggroOutlineDrop, aggroTestCheck
    local dispelOutlineDrop, dispelTestCheck
    local purgeOutlineDrop, purgeTestCheck
    local prioCheck
    local updateThrottleSlider, powerBarHeightSlider
    local infoTooltipDisableCheck
    local hpSpacerSelectedLabel, hpSpacerInfoButton
    local MSUF_BarsApplyGradient
    -- -----------------------------------------------------------------
    -- BUILD (extracted from MSUF_Options_Core.lua — zero behavior change)
    -- -----------------------------------------------------------------
local BAR_DROPDOWN_WIDTH = 260
    barsTitle = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    barsTitle:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 16, -178)
    barsTitle:SetText(TR("Bar appearance"))
local MSUF_RefreshAbsorbBarUIEnabled
-- Forward-declared scope refs (filled when scope system is created below).
-- These allow absorb dropdowns to be scope-aware even though they're created first.
local _MSUF_BarScope_GetUnitKey     -- function() → unitKey or nil
local _MSUF_BarScope_GetUnitDB      -- function(unitKey) → unit DB table
local _MSUF_BarScope_EnableOverride -- function(unitKey)
local _MSUF_BarScope_SyncUI         -- function()  (refresh all scope-aware controls)
-- Absorb display (moved from Misc -> Bar appearance; replaces Bar mode which is now in Colors)
absorbDisplayLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbDisplayLabel:SetPoint("TOPLEFT", barsTitle, "BOTTOMLEFT", 0, -8)
absorbDisplayLabel:SetText(TR("Absorb display"))
absorbDisplayDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_AbsorbDisplayDrop", barGroup) or CreateFrame("Frame", "MSUF_AbsorbDisplayDrop", barGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(absorbDisplayDrop)
absorbDisplayDrop:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbDisplayDrop, BAR_DROPDOWN_WIDTH)
local absorbDisplayOptions = {
    { key = 1, label = "Absorb off" },
    { key = 2, label = "Absorb bar" },
    { key = 3, label = "Absorb bar + text" },
    { key = 4, label = "Absorb text only" },
}
local function MSUF_GetAbsorbDisplayMode()
    EnsureDB()
    local g = MSUF_DB.general or {}
    -- Per-unit override
    if type(_MSUF_BarScope_GetUnitKey) == "function" then
        local unitKey = _MSUF_BarScope_GetUnitKey()
        if unitKey then
            local u = MSUF_DB[unitKey]
            if u and u.hpPowerTextOverride == true and u.absorbTextMode ~= nil then
                local m = tonumber(u.absorbTextMode)
                if m and m >= 1 and m <= 4 then return m end
            end
        end
    end
    local mode = tonumber(g.absorbTextMode)
    if mode and mode >= 1 and mode <= 4 then  return mode end
    local barOn  = (g.enableAbsorbBar ~= false)
    local textOn = (g.showTotalAbsorbAmount == true)
    if (not barOn) and (not textOn) then  return 1 end
    if barOn and (not textOn) then  return 2 end
    if barOn and textOn then  return 3 end
     return 4
end
local function MSUF_BindAbsorbDropdown(drop, options, getKey, dbField, applyFunc)
    if not drop then  return end
    MSUF_InitSimpleDropdown(drop, options, getKey, function(mode)
        EnsureDB()
        -- Scope-aware: write to unit DB if a unit is selected, else to general.
        local unitKey = type(_MSUF_BarScope_GetUnitKey) == "function" and _MSUF_BarScope_GetUnitKey() or nil
        if unitKey then
            local u = type(_MSUF_BarScope_GetUnitDB) == "function" and _MSUF_BarScope_GetUnitDB(unitKey) or nil
            if u then
                if u.hpPowerTextOverride ~= true and type(_MSUF_BarScope_EnableOverride) == "function" then
                    _MSUF_BarScope_EnableOverride(unitKey)
                end
                u[dbField] = mode
            end
        else
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general[dbField] = mode
        end
        if type(applyFunc) == "function" then pcall(applyFunc, mode) end
        if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end
        -- Sync override checkbox (may have been auto-enabled).
        if type(_MSUF_BarScope_SyncUI) == "function" then _MSUF_BarScope_SyncUI() end
     end, nil, BAR_DROPDOWN_WIDTH)
    drop:HookScript("OnShow", function()
        MSUF_SyncSimpleDropdown(drop, options, getKey)
        if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end
     end)
 end
MSUF_BindAbsorbDropdown(absorbDisplayDrop, absorbDisplayOptions, MSUF_GetAbsorbDisplayMode, "absorbTextMode", function(mode)
    if type(_G.MSUF_UpdateAbsorbTextMode) == "function" then _G.MSUF_UpdateAbsorbTextMode(mode) end
    if type(_G.MSUF_UpdateAllUnitFrames) == "function" then
        _G.MSUF_UpdateAllUnitFrames()
    elseif _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then UpdateSimpleUnitFrame(frame) end
        end
    end
 end)
-- Absorb anchoring (which side positive absorb / heal-absorb start on)
absorbAnchorLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbAnchorLabel:SetPoint("TOPLEFT", absorbDisplayDrop, "BOTTOMLEFT", 16, -8)
absorbAnchorLabel:SetText(TR("Absorb bar anchoring"))
absorbAnchorDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_AbsorbAnchorDrop", barGroup) or CreateFrame("Frame", "MSUF_AbsorbAnchorDrop", barGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(absorbAnchorDrop)
absorbAnchorDrop:SetPoint("TOPLEFT", absorbAnchorLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbAnchorDrop, BAR_DROPDOWN_WIDTH)
local absorbAnchorOptions = {
    { key = 1, label = "Anchor to left side" },
    { key = 2, label = "Anchor to right side" },
	    { key = 3, label = "Follow HP bar" },
	    { key = 4, label = "Follow HP bar (overflow)" },
	    { key = 5, label = "Reverse from max" },
}
local function MSUF_GetAbsorbAnchorMode()
    EnsureDB()
    local g = MSUF_DB.general or {}
    -- Per-unit override
    if type(_MSUF_BarScope_GetUnitKey) == "function" then
        local unitKey = _MSUF_BarScope_GetUnitKey()
        if unitKey then
            local u = MSUF_DB[unitKey]
            if u and u.hpPowerTextOverride == true and u.absorbAnchorMode ~= nil then
                return tonumber(u.absorbAnchorMode) or 2
            end
        end
    end
    return tonumber(g.absorbAnchorMode) or 2
end
MSUF_BindAbsorbDropdown(absorbAnchorDrop, absorbAnchorOptions, MSUF_GetAbsorbAnchorMode, "absorbAnchorMode", function()
    if _G.MSUF_UnitFrames and type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then
                _G.MSUF_ApplyAbsorbAnchorMode(frame)
                if UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(frame) end
            end
        end
    end
 end)
-- Absorb bar textures (optional overrides; default follows foreground texture)
absorbTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbTextureLabel:SetPoint("TOPLEFT", absorbAnchorDrop, "BOTTOMLEFT", 16, -8)
absorbTextureLabel:SetText(TR("Absorb bar texture (SharedMedia)"))
absorbBarTextureDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_AbsorbBarTextureDropdown", barGroup) or CreateFrame("Frame", "MSUF_AbsorbBarTextureDropdown", barGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(absorbBarTextureDrop)
absorbBarTextureDrop:SetPoint("TOPLEFT", absorbTextureLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbBarTextureDrop, BAR_DROPDOWN_WIDTH)
absorbBarTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
absorbBarTextureDrop._msufTweakBarTexturePreview = true
MSUF_MakeDropdownScrollable(absorbBarTextureDrop, 12)
healAbsorbTextureDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_HealAbsorbBarTextureDropdown", barGroup) or CreateFrame("Frame", "MSUF_HealAbsorbBarTextureDropdown", barGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(healAbsorbTextureDrop)
healAbsorbTextureDrop:SetPoint("TOPLEFT", absorbBarTextureDrop, "BOTTOMLEFT", 0, -8)
UIDropDownMenu_SetWidth(healAbsorbTextureDrop, BAR_DROPDOWN_WIDTH)
healAbsorbTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
healAbsorbTextureDrop._msufTweakBarTexturePreview = true
MSUF_MakeDropdownScrollable(healAbsorbTextureDrop, 12)
-- Live apply (no-op until runtime supports these keys; safe to call if function exists)
local function _MSUF_TryApplyAbsorbTexturesLive()
    local applied = false
    if type(_G.MSUF_UpdateAbsorbBarTextures) == "function" then
        _G.MSUF_UpdateAbsorbBarTextures()
        applied = true
    elseif type(_G.MSUF_UpdateAllUnitFrames) == "function" then
        _G.MSUF_UpdateAllUnitFrames()
        applied = true
    elseif type(_G.MSUF_RefreshAllUnitFrames) == "function" then
        _G.MSUF_RefreshAllUnitFrames()
        applied = true
    elseif _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then UpdateSimpleUnitFrame(frame) end
        end
        applied = true
    end
    -- If Test Mode is active, force an immediate refresh so the preview overlays
    -- pick up the newly selected textures *right away*.
    if _G.MSUF_AbsorbTextureTestMode and _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then UpdateSimpleUnitFrame(frame) end
        end
    end
     return applied
end
local function _MSUF_AddStatusbarTextureSwatch(info, key, LSM)
    local swatchTex
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
        swatchTex = _G.MSUF_ResolveStatusbarTextureKey(key)
    elseif LSM and type(LSM.Fetch) == "function" then
        swatchTex = LSM:Fetch("statusbar", key, true)
    end
    if swatchTex then
        info.icon = swatchTex
        info.iconInfo = {
            tCoordLeft = 0,
            tCoordRight = 0.85,
            tCoordTop = 0,
            tCoordBottom = 1,
            iconWidth = 80,
            iconHeight = 12,
        }
    else
        info.icon = nil
        info.iconInfo = nil
    end
 end
local function _MSUF_GetStatusbarTextureList()
    local LSM = MSUF_GetLSM()
    local list
    if LSM and type(LSM.List) == "function" then
        list = LSM:List("statusbar")
    else
        list = {
            "Blizzard",
            "Flat",
            "RaidHP",
            "RaidPower",
            "Skills",
            "Outline",
            "TooltipBorder",
            "DialogBG",
            "Parchment",
        }
    end
    if type(list) ~= "table" or #list == 0 then list = { "Blizzard" } end
    table.sort(list, function(a, b)
        a = tostring(a or "")
        b = tostring(b or "")
        return a:lower() < b:lower()
    end)
     return list, LSM
end
-- Sync helper: set dropdown display text/selected value from the stored texture.
-- Handles optional followText entries ("Use foreground texture").
local function _MSUF_SyncStatusbarTextureDropdown(drop)
    local cfg = drop and drop.__MSUF_TexCfg
    if not cfg then  return end
    EnsureDB()
    local cur = cfg.get and cfg.get() or nil
    if cfg.followText and ((cfg.isFollow and cfg.isFollow(cur)) or cur == nil or cur == "" or cur == cfg.followValue) then
        UIDropDownMenu_SetSelectedValue(drop, cfg.followValue or "")
        UIDropDownMenu_SetText(drop, cfg.followText)
         return
    end
    cur = cur or ""
    UIDropDownMenu_SetSelectedValue(drop, cur)
    UIDropDownMenu_SetText(drop, cur)
 end
-- Generic statusbar texture dropdown builder (SharedMedia + built-in fallback)
-- Used by multiple menus (Bars/Absorb/etc.) to avoid repeating ~100 lines of boilerplate each time.
local function _MSUF_InitStatusbarTextureDropdown(drop, cfg)
    if not drop or not cfg then  return end
    drop.__MSUF_TexCfg = cfg
    if cfg.width then UIDropDownMenu_SetWidth(drop, cfg.width) end
    UIDropDownMenu_Initialize(drop, function(self, level)
        if not level then  return end
        EnsureDB()
        cfg = drop.__MSUF_TexCfg
        if not cfg then  return end
        local info = UIDropDownMenu_CreateInfo()
        local current = cfg.get and cfg.get() or nil
        -- Optional "follow" entry (e.g. "Use foreground texture")
        if cfg.followText then
            info.text = cfg.followText
            info.value = cfg.followValue or ""
            info.func = function(btn)
                if cfg.setFollow then cfg.setFollow(btn.value) elseif cfg.set then cfg.set(btn.value) end
                UIDropDownMenu_SetSelectedValue(drop, btn.value)
                UIDropDownMenu_SetText(drop, cfg.followText)
             end
            info.checked = (cfg.isFollow and cfg.isFollow(current)) or (current == nil or current == cfg.followValue or current == "")
            info.notCheckable = nil
            info.icon = nil
            info.iconInfo = nil
            UIDropDownMenu_AddButton(info, level)
            -- Separator
            local sep = UIDropDownMenu_CreateInfo()
            sep.text = " "
            sep.isTitle = true
            sep.notCheckable = true
            sep.disabled = true
            UIDropDownMenu_AddButton(sep, level)
        end
        local list, LSM = _MSUF_GetStatusbarTextureList()
        for _, name in ipairs(list) do
            info.text = name
            info.value = name
            info.func = function(btn)
                if cfg.set then cfg.set(btn.value) end
                UIDropDownMenu_SetSelectedValue(drop, btn.value)
                UIDropDownMenu_SetText(drop, btn.value)
             end
            info.checked = (name == current)
            _MSUF_AddStatusbarTextureSwatch(info, name, LSM)
            UIDropDownMenu_AddButton(info, level)
        end
     end)
    if not drop.__MSUF_TexSyncHooked then
        drop.__MSUF_TexSyncHooked = true
        local prev = drop:GetScript("OnShow")
        drop:SetScript("OnShow", function(self, ...)
            if prev then prev(self, ...) end
            _MSUF_SyncStatusbarTextureDropdown(self)
         end)
    end
    _MSUF_SyncStatusbarTextureDropdown(drop)
 end
_G.MSUF_InitStatusbarTextureDropdown = _MSUF_InitStatusbarTextureDropdown
_G.MSUF_SyncStatusbarTextureDropdown = _MSUF_SyncStatusbarTextureDropdown
_G.MSUF_KillMenuPreviewBar = MSUF_KillMenuPreviewBar

-- Resolve a SharedMedia statusbar key (e.g. "Flat") → texture path.
-- Used by ClassPower, Absorb bars, and anywhere a per-panel texture override
-- needs to be resolved from a stored key name to an actual file path.
if not _G.MSUF_ResolveStatusbarTextureKey then
    function _G.MSUF_ResolveStatusbarTextureKey(key)
        if type(key) ~= "string" or key == "" then return nil end
        local LSM = MSUF_GetLSM and MSUF_GetLSM()
        if LSM and type(LSM.Fetch) == "function" then
            local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", key, true)
            if ok and type(tex) == "string" and tex ~= "" then return tex end
        end
        return nil
    end
end
local function _MSUF_InitAbsorbTextureDropdown(drop, dbKey, followText)
    if not drop then  return end
    followText = followText or "Use foreground texture"
    _MSUF_InitStatusbarTextureDropdown(drop, {
        width = 200,
        followText = followText,
        followValue = "",
        get = function()
            EnsureDB()
            local g = (MSUF_DB and MSUF_DB.general) or {}
            local cur = g[dbKey]
            if cur == "" then cur = nil end
             return cur
        end,
        set = function(val)
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general[dbKey] = val
            _MSUF_TryApplyAbsorbTexturesLive()
            ApplyAllSettings()
         end,
        isFollow = function(cur)  return (cur == nil or cur == "") end,
    })
 end
_MSUF_InitAbsorbTextureDropdown(absorbBarTextureDrop, "absorbBarTexture", "Use foreground texture")
_MSUF_InitAbsorbTextureDropdown(healAbsorbTextureDrop, "healAbsorbBarTexture", "Use foreground texture")
-- Preview/Test mode: temporarily force-show absorb + heal-absorb overlays so users can see textures.
-- Runtime-only (not saved). Auto-disables when leaving the Bars menu group.
local absorbTexTestCB = CreateLabeledCheckButton(
    "MSUF_AbsorbTextureTestModeCheck",
    "Test absorb textures",
    barGroup,
    16, -1 -- placeholder; we re-anchor below
)
if absorbTexTestCB then
    absorbTexTestCB:ClearAllPoints()
    absorbTexTestCB:SetPoint("TOPLEFT", healAbsorbTextureDrop, "BOTTOMLEFT", 16, -8)
    absorbTexTestCB.tooltip = "Temporarily shows fake absorb + heal-absorb overlays so you can preview these textures.\n\nAutomatically turns off when you leave this menu."
    absorbTexTestCB:SetScript("OnShow", function(self)
        self:SetChecked(_G.MSUF_AbsorbTextureTestMode and true or false)
     end)
    local function RefreshFrames()
        local ns = _G.MSUF_NS
        if ns and ns.MSUF_RefreshAllFrames then
            ns.MSUF_RefreshAllFrames()
             return
        end
        if _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit then UpdateSimpleUnitFrame(f) end
            end
        end
     end

    -- Player-only: show your own incoming heals as a small prediction segment behind the HP bar.
    local selfHealPredCB = CreateLabeledCheckButton(
        "MSUF_SelfHealPredictionCheck",
        "Heal prediction",
        barGroup,
        16, -1 -- placeholder; we re-anchor below
    )
    if selfHealPredCB then
        selfHealPredCB:ClearAllPoints()
        -- Keep it on the same row as the absorb texture test toggle, but move it far enough
        -- to the right so the labels never overlap/clamp at common UI scales.
        -- Nudge slightly left to avoid clipping against the right edge at some UI scales.
        selfHealPredCB:SetPoint("TOPLEFT", healAbsorbTextureDrop, "BOTTOMLEFT", 200, -8)
        selfHealPredCB.tooltip = "Player only: shows incoming heals from you to you as a green segment on the health bar (ignores other players)."
        selfHealPredCB:SetScript("OnShow", function(self)
            if type(EnsureDB) == "function" then EnsureDB() end
            local g = (MSUF_DB and MSUF_DB.general) or nil
            self:SetChecked((g and g.showSelfHealPrediction) and true or false)
         end)
        selfHealPredCB:SetScript("OnClick", function(self)
            if type(EnsureDB) == "function" then EnsureDB() end
            local g = MSUF_DB and MSUF_DB.general
            if not g then return end
            local newState = self:GetChecked() and true or false
            g.showSelfHealPrediction = newState
            self:SetChecked(newState)
            if self.__msufToggleUpdate then self.__msufToggleUpdate() end
            RefreshFrames()
         end)
    end
    absorbTexTestCB:SetScript("OnClick", function(self)
		local newState = self:GetChecked() and true or false
		_G.MSUF_AbsorbTextureTestMode = newState
		-- Hard-resync the visual state (some skinned checkbuttons may not repaint until SetChecked).
		self:SetChecked(newState)
		if self.__msufToggleUpdate then self.__msufToggleUpdate() end
		RefreshFrames()
	 end)
    -- Safety: leaving the Bars menu should never keep fake overlays active.
	absorbTexTestCB:SetScript("OnHide", function(self)
		-- Only auto-disable when actually leaving the Bars tab / Settings panel.
		-- Some layouts temporarily hide controls (scroll/refresh); don't undo the toggle in that case.
		if barGroup and barGroup.IsShown and barGroup:IsShown() then  return end
		if _G.MSUF_AbsorbTextureTestMode then
			_G.MSUF_AbsorbTextureTestMode = false
			self:SetChecked(false)
			if self.__msufToggleUpdate then self.__msufToggleUpdate() end
			RefreshFrames()
		end
	 end)
    -- Extra safety: never keep fake absorb overlays active outside the Bars tab.
    -- This covers tab switches and closing the Settings window (in case a control stays shown).
    if barGroup and barGroup.HookScript and not barGroup._msufAbsorbTestCleanupHooked then
        barGroup._msufAbsorbTestCleanupHooked = true
        barGroup:HookScript("OnHide", function()
            if _G.MSUF_AbsorbTextureTestMode then
                _G.MSUF_AbsorbTextureTestMode = false
                if absorbTexTestCB and absorbTexTestCB.SetChecked then absorbTexTestCB:SetChecked(false) end
                RefreshFrames()
            end
         end)
    end
    if panel and panel.HookScript and not panel._msufAbsorbTestPanelCleanupHooked then
        panel._msufAbsorbTestPanelCleanupHooked = true
        panel:HookScript("OnHide", function()
            if _G.MSUF_AbsorbTextureTestMode then
                _G.MSUF_AbsorbTextureTestMode = false
                if absorbTexTestCB and absorbTexTestCB.SetChecked then absorbTexTestCB:SetChecked(false) end
                RefreshFrames()
            end
         end)
    end
-- Grey-out / disable absorb-only controls when the absorb BAR is off (e.g. "Absorb off" or "Absorb text only").
-- Absorb display dropdown remains enabled so users can turn the bar back on.
MSUF_RefreshAbsorbBarUIEnabled = function()
    EnsureDB()
    -- Determine bar enabled state from current scope
    local barEnabled
    local mode = MSUF_GetAbsorbDisplayMode()
    barEnabled = (mode == 2 or mode == 3)
    -- Anchor mode only matters when a bar is rendered
    MSUF_SetDropDownEnabled(absorbAnchorDrop, absorbAnchorLabel, barEnabled)
    -- Texture overrides + test mode only apply to the bars
    if absorbTextureLabel and absorbTextureLabel.SetTextColor then
        if barEnabled then
            absorbTextureLabel:SetTextColor(1, 1, 1)
        else
            absorbTextureLabel:SetTextColor(0.35, 0.35, 0.35)
        end
    end
    MSUF_SetDropDownEnabled(absorbBarTextureDrop, nil, barEnabled)
    MSUF_SetDropDownEnabled(healAbsorbTextureDrop, nil, barEnabled)
    MSUF_SetCheckboxEnabled(absorbTexTestCB, barEnabled)
    -- If user turns absorb bar off while test mode is active, hard-kill the preview immediately.
    if (not barEnabled) and _G.MSUF_AbsorbTextureTestMode then
        _G.MSUF_AbsorbTextureTestMode = false
        if absorbTexTestCB and absorbTexTestCB.SetChecked then absorbTexTestCB:SetChecked(false) end
        local ns = _G.MSUF_NS
        if ns and ns.MSUF_RefreshAllFrames then
            ns.MSUF_RefreshAllFrames()
        elseif _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit then UpdateSimpleUnitFrame(f) end
            end
        end
    end
 end
-- Initial sync once everything exists
if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end
end
gradientCheck = CreateLabeledCheckButton(
        "MSUF_GradientEnableCheck",
        "Enable HP bar gradient",
        barGroup,
        16, -260
    )
    powerGradientCheck = CreateLabeledCheckButton(
        "MSUF_PowerGradientEnableCheck",
        "Enable power bar gradient",
        barGroup,
        16, -282
    )
    -- Gradient strength (shared by HP + Power gradients). Range 0..1
    gradientStrengthSlider = CreateLabeledSlider(
        "MSUF_GradientStrengthSlider",
        "Gradient strength",
        barGroup,
        0, 1, 0.05,
        16, -304
    )
    if gradientStrengthSlider and gradientStrengthSlider.SetWidth then gradientStrengthSlider:SetWidth(260) end
    -- Gradient direction selector (shared for HP + Power)
    gradientDirPad = MSUF_CreateGradientDirectionPad(barGroup)
    targetPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_TargetPowerBarCheck",
        "Show power bar on target frame",
        barGroup,
        260, -260
    )
    bossPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_BossPowerBarCheck",
        "Show power bar on boss frames",
        barGroup,
        260, -290
    )
    playerPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_PlayerPowerBarCheck",
        "Show power bar on player frames",
        barGroup,
        260, -320
    )
    focusPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_FocusPowerBarCheck",
        "Show power bar on focus",
        barGroup,
        260, -350
    )
    powerBarHeightLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarHeightLabel:SetPoint("TOPLEFT", focusPowerBarCheck, "BOTTOMLEFT", 0, -4)
    powerBarHeightLabel:SetText(TR("Power bar height"))
    powerBarHeightEdit = CreateFrame("EditBox", "MSUF_PowerBarHeightEdit", barGroup, "InputBoxTemplate")
    powerBarHeightEdit:SetSize(40, 20)
    powerBarHeightEdit:SetAutoFocus(false)
    powerBarHeightEdit:SetPoint("LEFT", powerBarHeightLabel, "RIGHT", 4, 0)
    powerBarHeightEdit:SetTextInsets(4, 4, 2, 2)
    powerBarEmbedCheck = CreateLabeledCheckButton(
        "MSUF_PowerBarEmbedCheck",
        "Embed power bar into health bar",
        barGroup,
        260, -380
    )
    powerBarBorderCheck = CreateLabeledCheckButton(
        "MSUF_PowerBarBorderCheck",
        "Show power bar border",
        barGroup,
        260, -410
    )
    powerBarBorderSizeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarBorderSizeLabel:SetPoint("TOPLEFT", powerBarBorderCheck, "BOTTOMLEFT", 0, -6)
    powerBarBorderSizeLabel:SetText(TR("Border thickness"))
    powerBarBorderSizeEdit = CreateFrame("EditBox", "MSUF_PowerBarBorderSizeEdit", barGroup, "InputBoxTemplate")
    powerBarBorderSizeEdit:SetSize(40, 20)
    powerBarBorderSizeEdit:SetAutoFocus(false)
    powerBarBorderSizeEdit:SetPoint("LEFT", powerBarBorderSizeLabel, "RIGHT", 10, 0)
    powerBarBorderSizeEdit:SetTextInsets(4, 4, 2, 2)

    -- Bar settings scope (Shared vs per-unit override). Controls text + absorb per-unit.
    hpPowerScopeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hpPowerScopeLabel:SetPoint("TOPLEFT", powerBarBorderSizeLabel or powerBarBorderCheck or powerBarEmbedCheck or powerBarHeightLabel, "BOTTOMLEFT", 0, -16)
    hpPowerScopeLabel:SetText(TR("Bar settings"))
    hpPowerScopeDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_HPTextScopeDropdown", barGroup) or CreateFrame("Frame", "MSUF_HPTextScopeDropdown", barGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(hpPowerScopeDrop)
    hpPowerScopeDrop:SetPoint("TOPLEFT", hpPowerScopeLabel, "BOTTOMLEFT", -16, -4)
    hpPowerScopeOptions = {
        { key = "shared",      label = "Shared" },
        { key = "player",      label = "Player" },
        { key = "target",      label = "Target" },
        { key = "targettarget",label = "Target of Target" },
        { key = "focus",       label = "Focus" },
        { key = "pet",         label = "Pet" },
        { key = "boss",        label = "Boss" },
    }

    local function _MSUF_HPText_NormalizeScopeKey(k)
        if k == "tot" then k = "targettarget" end
        if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(k) then k = "boss" end
        if k ~= "shared" and k ~= "player" and k ~= "target" and k ~= "focus" and k ~= "targettarget" and k ~= "pet" and k ~= "boss" then
            return "shared"
        end
        return k
    end

    local function _MSUF_HPText_GetScopeKey()
        EnsureDB()
        local g = MSUF_DB.general
        local k = _MSUF_HPText_NormalizeScopeKey(g.hpPowerTextSelectedKey)
        g.hpPowerTextSelectedKey = k
        return k
    end

    local function _MSUF_HPText_GetUnitKey()
        local k = _MSUF_HPText_GetScopeKey()
        if k == "shared" then return nil end
        return k
    end

    local function _MSUF_HPText_GetUnitDB(unitKey)
        if not unitKey then return nil end
        EnsureDB()
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        return MSUF_DB[unitKey]
    end

    local function _MSUF_HPText_EnableOverride(unitKey)
        if not unitKey then return end
        EnsureDB()
        local g = MSUF_DB.general
        local u = _MSUF_HPText_GetUnitDB(unitKey)
        if not u then return end
        if u.hpPowerTextOverride ~= true then
            u.hpPowerTextOverride = true
        end
        if u.hpTextMode == nil then u.hpTextMode = g.hpTextMode end
        if u.powerTextMode == nil then u.powerTextMode = g.powerTextMode end
        if u.hpTextSeparator == nil then u.hpTextSeparator = g.hpTextSeparator end
        if u.powerTextSeparator == nil then
            u.powerTextSeparator = (g.powerTextSeparator ~= nil) and g.powerTextSeparator or g.hpTextSeparator
        end
	        -- Spacers: copy Shared into unit on first enable so the unit starts identical.
	        if u.hpTextSpacerEnabled == nil then u.hpTextSpacerEnabled = g.hpTextSpacerEnabled end
	        if u.hpTextSpacerX == nil then u.hpTextSpacerX = g.hpTextSpacerX end
	        if u.powerTextSpacerEnabled == nil then u.powerTextSpacerEnabled = g.powerTextSpacerEnabled end
	        if u.powerTextSpacerX == nil then u.powerTextSpacerX = g.powerTextSpacerX end
	        -- Absorb settings: copy Shared into unit on first enable.
	        if u.absorbTextMode == nil then u.absorbTextMode = g.absorbTextMode end
	        if u.absorbAnchorMode == nil then u.absorbAnchorMode = g.absorbAnchorMode end
		        -- Text anchors: copy Shared into unit on first enable.
		        if u.hpTextAnchor == nil then u.hpTextAnchor = g.hpTextAnchor end
		        if u.powerTextAnchor == nil then u.powerTextAnchor = g.powerTextAnchor end
    end

    -- Wire up forward-declared scope refs so absorb dropdowns (created earlier) can be scope-aware.
    _MSUF_BarScope_GetUnitKey     = _MSUF_HPText_GetUnitKey
    _MSUF_BarScope_GetUnitDB      = _MSUF_HPText_GetUnitDB
    _MSUF_BarScope_EnableOverride = _MSUF_HPText_EnableOverride

    -- Override checkbox (only relevant for unit scopes).
    hpPowerOverrideCheck = CreateFrame('CheckButton', 'MSUF_HPTextOverrideCheck', barGroup, 'UICheckButtonTemplate')
    hpPowerOverrideCheck:SetPoint('TOPLEFT', hpPowerScopeDrop, 'BOTTOMLEFT', 16, -6)
    hpPowerOverrideCheck.text = _G['MSUF_HPTextOverrideCheckText']
    if hpPowerOverrideCheck.text then
        hpPowerOverrideCheck.text:SetText(TR('Override shared settings'))
    end
    MSUF_StyleToggleText(hpPowerOverrideCheck)
    MSUF_StyleCheckmark(hpPowerOverrideCheck)
    hpPowerOverrideCheck:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        GameTooltip:SetText('Per-unit override', 1, 1, 1)
        GameTooltip:AddLine('When unchecked, this unit inherits Shared settings for text modes, absorb display, and spacers.', 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine('Changing any per-unit setting will auto-enable this override.', 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    hpPowerOverrideCheck:SetScript('OnLeave', function() GameTooltip:Hide() end)

    -- Re-anchor Bar scope (Shared/Override) to the TOP of the Bars menu so it's always visible.
    -- A header label makes the purpose clear.
    if not barGroup._msufBarScopeHeader then
        local hdr = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        hdr:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 16, -120)
        hdr:SetText(TR("Bar scope"))
        barGroup._msufBarScopeHeader = hdr
    end
    hpPowerScopeLabel:ClearAllPoints()
    hpPowerScopeLabel:SetPoint("TOPLEFT", barGroup._msufBarScopeHeader, "BOTTOMLEFT", 0, -6)
    hpPowerScopeLabel:SetText(TR("Configure settings for"))
    hpPowerScopeDrop:ClearAllPoints()
    hpPowerScopeDrop:SetPoint("TOPLEFT", hpPowerScopeLabel, "BOTTOMLEFT", -16, -4)
    hpPowerOverrideCheck:ClearAllPoints()
    hpPowerOverrideCheck:SetPoint("TOPLEFT", hpPowerScopeDrop, "TOPRIGHT", 10, -4)

    hpModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hpModeLabel:SetPoint("TOPLEFT", hpPowerOverrideCheck, "BOTTOMLEFT", 0, -44)
    hpModeLabel:SetText(TR("Textmode HP / Power"))
    -- Make this header white (requested UX): the dropdown items remain normal.
    hpModeLabel:SetTextColor(1, 1, 1, 1)
    hpModeDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_HPTextModeDropdown", barGroup) or CreateFrame("Frame", "MSUF_HPTextModeDropdown", barGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(hpModeDrop)
    hpModeDrop:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -4)
    hpModeOptions = {
        { key = "FULL_ONLY",          label = "Full value only" },
        { key = "FULL_PLUS_PERCENT",  label = "Full value + %" },
        { key = "PERCENT_PLUS_FULL",  label = "% + Full value" },
        { key = "PERCENT_ONLY",       label = "Only %" },
    }

    local function _MSUF_HPText_GetHpModeKey()
        EnsureDB()
        local g = MSUF_DB.general
        local unitKey = _MSUF_HPText_GetUnitKey()
        if not unitKey then
            return (g.hpTextMode or "FULL_PLUS_PERCENT")
        end
        local u = _MSUF_HPText_GetUnitDB(unitKey)
        if u and u.hpPowerTextOverride == true and u.hpTextMode ~= nil then
            return u.hpTextMode
        end
        return (g.hpTextMode or "FULL_PLUS_PERCENT")
    end

    local function _MSUF_HPText_SetHpModeKey(v)
        EnsureDB()
        local g = MSUF_DB.general
        local unitKey = _MSUF_HPText_GetUnitKey()
        if not unitKey then
            g.hpTextMode = v
            return
        end
        local u = _MSUF_HPText_GetUnitDB(unitKey)
        if u and u.hpPowerTextOverride ~= true then
            _MSUF_HPText_EnableOverride(unitKey)
        end
        u.hpTextMode = v
    end
    hpModeDrop._msufGetCurrentKey = _MSUF_HPText_GetHpModeKey
    MSUF_InitSimpleDropdown(
        hpModeDrop,
        hpModeOptions,
        _MSUF_HPText_GetHpModeKey,
        _MSUF_HPText_SetHpModeKey,
        function(v, opt)
            ApplyAllSettings()
            local unitKey = _MSUF_HPText_GetUnitKey()
            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                if unitKey then
                    _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
                else
                    _G.MSUF_ForceTextLayoutForUnitKey("player")
                    _G.MSUF_ForceTextLayoutForUnitKey("target")
                    _G.MSUF_ForceTextLayoutForUnitKey("focus")
                    _G.MSUF_ForceTextLayoutForUnitKey("targettarget")
                    _G.MSUF_ForceTextLayoutForUnitKey("pet")
                    _G.MSUF_ForceTextLayoutForUnitKey("boss")
                end
            end
            if type(_G.MSUF_Options_RefreshHPSpacerControls) == "function" then _G.MSUF_Options_RefreshHPSpacerControls() end
            -- Sync override checkbox (may have been auto-enabled)
            if type(_MSUF_BarScope_SyncUI) == "function" then _MSUF_BarScope_SyncUI() end
         end,
        BAR_DROPDOWN_WIDTH
    )
powerModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerModeLabel:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", 0, -16)
    powerModeLabel:SetText(TR("Power text mode"))
    powerModeDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_PowerTextModeDropdown", barGroup) or CreateFrame("Frame", "MSUF_PowerTextModeDropdown", barGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(powerModeDrop)
    powerModeDrop:SetPoint("TOPLEFT", powerModeLabel, "BOTTOMLEFT", -16, -16)
    powerModeOptions = {
        { key = "CURRENT", label = "Current" },
        { key = "MAX", label = "Max" },
        { key = "CURMAX", label = "Cur/Max" },
        { key = "PERCENT", label = "Percent" },
        { key = "CURPERCENT", label = "Cur + Percent" },
        { key = "CURMAXPERCENT", label = "Cur/Max + Percent" },
    }

    local function _MSUF_NormalizePowerTextMode_Local(mode)
        if type(_G.MSUF_NormalizePowerTextMode) == "function" then
            return _G.MSUF_NormalizePowerTextMode(mode)
        end
        if mode == nil then return "CURPERCENT" end
        if mode == "FULL_SLASH_MAX" then return "CURMAX" end
        if mode == "FULL_ONLY" then return "CURRENT" end
        if mode == "PERCENT_ONLY" then return "PERCENT" end
        if mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
        return mode
    end
    local function _MSUF_HPText_GetPowerModeKey()
        EnsureDB()
        local g = MSUF_DB.general
        local unitKey = _MSUF_HPText_GetUnitKey()
        if not unitKey then
            return _MSUF_NormalizePowerTextMode_Local(g.powerTextMode)
        end
        local u = _MSUF_HPText_GetUnitDB(unitKey)
        if u and u.hpPowerTextOverride == true and u.powerTextMode ~= nil then
            return _MSUF_NormalizePowerTextMode_Local(u.powerTextMode)
        end
        return _MSUF_NormalizePowerTextMode_Local(g.powerTextMode)
    end

    local function _MSUF_HPText_SetPowerModeKey(v)
        EnsureDB()
        local g = MSUF_DB.general
        local unitKey = _MSUF_HPText_GetUnitKey()
        if not unitKey then
            g.powerTextMode = v
            return
        end
        local u = _MSUF_HPText_GetUnitDB(unitKey)
        if u and u.hpPowerTextOverride ~= true then
            _MSUF_HPText_EnableOverride(unitKey)
        end
        u.powerTextMode = v
    end
    powerModeDrop._msufGetCurrentKey = _MSUF_HPText_GetPowerModeKey
    MSUF_InitSimpleDropdown(
        powerModeDrop,
        powerModeOptions,
        _MSUF_HPText_GetPowerModeKey,
        _MSUF_HPText_SetPowerModeKey,
        function(v, opt)
            ApplyAllSettings()
            local unitKey = _MSUF_HPText_GetUnitKey()
            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                if unitKey then
                    _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
                else
                    _G.MSUF_ForceTextLayoutForUnitKey("player")
                    _G.MSUF_ForceTextLayoutForUnitKey("target")
                    _G.MSUF_ForceTextLayoutForUnitKey("focus")
                    _G.MSUF_ForceTextLayoutForUnitKey("targettarget")
                    _G.MSUF_ForceTextLayoutForUnitKey("pet")
                    _G.MSUF_ForceTextLayoutForUnitKey("boss")
                end
            end
            if type(_MSUF_BarScope_SyncUI) == "function" then _MSUF_BarScope_SyncUI() end
         end,
        BAR_DROPDOWN_WIDTH
    )
-- Text separators (HP + Power)
    sepHeader = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sepHeader:SetPoint("TOPLEFT", powerModeDrop, "BOTTOMLEFT", 16, -12)
    sepHeader:SetText(TR("Text Separators"))
    hpSepLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    -- Extra spacing from the header (prevents cramped look)
    hpSepLabel:SetPoint("TOPLEFT", sepHeader, "BOTTOMLEFT", 0, -10)
    hpSepLabel:SetText(TR("Health (HP)"))
    hpSepDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_HPTextSeparatorDropdown", barGroup) or CreateFrame("Frame", "MSUF_HPTextSeparatorDropdown", barGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(hpSepDrop)
    -- Both dropdowns sit slightly lower (5px) for nicer vertical balance.
    hpSepDrop:SetPoint("TOPLEFT", hpSepLabel, "BOTTOMLEFT", -16, -16)
    UIDropDownMenu_SetWidth(hpSepDrop, 80)
    -- In the Flash/Slash menu container, UIDropDownMenu can anchor incorrectly.
    -- Force the dropdown list to open anchored under this dropdown.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(hpSepDrop, 0, 0, "TOPLEFT", hpSepDrop, "BOTTOMLEFT")
    else
        hpSepDrop.xOffset = 0
        hpSepDrop.yOffset = 0
        hpSepDrop.point = "TOPLEFT"
        hpSepDrop.relativeTo = hpSepDrop
        hpSepDrop.relativePoint = "BOTTOMLEFT"
    end
    local textSepOptions = {
        { key = "",  label = " ", menuText = "Space / none" }, -- empty  looks blank, just space between values
        { key = "-", label = "-" },
        { key = "/", label = "/" },
        { key = "\\", label = "\\" },
        { key = "|", label = "|" },
        { key = "<", label = "<" },
        { key = ">", label = ">" },
        { key = "~", label = "~" },
        { key = "\194\183", label = "\194\183", menuText = "\194\183  (middle dot)" },
        { key = "\226\128\162", label = "\226\128\162", menuText = "\226\128\162  (bullet)" },
        { key = ":", label = ":" },
        { key = "\194\187", label = "\194\187", menuText = "\194\187  (guillemet right)" },
        { key = "\194\171", label = "\194\171", menuText = "\194\171  (guillemet left)" },
    }
    MSUF_InitSimpleDropdown(
        hpSepDrop,
        textSepOptions,
        function()
            EnsureDB()
            local g = MSUF_DB.general
            local unitKey = _MSUF_HPText_GetUnitKey()
            if not unitKey then
                return (g.hpTextSeparator or "")
            end
            local u = _MSUF_HPText_GetUnitDB(unitKey)
            if u and u.hpPowerTextOverride == true and u.hpTextSeparator ~= nil then
                return u.hpTextSeparator
            end
            return (g.hpTextSeparator or "")
        end,
        function(v)
            EnsureDB()
            local g = MSUF_DB.general
            local unitKey = _MSUF_HPText_GetUnitKey()
            if not unitKey then
                g.hpTextSeparator = v
                -- Force immediate text re-render for all units (Shared scope).
                if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                    _G.MSUF_ForceTextLayoutForUnitKey("player")
                    _G.MSUF_ForceTextLayoutForUnitKey("target")
                    _G.MSUF_ForceTextLayoutForUnitKey("focus")
                    _G.MSUF_ForceTextLayoutForUnitKey("targettarget")
                    _G.MSUF_ForceTextLayoutForUnitKey("pet")
                    _G.MSUF_ForceTextLayoutForUnitKey("boss")
                end
                return
            end
            local u = _MSUF_HPText_GetUnitDB(unitKey)
            if u and u.hpPowerTextOverride ~= true then
                _MSUF_HPText_EnableOverride(unitKey)
            end
            u.hpTextSeparator = v
            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
            end
            if type(_MSUF_BarScope_SyncUI) == "function" then _MSUF_BarScope_SyncUI() end
        end,
        "all"
    )
-- Power separator (separate from HP separator; falls back to HP separator if unset for backward compatibility)
    powerSepLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerSepLabel:SetPoint("LEFT", hpSepLabel, "RIGHT", 120, 0)
    powerSepLabel:SetText(TR("Power"))
    powerSepDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_PowerTextSeparatorDropdown", barGroup) or CreateFrame("Frame", "MSUF_PowerTextSeparatorDropdown", barGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(powerSepDrop)
    powerSepDrop:SetPoint("TOPLEFT", powerSepLabel, "BOTTOMLEFT", -16, -16)
    UIDropDownMenu_SetWidth(powerSepDrop, 80)
    -- Same anchor fix for the power separator dropdown.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(powerSepDrop, 0, 0, "TOPLEFT", powerSepDrop, "BOTTOMLEFT")
    else
        powerSepDrop.xOffset = 0
        powerSepDrop.yOffset = 0
        powerSepDrop.point = "TOPLEFT"
        powerSepDrop.relativeTo = powerSepDrop
        powerSepDrop.relativePoint = "BOTTOMLEFT"
    end
    MSUF_InitSimpleDropdown(
        powerSepDrop,
        textSepOptions,
        function()
            EnsureDB()
            local g = MSUF_DB.general
            local unitKey = _MSUF_HPText_GetUnitKey()
            if unitKey then
                local u = _MSUF_HPText_GetUnitDB(unitKey)
                if u and u.hpPowerTextOverride == true then
                    if u.powerTextSeparator ~= nil then return u.powerTextSeparator end
                    if u.hpTextSeparator ~= nil then return u.hpTextSeparator end
                end
            end
            return (g.powerTextSeparator ~= nil) and g.powerTextSeparator or (g.hpTextSeparator or "")
        end,
        function(v)
            EnsureDB()
            local g = MSUF_DB.general
            local unitKey = _MSUF_HPText_GetUnitKey()
            if not unitKey then
                g.powerTextSeparator = v
                -- Force immediate text re-render for all units (Shared scope).
                if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                    _G.MSUF_ForceTextLayoutForUnitKey("player")
                    _G.MSUF_ForceTextLayoutForUnitKey("target")
                    _G.MSUF_ForceTextLayoutForUnitKey("focus")
                    _G.MSUF_ForceTextLayoutForUnitKey("targettarget")
                    _G.MSUF_ForceTextLayoutForUnitKey("pet")
                    _G.MSUF_ForceTextLayoutForUnitKey("boss")
                end
                return
            end
            local u = _MSUF_HPText_GetUnitDB(unitKey)
            if u and u.hpPowerTextOverride ~= true then
                _MSUF_HPText_EnableOverride(unitKey)
            end
            u.powerTextSeparator = v
            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
            end
            if type(_MSUF_BarScope_SyncUI) == "function" then _MSUF_BarScope_SyncUI() end
        end,
        "all"
    )

    local function _MSUF_SyncHpPowerTextScopeUI()
        EnsureDB()
        local g = MSUF_DB.general
        local scopeKey = _MSUF_HPText_GetScopeKey()
        local unitKey = _MSUF_HPText_GetUnitKey()
        if hpPowerScopeDrop and hpPowerScopeOptions then
            MSUF_SyncSimpleDropdown(hpPowerScopeDrop, hpPowerScopeOptions, _MSUF_HPText_GetScopeKey)
        end
        if hpPowerOverrideCheck then
            if unitKey then
                local u = _MSUF_HPText_GetUnitDB(unitKey)
                hpPowerOverrideCheck:Show()
                hpPowerOverrideCheck:Enable()
                hpPowerOverrideCheck:SetAlpha(1)
                hpPowerOverrideCheck:SetChecked(u and u.hpPowerTextOverride == true)
            else
                hpPowerOverrideCheck:Hide()
            end
        end
        -- Show reset button only in Shared scope (when any override exists)
        local resetBtn = _G["MSUF_HPTextResetOverridesBtn"]
        if resetBtn then
            if unitKey then
                resetBtn:Hide()
            else
                -- Show only if at least one unit has an active override
                local anyOverride = false
                local unitKeys = { "player", "target", "focus", "targettarget", "pet", "boss" }
                for _, uKey in ipairs(unitKeys) do
                    local u = MSUF_DB[uKey]
                    if u and u.hpPowerTextOverride == true then anyOverride = true; break end
                end
                if anyOverride then
                    resetBtn:Show()
                else
                    resetBtn:Hide()
                end
            end
        end
        if hpModeDrop and hpModeOptions and hpModeDrop._msufGetCurrentKey then
            MSUF_SyncSimpleDropdown(hpModeDrop, hpModeOptions, hpModeDrop._msufGetCurrentKey)
        end
        if powerModeDrop and powerModeOptions and powerModeDrop._msufGetCurrentKey then
            MSUF_SyncSimpleDropdown(powerModeDrop, powerModeOptions, powerModeDrop._msufGetCurrentKey)
        end
        if hpSepDrop and textSepOptions then
            MSUF_SyncSimpleDropdown(hpSepDrop, textSepOptions, function()
                EnsureDB()
                local g0 = MSUF_DB.general
                local uKey = _MSUF_HPText_GetUnitKey()
                if not uKey then return (g0.hpTextSeparator or "") end
                local u0 = _MSUF_HPText_GetUnitDB(uKey)
                if u0 and u0.hpPowerTextOverride == true and u0.hpTextSeparator ~= nil then return u0.hpTextSeparator end
                return (g0.hpTextSeparator or "")
            end)
        end
        if powerSepDrop and textSepOptions then
            MSUF_SyncSimpleDropdown(powerSepDrop, textSepOptions, function()
                EnsureDB()
                local g0 = MSUF_DB.general
                local uKey = _MSUF_HPText_GetUnitKey()
                if uKey then
                    local u0 = _MSUF_HPText_GetUnitDB(uKey)
                    if u0 and u0.hpPowerTextOverride == true then
                        if u0.powerTextSeparator ~= nil then return u0.powerTextSeparator end
                        if u0.hpTextSeparator ~= nil then return u0.hpTextSeparator end
                    end
                end
                return (g0.powerTextSeparator ~= nil) and g0.powerTextSeparator or (g0.hpTextSeparator or "")
            end)
        end
        if type(_G.MSUF_Options_RefreshHPSpacerControls) == "function" then
            _G.MSUF_Options_RefreshHPSpacerControls()
        end
        -- Sync absorb dropdowns with current scope
        if absorbDisplayDrop and absorbDisplayOptions then
            MSUF_SyncSimpleDropdown(absorbDisplayDrop, absorbDisplayOptions, MSUF_GetAbsorbDisplayMode)
        end
        if absorbAnchorDrop and absorbAnchorOptions then
            MSUF_SyncSimpleDropdown(absorbAnchorDrop, absorbAnchorOptions, MSUF_GetAbsorbAnchorMode)
        end
        if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end

        -- ── Gray out global-only controls when a per-unit scope is active ──
        -- Per-unit controls (absorb display, absorb anchor, text modes, spacers) stay active.
        -- Everything else (textures, gradients, outline, highlight, power bar) is global-only.
        local isUnit = (unitKey ~= nil)
        local ena = not isUnit  -- true = enabled (Shared), false = disabled (unit scope)
        local dimAlpha = isUnit and 0.35 or 1
        -- Helper: dim/enable a dropdown by global name
        local function DimDrop(name, labelFS)
            MSUF_SetDropDownEnabled(_G[name], labelFS, ena)
        end
        -- Helper: dim/enable a checkbox by global name
        local function DimCheck(name)
            MSUF_SetCheckboxEnabled(_G[name], ena)
        end
        -- Helper: dim/enable a slider or generic frame
        local function DimSlider(name)
            MSUF_SetLabeledSliderEnabled(_G[name], ena)
        end
        local function DimFrame(name)
            local f = _G[name]
            if not f then return end
            if f.SetAlpha then f:SetAlpha(dimAlpha) end
            if ena then
                if f.Enable then pcall(f.Enable, f) end
            else
                if f.Disable then pcall(f.Disable, f) end
            end
            if f.EnableMouse then pcall(f.EnableMouse, f, ena) end
        end
        -- Helper: dim a section header / label fontstring
        local function DimLabel(fs)
            if not fs then return end
            if fs.SetTextColor then
                if ena then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.35, 0.35, 0.35) end
            elseif fs.SetAlpha then
                fs:SetAlpha(dimAlpha)
            end
        end

        -- ── Left panel: global-only sections ──
        -- Absorb textures (global)
        DimDrop("MSUF_AbsorbBarTextureDropdown", nil)
        DimDrop("MSUF_HealAbsorbBarTextureDropdown", nil)
        DimCheck("MSUF_AbsorbTextureTestModeCheck")
        DimCheck("MSUF_SelfHealPredictionCheck")
        DimLabel(absorbTextureLabel)
        -- Bar textures (global)
        DimDrop("MSUF_BarTextureDropdown", nil)
        DimDrop("MSUF_BarBackgroundTextureDropdown", nil)
        DimFrame("MSUF_BarTexturePreview")
        DimLabel(barTextureLabel)
        DimLabel(barBgTextureLabel)
        DimLabel(_G.MSUF_BarsMenuTexturesHeader)
        -- Gradient section (global)
        DimCheck("MSUF_GradientEnableCheck")
        DimCheck("MSUF_PowerGradientEnableCheck")
        DimSlider("MSUF_GradientStrengthSlider")
        DimFrame("MSUF_GradientDirectionPad")
        DimLabel(_G.MSUF_BarsMenuGradientHeader)
        -- Outline thickness (global)
        DimSlider("MSUF_BarOutlineThicknessSlider")
        -- Highlight border section (global)
        DimSlider("MSUF_HighlightBorderThicknessSlider")
        DimDrop("MSUF_AggroOutlineDropdown", nil)
        DimCheck("MSUF_AggroOutlineTestCheck")
        DimDrop("MSUF_DispelOutlineDropdown", nil)
        DimCheck("MSUF_DispelOutlineTestCheck")
        DimDrop("MSUF_PurgeOutlineDropdown", nil)
        DimCheck("MSUF_PurgeOutlineTestCheck")
        DimCheck("MSUF_HighlightPrioCheck")
        DimFrame("MSUF_HighlightPrioContainer")
        DimLabel(_G.MSUF_BarsMenuHighlightHeader)
        -- Left panel section divider lines + headers stored on panel
        local lp = _G["MSUF_BarsMenuPanelLeft"]
        if lp then
            if lp.MSUF_SectionLine_Textures then lp.MSUF_SectionLine_Textures:SetAlpha(dimAlpha) end
            if lp.MSUF_SectionLine_Gradient then lp.MSUF_SectionLine_Gradient:SetAlpha(dimAlpha) end
            if lp.MSUF_SectionLine_Highlight then lp.MSUF_SectionLine_Highlight:SetAlpha(dimAlpha) end
            if lp.MSUF_SectionHeader_Outline then DimLabel(lp.MSUF_SectionHeader_Outline) end
            if lp.MSUF_SectionLine_Outline then lp.MSUF_SectionLine_Outline:SetAlpha(dimAlpha) end
        end

        -- ── Right panel: global-only sections ──
        -- Power bar settings (global)
        DimCheck("MSUF_TargetPowerBarCheck")
        DimCheck("MSUF_BossPowerBarCheck")
        DimCheck("MSUF_PlayerPowerBarCheck")
        DimCheck("MSUF_FocusPowerBarCheck")
        DimFrame("MSUF_PowerBarHeightEdit")
        DimCheck("MSUF_PowerBarEmbedCheck")
        DimCheck("MSUF_PowerBarBorderCheck")
        DimFrame("MSUF_PowerBarBorderSizeEdit")
        DimLabel(powerBarHeightLabel)
        DimLabel(powerBarBorderSizeLabel)
        DimLabel(_G.MSUF_BarsMenuRightHeader)
    end

    MSUF_InitSimpleDropdown(
        hpPowerScopeDrop,
        hpPowerScopeOptions,
        _MSUF_HPText_GetScopeKey,
        function(v)
            EnsureDB()
            local g = MSUF_DB.general
            local k = _MSUF_HPText_NormalizeScopeKey(v)
            g.hpPowerTextSelectedKey = k
            if k ~= "shared" then
                g.hpSpacerSelectedUnitKey = k
            end
        end,
        function() _MSUF_SyncHpPowerTextScopeUI() end,
        BAR_DROPDOWN_WIDTH
    )

    hpPowerOverrideCheck:SetScript('OnClick', function(self)
        EnsureDB()
        local unitKey = _MSUF_HPText_GetUnitKey()
        if not unitKey then
            self:SetChecked(false)
            return
        end
        local u = _MSUF_HPText_GetUnitDB(unitKey)
        if not u then
            self:SetChecked(false)
            return
        end
        if self:GetChecked() then
            _MSUF_HPText_EnableOverride(unitKey)
        else
            u.hpPowerTextOverride = false
        end
        ApplyAllSettings()
        if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
            _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
        end
        -- Re-apply absorb settings for affected frames
        if _G.MSUF_UnitFrames then
            for _, frame in pairs(_G.MSUF_UnitFrames) do
                if frame and frame.unit then
                    if type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
                        _G.MSUF_ApplyAbsorbAnchorMode(frame)
                    end
                    if UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(frame) end
                end
            end
        end
        _MSUF_SyncHpPowerTextScopeUI()
    end)

    -- "Reset all overrides" button — only visible when Shared scope is selected.
    local hpPowerResetBtn = CreateFrame("Button", "MSUF_HPTextResetOverridesBtn", barGroup, "UIPanelButtonTemplate")
    hpPowerResetBtn:SetSize(140, 22)
    hpPowerResetBtn:SetPoint("TOPLEFT", hpPowerOverrideCheck, "TOPLEFT", 0, 2)
    hpPowerResetBtn:SetText(TR("Reset all overrides"))
    hpPowerResetBtn:SetNormalFontObject("GameFontNormalSmall")
    hpPowerResetBtn:SetHighlightFontObject("GameFontHighlightSmall")
    hpPowerResetBtn:Hide()
    hpPowerResetBtn:SetScript("OnClick", function()
        EnsureDB()
        local unitKeys = { "player", "target", "focus", "targettarget", "pet", "boss" }
        local anyReset = false
        for _, uKey in ipairs(unitKeys) do
            local u = MSUF_DB[uKey]
            if u and u.hpPowerTextOverride then
                u.hpPowerTextOverride = false
                anyReset = true
            end
        end
        if anyReset then
            ApplyAllSettings()
            -- Re-apply absorb + text layout for all frames
            if _G.MSUF_UnitFrames then
                for _, frame in pairs(_G.MSUF_UnitFrames) do
                    if frame and frame.unit then
                        if type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
                            _G.MSUF_ApplyAbsorbAnchorMode(frame)
                        end
                        if UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(frame) end
                    end
                end
            end
            for _, uKey in ipairs(unitKeys) do
                if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                    _G.MSUF_ForceTextLayoutForUnitKey(uKey)
                end
            end
        end
        _MSUF_SyncHpPowerTextScopeUI()
    end)
    hpPowerResetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset all overrides")
        GameTooltip:AddLine("Clears per-unit overrides for all units (Player, Target, Focus, etc.) so they all use the shared settings again.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    hpPowerResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Wire up scope sync so absorb apply callbacks can trigger a full refresh.
    _MSUF_BarScope_SyncUI = _MSUF_SyncHpPowerTextScopeUI

    -- Initial sync.
    _MSUF_SyncHpPowerTextScopeUI()
-- HP % Spacer (split FULL value + % into two text anchors)
    -- Per-unit settings are stored on MSUF_DB[unitKey].hpTextSpacerEnabled / hpTextSpacerX.
    -- The Bars menu shows the settings for the *last clicked* MSUF unitframe (stored as a UI selection
    -- in MSUF_DB.general.hpSpacerSelectedUnitKey).
-- Selected unitframe indicator + info icon (selection is done by clicking the unitframe itself).
hpSpacerSelectedLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hpSpacerSelectedLabel:ClearAllPoints()
hpSpacerSelectedLabel:SetPoint("TOPLEFT", hpSepDrop, "BOTTOMLEFT", 16, -8)
hpSpacerSelectedLabel:SetTextColor(1, 0.82, 0, 1)
hpSpacerSelectedLabel:SetText(TR("Selected: Shared"))
hpSpacerInfoButton = CreateFrame("Button", "MSUF_HPSpacerInfoButton", barGroup)
hpSpacerInfoButton:SetSize(14, 14)
hpSpacerInfoButton:ClearAllPoints()
hpSpacerInfoButton:SetPoint("LEFT", hpSpacerSelectedLabel, "RIGHT", 4, 0)
do
    local t = hpSpacerInfoButton:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(hpSpacerInfoButton)
    t:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    hpSpacerInfoButton._msufTex = t
end
hpSpacerInfoButton:SetScript("OnEnter", function(self)
   if not GameTooltip then  return end
   GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
   GameTooltip:AddLine("Text Spacers", 1, 1, 1)
   GameTooltip:AddLine("Use the Bar settings scope dropdown (left panel, bottom) to choose which unit these settings apply to.", 0.9, 0.9, 0.9, true)
	   GameTooltip:AddLine("When scope is set to 'Shared', settings apply globally. Select a unit and enable 'Override shared settings' to customize per unitframe.", 0.9, 0.9, 0.9, true)
   GameTooltip:AddLine("Works only when the corresponding text mode is set to 'Full value + %' (or '% + Full value').", 0.9, 0.9, 0.9, true)
   GameTooltip:Show()
end)
hpSpacerInfoButton:SetScript("OnLeave", function()  if GameTooltip then GameTooltip:Hide() end  end)
-- HP spacer controls
hpSpacerCheck = CreateFrame("CheckButton", "MSUF_HPTextSpacerCheck", barGroup, "UICheckButtonTemplate")
hpSpacerCheck:ClearAllPoints()
hpSpacerCheck:SetPoint("TOPLEFT", hpSpacerSelectedLabel, "BOTTOMLEFT", 0, -4)
hpSpacerCheck.text = _G["MSUF_HPTextSpacerCheckText"]
if hpSpacerCheck.text then hpSpacerCheck.text:SetText(TR("HP Spacer on/off")) end
MSUF_StyleToggleText(hpSpacerCheck)
MSUF_StyleCheckmark(hpSpacerCheck)
hpSpacerSlider = CreateLabeledSlider("MSUF_HPTextSpacerSlider", "HP Spacer (X)", barGroup, 0, 1000, 1, 16, -200)
hpSpacerSlider:ClearAllPoints()
hpSpacerSlider:SetPoint("TOPLEFT", hpSpacerCheck, "BOTTOMLEFT", 0, -18)
if hpSpacerSlider.SetWidth then hpSpacerSlider:SetWidth(260) end
-- Power spacer controls
local powerSpacerHeader = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
powerSpacerHeader:SetPoint("TOPLEFT", hpSpacerSlider, "BOTTOMLEFT", 0, -18)
powerSpacerHeader:SetText(TR(""))
local powerSpacerCheck = CreateFrame("CheckButton", "MSUF_PowerTextSpacerCheck", barGroup, "UICheckButtonTemplate")
powerSpacerCheck:ClearAllPoints()
powerSpacerCheck:SetPoint("TOPLEFT", powerSpacerHeader, "BOTTOMLEFT", 0, -4)
powerSpacerCheck.text = _G["MSUF_PowerTextSpacerCheckText"]
if powerSpacerCheck.text then powerSpacerCheck.text:SetText(TR("Power Spacer on/off")) end
MSUF_StyleToggleText(powerSpacerCheck)
MSUF_StyleCheckmark(powerSpacerCheck)
local powerSpacerSlider = CreateLabeledSlider("MSUF_PowerTextSpacerSlider", "Power Spacer (X)", barGroup, 0, 1000, 1, 16, -200)
powerSpacerSlider:ClearAllPoints()
powerSpacerSlider:SetPoint("TOPLEFT", powerSpacerCheck, "BOTTOMLEFT", 0, -18)
if powerSpacerSlider.SetWidth then powerSpacerSlider:SetWidth(260) end

-- ── Bar Animation + Text Accuracy ──────────────────────────────────
-- Two independent toggles so users can pick:
--   Both ON  = MidnightRogueBars style (hyper-smooth, pixel-accurate)
--   Both OFF = Classic MSUF style (instant snap, battery-friendly)
--   Mixed    = Custom blend
local animHeader = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
animHeader:SetPoint("TOPLEFT", powerSpacerSlider, "BOTTOMLEFT", 0, -38)
animHeader:SetText(TR("Bar Animation + Text Accuracy"))
animHeader:SetTextColor(1, 0.82, 0, 1)
_G.MSUF_SmoothPowerHeader = animHeader

local animLine = barGroup:CreateTexture(nil, "ARTWORK")
animLine:SetColorTexture(1, 1, 1, 0.20)
animLine:SetHeight(1)
animLine:SetPoint("TOPLEFT", animHeader, "BOTTOMLEFT", -16, -4)
animLine:SetWidth(286)

-- ─ Toggle 1: Smooth power bar (ExponentialEaseOut interpolation) ─
local smoothBarCheck = CreateFrame("CheckButton", "MSUF_SmoothPowerBarCheck", barGroup, "UICheckButtonTemplate")
smoothBarCheck:ClearAllPoints()
smoothBarCheck:SetPoint("TOPLEFT", animLine, "BOTTOMLEFT", 16, -6)
smoothBarCheck.text = _G["MSUF_SmoothPowerBarCheckText"]
if smoothBarCheck.text then smoothBarCheck.text:SetText(TR("Smooth power bar")) end
MSUF_StyleToggleText(smoothBarCheck)
MSUF_StyleCheckmark(smoothBarCheck)
local smoothBarHint = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
smoothBarHint:SetPoint("TOPLEFT", smoothBarCheck, "BOTTOMLEFT", 0, -1)
smoothBarHint:SetText(TR("C-side interpolation for fluid bar movement"))
smoothBarHint:SetTextColor(0.45, 0.45, 0.45)
smoothBarCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Smooth Power Bar", 1, 1, 1)
    GameTooltip:AddLine("Uses ExponentialEaseOut interpolation on the", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("StatusBar for silky-smooth bar animation.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("When OFF: Bar snaps instantly to new values.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
smoothBarCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
do
    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    local val = MSUF_DB.bars.smoothPowerBar
    if val == nil then val = true end
    smoothBarCheck:SetChecked(val)
end
smoothBarCheck:SetScript("OnClick", function(self)
    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.smoothPowerBar = self:GetChecked() and true or false
    if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then
        _G.MSUF_UFCore_RefreshSettingsCache("SMOOTH_POWER")
    end
end)

-- ─ Toggle 2: Real-time power text (every event, no throttle) ─
local rtTextCheck = CreateFrame("CheckButton", "MSUF_RealtimePowerTextCheck", barGroup, "UICheckButtonTemplate")
rtTextCheck:ClearAllPoints()
rtTextCheck:SetPoint("TOPLEFT", smoothBarHint, "BOTTOMLEFT", 0, -6)
rtTextCheck.text = _G["MSUF_RealtimePowerTextCheckText"]
if rtTextCheck.text then rtTextCheck.text:SetText(TR("Real-time power text")) end
MSUF_StyleToggleText(rtTextCheck)
MSUF_StyleCheckmark(rtTextCheck)
local rtTextHint = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
rtTextHint:SetPoint("TOPLEFT", rtTextCheck, "BOTTOMLEFT", 0, -1)
rtTextHint:SetText(TR("Update text every event (higher CPU, pixel-accurate)"))
rtTextHint:SetTextColor(0.45, 0.45, 0.45)
rtTextCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Real-time Power Text", 1, 1, 1)
    GameTooltip:AddLine("Updates the power number on every game event", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("for pixel-accurate text that matches the bar.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("When OFF: Text updates are budget-gated", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("(player 33Hz, others 10Hz) for lower CPU.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
rtTextCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
do
    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    local val = MSUF_DB.bars.realtimePowerText
    if val == nil then val = true end
    rtTextCheck:SetChecked(val)
end
rtTextCheck:SetScript("OnClick", function(self)
    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.realtimePowerText = self:GetChecked() and true or false
    if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then
        _G.MSUF_UFCore_RefreshSettingsCache("REALTIME_TEXT")
    end
end)
-- ── End Bar Animation + Text Accuracy ──────────────────────────────

	local function _MSUF_HPSpacer_GetSelection()
	    -- Selection is driven by the HP/Power scope dropdown above.
	    EnsureDB()
	    MSUF_DB.general = MSUF_DB.general or {}
	    local g = MSUF_DB.general
	    local scope = (type(_MSUF_HPText_GetScopeKey) == "function") and _MSUF_HPText_GetScopeKey() or nil
	    if type(_MSUF_HPText_NormalizeScopeKey) == "function" then
	        scope = _MSUF_HPText_NormalizeScopeKey(scope)
	    end
	    if scope == "shared" then
	        return nil, true
	    end
	    local k = scope
	    if type(_G.MSUF_NormalizeTextLayoutUnitKey) == "function" then
	        k = _G.MSUF_NormalizeTextLayoutUnitKey(k, "player")
	    end
	    if not k or k == "shared" then k = "player" end
	    g.hpSpacerSelectedUnitKey = k
	    return k, false
	end
	local function _MSUF_HPSpacer_GetDB()
	    local unitKey, isShared = _MSUF_HPSpacer_GetSelection()
	    EnsureDB()
	    MSUF_DB.general = MSUF_DB.general or {}
	    if isShared then
	        return nil, MSUF_DB.general, true
	    end
	    MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
	    return unitKey, MSUF_DB[unitKey], false
	end
local function _MSUF_TextModeAllowsSpacer(mode)
  return (mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" or mode == "CURPERCENT" or mode == "CURMAXPERCENT")
    end
    local SPACER_SPECS = {
        {
            id = "hp",
            check = hpSpacerCheck,
            slider = hpSpacerSlider,
            modeKey = "hpTextMode",
            enabledKey = "hpTextSpacerEnabled",
            xKey = "hpTextSpacerX",
            maxFuncName = "MSUF_GetHPSpacerMaxForUnitKey",
            maxDefault = 1000,
            maxCap = 2000,
            reqToggle = "HP_SPACER_TOGGLE",
            reqX = "HP_SPACER_X",
            dimText = true, -- dim label text when mode doesn't allow spacer
        },
        {
            id = "power",
            check = powerSpacerCheck,
            slider = powerSpacerSlider,
            modeKey = "powerTextMode",
            enabledKey = "powerTextSpacerEnabled",
            xKey = "powerTextSpacerX",
            maxFuncName = "MSUF_GetPowerSpacerMaxForUnitKey",
            maxDefault = 1000,
            maxCap = 1000,
            reqToggle = "POWER_SPACER_TOGGLE",
            reqX = "POWER_SPACER_X",
        },
    }
    local function _MSUF_NiceUnitKey(unitKey)
        if unitKey == "player" then  return "Player"
        elseif unitKey == "target" then  return "Target"
        elseif unitKey == "focus" then  return "Focus"
        elseif unitKey == "targettarget" then  return "ToT"
        elseif unitKey == "pet" then  return "Pet"
        elseif unitKey == "boss" then  return "Boss"
        end
        return tostring(unitKey or "Player")
    end
    local function _MSUF_GetSpacerMax(spec, unitKey)
        local mv = spec.maxDefault or 1000
        local fn = spec.maxFuncName and _G and _G[spec.maxFuncName]
        if type(fn) == "function" then
            local ok, out = pcall(fn, unitKey)
            if ok and type(out) == "number" and out > 0 then mv = out end
        end
        mv = math.floor((tonumber(mv) or 0) + 0.5)
        if mv < 0 then mv = 0 end
        if spec.maxCap and mv > spec.maxCap then mv = spec.maxCap end
         return mv
    end
	local function _MSUF_GetEffectiveSpacerMode(unitKey, spec, g0)
	    if not spec or not spec.modeKey then  return "FULL_PLUS_PERCENT" end
	    -- Shared selection uses Shared mode directly.
	    if not unitKey then
	        return (g0 and g0[spec.modeKey]) or "FULL_PLUS_PERCENT"
	    end
	    local u0 = (MSUF_DB and MSUF_DB[unitKey]) or nil
	    local useOverride = (u0 and u0.hpPowerTextOverride == true)
	    local m = (useOverride and u0 and u0[spec.modeKey]) or (g0 and g0[spec.modeKey]) or "FULL_PLUS_PERCENT"
	    return m
	end

local function _MSUF_SyncSpacerControls()
    EnsureDB()
	    local g0 = MSUF_DB.general or {}
	    -- Seed Shared spacer defaults from Player (user expectation: Shared starts "like Player").
	    do
	        local p = MSUF_DB and MSUF_DB.player
	        if p then
	            if g0.hpTextSpacerEnabled == nil and p.hpTextSpacerEnabled ~= nil then g0.hpTextSpacerEnabled = p.hpTextSpacerEnabled end
	            if g0.hpTextSpacerX == nil and p.hpTextSpacerX ~= nil then g0.hpTextSpacerX = p.hpTextSpacerX end
	            if g0.powerTextSpacerEnabled == nil and p.powerTextSpacerEnabled ~= nil then g0.powerTextSpacerEnabled = p.powerTextSpacerEnabled end
	            if g0.powerTextSpacerX == nil and p.powerTextSpacerX ~= nil then g0.powerTextSpacerX = p.powerTextSpacerX end
	        end
	    end
	    local unitKey, u, isShared = _MSUF_HPSpacer_GetDB()
	    local unitOverride = (not isShared) and (u and u.hpPowerTextOverride == true)

	    if hpSpacerSelectedLabel and hpSpacerSelectedLabel.SetText then
	        local nice = (isShared and "Shared") or _MSUF_NiceUnitKey(unitKey)
	        hpSpacerSelectedLabel:SetText("Selected: " .. nice)
	    end

    for _, spec in ipairs(SPACER_SPECS) do
        local cb = spec.check
        local sl = spec.slider

	        local canEdit = isShared or unitOverride
	        -- If unit override is OFF, show effective (Shared) values but keep controls disabled.
	        local src = (isShared and g0) or (unitOverride and u or g0)
	        local enabled = (src and src[spec.enabledKey] == true) or false
	        local mode = _MSUF_GetEffectiveSpacerMode(unitKey, spec, g0)
	        local modeAllows = _MSUF_TextModeAllowsSpacer(mode)

	        if cb and cb.SetChecked then cb:SetChecked(enabled) end
	        if cb and cb.SetEnabled then cb:SetEnabled(canEdit and modeAllows) end
	        if cb and cb.SetAlpha then cb:SetAlpha((canEdit and modeAllows) and 1 or 0.45) end

        -- Optional: dim HP spacer toggle label when disabled by mode (requested UX).
	        if spec.dimText and cb and cb.text and cb.text.SetTextColor then
	            local c = (modeAllows and (canEdit and 1 or 0.75)) or 0.5
	            cb.text:SetTextColor(c, c, c, 1)
	        end

	        -- Shared slider range is based on Player (requested). Unit scope uses its own unit.
	        local maxKey = isShared and "player" or unitKey
	        local maxV = _MSUF_GetSpacerMax(spec, maxKey)

        if sl and sl.SetMinMaxValues then
            sl:SetMinMaxValues(0, maxV)
            sl.minVal = 0
            sl.maxVal = maxV

            local n = (sl.GetName and sl:GetName())
            if n and _G then
                local high = _G[n .. "High"]
                local low  = _G[n .. "Low"]
                if high and high.SetText then high:SetText(tostring(maxV)) end
                if low  and low.SetText  then low:SetText(TR("0")) end
            end

	            local v = tonumber(src and src[spec.xKey]) or 0
	            if v < 0 then v = 0 end
	            if v > maxV then v = maxV end
	            -- Only write back when the scope is editable; never clamp Shared based on a smaller unit.
	            if canEdit then
	                if isShared then
	                    g0[spec.xKey] = v
	                elseif u then
	                    u[spec.xKey] = v
	                end
	            end

            if type(MSUF_SetLabeledSliderValue) == "function" then
                MSUF_SetLabeledSliderValue(sl, v)
            else
                sl.MSUF_SkipCallback = true
                sl:SetValue(v)
                sl.MSUF_SkipCallback = nil
            end

	            local slEnabled = (canEdit and modeAllows and enabled)
            if type(MSUF_SetLabeledSliderEnabled) == "function" then
                MSUF_SetLabeledSliderEnabled(sl, slEnabled)
                if (not slEnabled) and sl.SetAlpha then sl:SetAlpha(0.45) end -- keep old visual
            else
                if sl.SetEnabled then sl:SetEnabled(slEnabled) end
                if sl.SetAlpha then sl:SetAlpha(slEnabled and 1 or 0.45) end
            end
        end
    end
 end

	local _MSUF_TEXT_LAYOUT_KEYS = { "player", "target", "focus", "targettarget", "pet", "boss" }
	local function _MSUF_RequestTextLayoutForScope(unitKey, isShared, reason)
	    if isShared then
	        for _, k in ipairs(_MSUF_TEXT_LAYOUT_KEYS) do
	            if type(MSUF_Options_RequestLayoutForKey) == "function" then
	                MSUF_Options_RequestLayoutForKey(k, reason)
	            end
	            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
	                _G.MSUF_ForceTextLayoutForUnitKey(k)
	            end
	        end
	        return
	    end
	    if type(MSUF_Options_RequestLayoutForKey) == "function" then
	        MSUF_Options_RequestLayoutForKey(unitKey, reason)
	    end
	    if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
	        _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
	    end
	end

local function _MSUF_BindSpacerToggle(spec)
        if not spec or not spec.check then  return end
        spec.check:SetScript("OnClick", function(self)
            EnsureDB()
	            local unitKey, db, isShared = _MSUF_HPSpacer_GetDB()
	            local g = MSUF_DB.general or {}
	            local canEdit = isShared or (db and db.hpPowerTextOverride == true)
	            if not canEdit then
	                _MSUF_SyncSpacerControls()
	                return
	            end
	            local mode = _MSUF_GetEffectiveSpacerMode(unitKey, spec, g)
	            if not _MSUF_TextModeAllowsSpacer(mode) then
	                _MSUF_SyncSpacerControls()
	                return
	            end
	            local targetDB = isShared and g or db
	            targetDB[spec.enabledKey] = self:GetChecked() and true or false
	            _MSUF_SyncSpacerControls()
	            _MSUF_RequestTextLayoutForScope(unitKey, isShared, spec.reqToggle)
         end)
     end
    local function _MSUF_BindSpacerSlider(spec)
        if not spec or not spec.slider then  return end
        spec.slider.onValueChanged = function(self, value)
            EnsureDB()
	            local unitKey, db, isShared = _MSUF_HPSpacer_GetDB()
	            local g = MSUF_DB.general or {}
	            local canEdit = isShared or (db and db.hpPowerTextOverride == true)
	            if not canEdit then
	                _MSUF_SyncSpacerControls()
	                return
	            end
	            local mode = _MSUF_GetEffectiveSpacerMode(unitKey, spec, g)
	            if not _MSUF_TextModeAllowsSpacer(mode) then
	                _MSUF_SyncSpacerControls()
	                return
	            end
	            local maxKey = isShared and "player" or unitKey
	            local maxV = _MSUF_GetSpacerMax(spec, maxKey)
	            local v = tonumber(value) or 0
	            if v < 0 then v = 0 end
	            if v > maxV then v = maxV end
	            local targetDB = isShared and g or db
	            targetDB[spec.xKey] = v
            -- If clamped, snap slider back (without triggering callbacks).
            if v ~= value and type(MSUF_SetLabeledSliderValue) == "function" then
                MSUF_SetLabeledSliderValue(self, v)
            end
	            _MSUF_RequestTextLayoutForScope(unitKey, isShared, spec.reqX)
         end
     end
    for _, spec in ipairs(SPACER_SPECS) do
        _MSUF_BindSpacerToggle(spec)
        _MSUF_BindSpacerSlider(spec)
    end
    _MSUF_SyncSpacerControls()
    -- Let other code refresh this UI when selection/scope changes.
    _G.MSUF_Options_RefreshHPSpacerControls = _MSUF_SyncSpacerControls

local barTextureDrop
        local barBgTextureDrop
        -- Shared helper used by both bar texture dropdowns (foreground + background)
        local function MSUF_TryApplyBarTextureLive()
            if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
            if type(_G.MSUF_UpdateAllBarTextures_Immediate) == "function" then
                _G.MSUF_UpdateAllBarTextures_Immediate()
            elseif type(_G.MSUF_UpdateAllBarTextures) == "function" then
                _G.MSUF_UpdateAllBarTextures()
            elseif type(_G.UpdateAllBarTextures) == "function" then
                _G.UpdateAllBarTextures()
            elseif type(_G.MSUF_UpdateAllUnitFrames) == "function" then
                _G.MSUF_UpdateAllUnitFrames()
            elseif type(_G.MSUF_RefreshAllUnitFrames) == "function" then
                _G.MSUF_RefreshAllUnitFrames()
            end
         end
        _G.MSUF_TryApplyBarTextureLive = MSUF_TryApplyBarTextureLive
        do
            barTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            barTextureLabel:SetPoint("TOPLEFT", (absorbTexTestCB or healAbsorbTextureDrop or absorbBarTextureDrop or absorbAnchorDrop or absorbDisplayDrop), "BOTTOMLEFT", 16, -18)
            barTextureLabel:SetText(TR("Bar texture (SharedMedia)"))
            barTextureDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_BarTextureDropdown", barGroup) or CreateFrame("Frame", "MSUF_BarTextureDropdown", barGroup, "UIDropDownMenuTemplate"))
            MSUF_ExpandDropdownClickArea(barTextureDrop)
            barTextureDrop:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -4)
            UIDropDownMenu_SetWidth(barTextureDrop, BAR_DROPDOWN_WIDTH)
			-- If LibSharedMedia is unavailable, we still allow choosing built-in Blizzard textures.
            barTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
            barTextureDrop._msufTweakBarTexturePreview = true
            MSUF_MakeDropdownScrollable(barTextureDrop, 12)
            local barTexturePreview = _G.MSUF_BarTexturePreview
            if not barTexturePreview then barTexturePreview = CreateFrame("StatusBar", "MSUF_BarTexturePreview", barGroup) end
            barTexturePreview:SetParent(barGroup)
            barTexturePreview:SetSize(BAR_DROPDOWN_WIDTH, 10)
            barTexturePreview:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 20, -6)
            barTexturePreview:SetMinMaxValues(0, 1)
            barTexturePreview:SetValue(1)
            barTexturePreview:Hide()
            MSUF_KillMenuPreviewBar(barTexturePreview)
            barTextureInfo = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            barTextureInfo:SetPoint("TOPLEFT", barTexturePreview, "BOTTOMLEFT", 0, -6)
            barTextureInfo:SetText('Install "SharedMedia" (LibSharedMedia-3.0) to unlock more bar textures. Without it, you can still pick Blizzard built-in textures.')
            local function BarTexturePreview_Update(texName)
                -- Prefer the global resolver (covers both built-ins and SharedMedia keys).
                if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
                    local resolved = _G.MSUF_ResolveStatusbarTextureKey(texName)
                    if resolved then
                        barTexturePreview:SetStatusBarTexture(resolved)
                         return
                    end
                end
                local LSM = MSUF_GetLSM()
                if LSM and type(LSM.Fetch) == "function" then
                    local tex = LSM:Fetch("statusbar", texName, true)
                    if tex then
                        barTexturePreview:SetStatusBarTexture(tex)
                         return
                    end
                end
                -- Hard fallback
                barTexturePreview:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
             end
            _MSUF_InitStatusbarTextureDropdown(barTextureDrop, {
                get = function()
                    EnsureDB()
                    return (MSUF_DB.general and MSUF_DB.general.barTexture) or "Blizzard"
                end,
                set = function(value)
                    EnsureDB()
                    MSUF_DB.general = MSUF_DB.general or {}
                    MSUF_DB.general.barTexture = value
                    BarTexturePreview_Update(value)
                    MSUF_TryApplyBarTextureLive()
                 end,
            })
            EnsureDB()
            BarTexturePreview_Update((MSUF_DB.general and MSUF_DB.general.barTexture) or "Blizzard")
            if MSUF_GetLSM() then
                barTextureInfo:Hide()
            else
                barTextureInfo:Show()
            end
        end
        do -- Bar background texture dropdown
            barBgTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            barBgTextureLabel:SetPoint("TOPLEFT", _G.MSUF_BarTexturePreview, "BOTTOMLEFT", -20, -40)
            barBgTextureLabel:SetText(TR("Bar background texture"))
            barBgTextureDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_BarBackgroundTextureDropdown", barGroup) or CreateFrame("Frame", "MSUF_BarBackgroundTextureDropdown", barGroup, "UIDropDownMenuTemplate"))
            MSUF_ExpandDropdownClickArea(barBgTextureDrop)
            barBgTextureDrop:SetPoint("TOPLEFT", barBgTextureLabel, "BOTTOMLEFT", -16, -4)
            UIDropDownMenu_SetWidth(barBgTextureDrop, BAR_DROPDOWN_WIDTH)
			-- If LibSharedMedia is unavailable, we still allow choosing built-in Blizzard textures.
            barBgTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
            barBgTextureDrop._msufTweakBarTexturePreview = true
            MSUF_MakeDropdownScrollable(barBgTextureDrop, 12)
            _MSUF_InitStatusbarTextureDropdown(barBgTextureDrop, {
                get = function()
                    EnsureDB()
                    local g = (MSUF_DB and MSUF_DB.general) or {}
                    return g.barBackgroundTexture
                end,
                followText = "Use foreground texture",
                followValue = "",
                isFollow = function(cur)  return (cur == nil or cur == "") end,
                setFollow = function()
                    EnsureDB()
                    MSUF_DB.general = MSUF_DB.general or {}
                    MSUF_DB.general.barBackgroundTexture = ""
                    MSUF_TryApplyBarTextureLive()
                 end,
                set = function(value)
                    EnsureDB()
                    MSUF_DB.general = MSUF_DB.general or {}
                    MSUF_DB.general.barBackgroundTexture = value
                    MSUF_TryApplyBarTextureLive()
                 end,
            })
            EnsureDB()
        end
-- Unitframe bar outline (replaces legacy border toggle + border style dropdown)
-- 0 = disabled, 1..6 = thickness in pixels (expands OUTSIDE the HP bar like castbar outline)
barOutlineThicknessSlider = CreateLabeledSlider(
    "MSUF_BarOutlineThicknessSlider",
    "Outline thickness",
    barGroup,
    0, 6, 1,
    16, -350
)
-- Initialize the numeric box to the saved value immediately (otherwise it stays empty until changed).
do
    EnsureDB()
    local bars = (MSUF_DB and MSUF_DB.bars) or {}
    local t = tonumber(bars.barOutlineThickness)
    if type(t) ~= "number" then t = 1 end
    t = math.floor(t + 0.5)
    if t < 0 then t = 0 elseif t > 6 then t = 6 end
    MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t)
end

-- Live-apply outline thickness while the Settings panel is open (cold path).
-- Once set, runtime uses the cached value and doesn't reapply constantly.
barOutlineThicknessSlider.onValueChanged = function(_, value)
    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.barOutlineThickness = value
    if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then
        _G.MSUF_ApplyBarOutlineThickness_All()
    else
        ApplyAllSettings()
    end
end

-- Highlight border thickness (separate overlay for aggro/dispel/purge)
local highlightBorderThicknessSlider = CreateLabeledSlider(
    "MSUF_HighlightBorderThicknessSlider",
    "Highlight border thickness",
    barGroup,
    1, 6, 1,
    16, -420
)
do
    local txt = _G["MSUF_HighlightBorderThicknessSliderText"]
    if txt and txt.SetFontObject then txt:SetFontObject("GameFontHighlightSmall") end
end
do
    EnsureDB()
    local gen = (MSUF_DB and MSUF_DB.general) or {}
    local t = tonumber(gen.highlightBorderThickness)
    if type(t) ~= "number" then t = 2 end
    t = math.floor(t + 0.5)
    if t < 1 then t = 1 elseif t > 6 then t = 6 end
    MSUF_SetLabeledSliderValue(highlightBorderThicknessSlider, t)
end

highlightBorderThicknessSlider.onValueChanged = function(_, value)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.highlightBorderThickness = value
    if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then
        _G.MSUF_ApplyBarOutlineThickness_All()
    else
        ApplyAllSettings()
    end
end


-- Aggro border indicator: reuse outline border as a thick orange threat border (target/focus/boss).
-- No extra header label; the dropdown itself is the control.
local aggroOutlineDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_AggroOutlineDropdown", barGroup) or CreateFrame("Frame", "MSUF_AggroOutlineDropdown", barGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(aggroOutlineDrop)

-- The UIDropDownMenuTemplate has extra left padding; keep the control comfortably inside the left panel.
-- Also keep enough room for the "Test" checkbox to the right (avoid clipping into the right column).
-- Move the dropdown slightly lower to avoid clipping against the slider section.
aggroOutlineDrop:SetPoint("TOPLEFT", barOutlineThicknessSlider, "BOTTOMLEFT", 6, -34)
UIDropDownMenu_SetWidth(aggroOutlineDrop, 170)
	-- Match Dispel dropdown text alignment (true left-justify)
	if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(aggroOutlineDrop, "LEFT") end
	-- Prevent the list from being cut off near the bottom edge of the Settings scroll area.
	if UIDropDownMenu_SetClampedToScreen then UIDropDownMenu_SetClampedToScreen(aggroOutlineDrop, true) end
MSUF_MakeDropdownScrollable(aggroOutlineDrop, 10)

local function _AggroOutline_Set(val)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.aggroOutlineMode = val
    if type(_G.MSUF_AggroOutline_ApplyEventRegistration) == "function" then
        _G.MSUF_AggroOutline_ApplyEventRegistration()
    end
    -- Refresh outlines immediately (cheap).
    local fn = _G and _G.MSUF_RefreshRareBarVisuals
    local frames = _G and _G.MSUF_UnitFrames
    if type(fn) == "function" and frames then
        local t = frames.target
        if t and t.unit == "target" then fn(t) end
        local f = frames.focus
        if f and f.unit == "focus" then fn(f) end
        for i = 1, 5 do
            local b = frames["boss" .. i]
            if b and b.unit == ("boss" .. i) then fn(b) end
        end
    end
end

	-- Use the shared helper so selected text updates correctly (avoids "visual-only" desync).
	local _AggroOutline_Options = {
	    { key = 0, label = TR("Aggro border off") },
	    { key = 1, label = TR("Aggro border on") },
	}
	local function _AggroOutline_Get()
	    EnsureDB()
	    local g = (MSUF_DB and MSUF_DB.general) or {}
	    return g.aggroOutlineMode or 0
	end
	MSUF_InitSimpleDropdown(
	    aggroOutlineDrop,
	    _AggroOutline_Options,
	    _AggroOutline_Get,
	    function(v) _AggroOutline_Set(v) end,
	    function() _AggroOutline_Set(_AggroOutline_Get()) end,
	    170
	)
	-- Keep for LoadFromDB sync.
	aggroOutlineDrop._msufAggroOutlineOptions = _AggroOutline_Options
	aggroOutlineDrop._msufAggroOutlineGet = _AggroOutline_Get

-- Options-only: Test mode to force the aggro border on while this menu is open.
local aggroTestCheck = CreateFrame("CheckButton", "MSUF_AggroOutlineTestCheck", barGroup, "ChatConfigCheckButtonTemplate")
-- Keep the toggle visually attached but within the panel width.
-- Nudge the checkbox down to align visually with the dropdown and avoid edge clipping.
aggroTestCheck:SetPoint("LEFT", aggroOutlineDrop, "RIGHT", 6, -4)
aggroTestCheck.Text:SetText(TR("Test"))
aggroTestCheck.tooltipText = TR("Aggro border: Target, Focus, Boss frames")
aggroTestCheck:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
aggroTestCheck:HookScript("OnLeave", function() GameTooltip:Hide() end)
aggroTestCheck:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if type(_G.MSUF_SetAggroBorderTestMode) == "function" then
        _G.MSUF_SetAggroBorderTestMode(on)
    end
end)



-- Dispel border: light-blue outline border when the player can dispel something on the unit (RAID_PLAYER_DISPELLABLE).
local dispelOutlineDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_DispelOutlineDropdown", barGroup) or CreateFrame("Frame", "MSUF_DispelOutlineDropdown", barGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(dispelOutlineDrop)
dispelOutlineDrop:SetPoint("TOPLEFT", aggroOutlineDrop, "BOTTOMLEFT", 0, -18)
UIDropDownMenu_SetWidth(dispelOutlineDrop, 170)
if UIDropDownMenu_SetClampedToScreen then UIDropDownMenu_SetClampedToScreen(dispelOutlineDrop, true) end
	-- Keep default dropdown visuals (same look as Aggro border dropdown).
	if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(dispelOutlineDrop, "LEFT") end
MSUF_MakeDropdownScrollable(dispelOutlineDrop, 10)

local dispelOutlineOptions = {
    { key = 0, label = TR("Dispel border off") },
    { key = 1, label = TR("Dispel border on") },
}

local function _DispelOutline_Get()
    local g = MSUF_DB and MSUF_DB.general
    return (g and g.dispelOutlineMode) or 0
end

local function _DispelOutline_Set(val)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.dispelOutlineMode = val
    if type(_G.MSUF_DispelOutline_ApplyEventRegistration) == "function" then
        _G.MSUF_DispelOutline_ApplyEventRegistration()
    end

    if type(_G.MSUF_RefreshDispelOutlineStates) == "function" then
        _G.MSUF_RefreshDispelOutlineStates(true)
    else
        local fn = _G.MSUF_RefreshRareBarVisuals
        local frames = _G.MSUF_UnitFrames
        if type(fn) == "function" and type(frames) == "table" then
            if frames.player then fn(frames.player) end
            if frames.target then fn(frames.target) end
            if frames.focus then fn(frames.focus) end
            if frames.targettarget then fn(frames.targettarget) end
        end
    end
end

MSUF_InitSimpleDropdown(
    dispelOutlineDrop,
    dispelOutlineOptions,
    _DispelOutline_Get,
    function(v) _DispelOutline_Set(v) end,
    function() _DispelOutline_Set(_DispelOutline_Get()) end,
    170
)
dispelOutlineDrop._msufDispelOutlineOptions = dispelOutlineOptions
dispelOutlineDrop._msufDispelOutlineGet = _DispelOutline_Get

-- Options-only: Test mode to force the dispel border on while this menu is open.
local dispelTestCheck = CreateFrame("CheckButton", "MSUF_DispelOutlineTestCheck", barGroup, "ChatConfigCheckButtonTemplate")
dispelTestCheck:SetPoint("LEFT", dispelOutlineDrop, "RIGHT", 6, -4)
dispelTestCheck.Text:SetText(TR("Test"))
dispelTestCheck.tooltipText = TR("Dispel border: Player, Target, Focus, Target of Target")
dispelTestCheck:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
dispelTestCheck:HookScript("OnLeave", function() GameTooltip:Hide() end)
dispelTestCheck:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if type(_G.MSUF_SetDispelBorderTestMode) == "function" then
        _G.MSUF_SetDispelBorderTestMode(on)
    end
end)

-- Purge border: yellow outline border when the player can purge/spellsteal a buff on the unit.
local purgeOutlineDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_PurgeOutlineDropdown", barGroup) or CreateFrame("Frame", "MSUF_PurgeOutlineDropdown", barGroup, "UIDropDownMenuTemplate"))
MSUF_ExpandDropdownClickArea(purgeOutlineDrop)
purgeOutlineDrop:SetPoint("TOPLEFT", dispelOutlineDrop, "BOTTOMLEFT", 0, -18)
UIDropDownMenu_SetWidth(purgeOutlineDrop, 170)
if UIDropDownMenu_SetClampedToScreen then UIDropDownMenu_SetClampedToScreen(purgeOutlineDrop, true) end
	if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(purgeOutlineDrop, "LEFT") end
MSUF_MakeDropdownScrollable(purgeOutlineDrop, 10)

local purgeOutlineOptions = {
    { key = 0, label = TR("Purge border off") },
    { key = 1, label = TR("Purge border on") },
}

local function _PurgeOutline_Get()
    local g = MSUF_DB and MSUF_DB.general
    return (g and g.purgeOutlineMode) or 0
end

local function _PurgeOutline_Set(val)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.purgeOutlineMode = val
    if type(_G.MSUF_DispelOutline_ApplyEventRegistration) == "function" then
        _G.MSUF_DispelOutline_ApplyEventRegistration()
    end
    if type(_G.MSUF_RefreshDispelOutlineStates) == "function" then
        _G.MSUF_RefreshDispelOutlineStates(true)
    else
        local fn = _G.MSUF_RefreshRareBarVisuals
        local frames = _G.MSUF_UnitFrames
        if type(fn) == "function" and type(frames) == "table" then
            if frames.player then fn(frames.player) end
            if frames.target then fn(frames.target) end
            if frames.focus then fn(frames.focus) end
            if frames.targettarget then fn(frames.targettarget) end
        end
    end
end

MSUF_InitSimpleDropdown(
    purgeOutlineDrop,
    purgeOutlineOptions,
    _PurgeOutline_Get,
    function(v) _PurgeOutline_Set(v) end,
    function() _PurgeOutline_Set(_PurgeOutline_Get()) end,
    170
)
purgeOutlineDrop._msufPurgeOutlineOptions = purgeOutlineOptions
purgeOutlineDrop._msufPurgeOutlineGet = _PurgeOutline_Get

local purgeTestCheck = CreateFrame("CheckButton", "MSUF_PurgeOutlineTestCheck", barGroup, "ChatConfigCheckButtonTemplate")
purgeTestCheck:SetPoint("LEFT", purgeOutlineDrop, "RIGHT", 6, -4)
purgeTestCheck.Text:SetText(TR("Test"))
purgeTestCheck.tooltipText = TR("Purge border: Target, Focus, Target of Target")
purgeTestCheck:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
purgeTestCheck:HookScript("OnLeave", function() GameTooltip:Hide() end)
purgeTestCheck:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
        _G.MSUF_SetPurgeBorderTestMode(on)
    end
end)

-- Ã¢â€â‚¬Ã¢â€â‚¬ Highlight priority reorder Ã¢â€â‚¬Ã¢â€â‚¬
-- Draggable rows to set display priority of highlight borders (Aggro/Dispel/Purge).
-- Default order: Dispel > Aggro > Purge.  Custom order stored in DB.
local _PRIO_DEFAULTS = { "dispel", "aggro", "purge" }  -- must match render fallback order
local _PRIO_LABELS   = { dispel = "Dispel", aggro = "Aggro", purge = "Purge" }

local prioCheck = CreateFrame("CheckButton", "MSUF_HighlightPrioCheck", barGroup, "ChatConfigCheckButtonTemplate")
prioCheck:SetPoint("TOPLEFT", purgeOutlineDrop, "BOTTOMLEFT", 16, -10)
prioCheck.Text:SetText(TR("Custom highlight priority"))
prioCheck.tooltipText = TR("Drag to reorder which highlight border takes priority when multiple are active.")
prioCheck:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(TR("Custom highlight priority"), 1, 1, 1)
    GameTooltip:AddLine(self.tooltipText, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
prioCheck:HookScript("OnLeave", function() GameTooltip:Hide() end)

local prioContainer = CreateFrame("Frame", "MSUF_HighlightPrioContainer", barGroup)
prioContainer:SetSize(200, 78)
prioContainer:SetPoint("TOPLEFT", prioCheck, "BOTTOMLEFT", -2, -4)

local _PRIO_ROW_H, _PRIO_ROW_GAP = 22, 4
local _prioRows = {}

local function _Prio_GetOrder()
    local g = MSUF_DB and MSUF_DB.general
    local o = g and g.highlightPrioOrder
    if type(o) == "table" and #o == 3 then return { o[1], o[2], o[3] } end
    return { _PRIO_DEFAULTS[1], _PRIO_DEFAULTS[2], _PRIO_DEFAULTS[3] }
end

local function _Prio_SlotY(s)
    return -((s - 1) * (_PRIO_ROW_H + _PRIO_ROW_GAP))
end

local function _Prio_SnapAll()
    for i = 1, 3 do
        local row = _prioRows[i]
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", prioContainer, "TOPLEFT", 0, _Prio_SlotY(row.slotIndex))
    end
end

local function _Prio_SaveOrder()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local sorted = {}
    for i = 1, 3 do sorted[i] = _prioRows[i] end
    table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
    local order = {}
    for i = 1, 3 do order[i] = sorted[i].key end
    MSUF_DB.general.highlightPrioOrder = order
    -- Full refresh: covers player/target/focus/targettarget/boss1-5.
    if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then
        _G.MSUF_ApplyBarOutlineThickness_All()
    end
end

local function _Prio_SetEnabled(enabled)
    for i = 1, 3 do
        local row = _prioRows[i]
        row.frame:SetAlpha(enabled and 1 or 0.4)
        row.frame:EnableMouse(enabled and true or false)
    end
end

for i = 1, 3 do
    local rf = CreateFrame("Frame", "MSUF_PrioRow" .. i, prioContainer, BackdropTemplateMixin and "BackdropTemplate" or nil)
    rf:SetSize(190, _PRIO_ROW_H)
    rf:SetMovable(true)
    rf:EnableMouse(true)
    rf:RegisterForDrag("LeftButton")
    rf:SetBackdrop({
        bgFile   = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
        edgeFile = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    rf:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
    rf:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    local stripe = rf:CreateTexture(nil, "ARTWORK")
    stripe:SetSize(4, _PRIO_ROW_H - 2)
    stripe:SetPoint("LEFT", rf, "LEFT", 2, 0)
    rf._stripe = stripe
    local label = rf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", stripe, "RIGHT", 6, 0)
    rf._label = label
    local num = rf:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    num:SetPoint("RIGHT", rf, "RIGHT", -8, 0)
    num:SetTextColor(0.5, 0.5, 0.5, 1)
    rf._numText = num
    rf:SetScript("OnEnter", function(self)
        local g = MSUF_DB and MSUF_DB.general
        if not (g and g.highlightPrioEnabled == 1) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TR("Drag to reorder"), 1, 1, 1)
        GameTooltip:AddLine(TR("Left-click and drag up or down to change highlight priority."), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rf:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:StartMoving()
        self:SetFrameStrata("TOOLTIP")
    end)
    rf:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetFrameStrata(prioContainer:GetFrameStrata())
        local _, selfY = self:GetCenter()
        local contTop = prioContainer:GetTop()
        local bestSlot, bestDist = 1, math.huge
        for s = 1, 3 do
            local slotY = contTop + _Prio_SlotY(s) - _PRIO_ROW_H / 2
            local dist = math.abs(selfY - slotY)
            if dist < bestDist then bestDist = dist; bestSlot = s end
        end
        local myRow
        for idx = 1, 3 do
            if _prioRows[idx].frame == self then myRow = _prioRows[idx]; break end
        end
        if myRow and myRow.slotIndex ~= bestSlot then
            for idx = 1, 3 do
                if _prioRows[idx].slotIndex == bestSlot then
                    _prioRows[idx].slotIndex = myRow.slotIndex; break
                end
            end
            myRow.slotIndex = bestSlot
        end
        for idx = 1, 3 do
            _prioRows[idx].frame._numText:SetText(tostring(_prioRows[idx].slotIndex))
        end
        _Prio_SnapAll()
        _Prio_SaveOrder()
    end)
    _prioRows[i] = { frame = rf, key = "", slotIndex = i }
end

local function _Prio_InitRows()
    local order = _Prio_GetOrder()
    local g = MSUF_DB and MSUF_DB.general
    -- Read actual colors from Colors menu DB, with fallback defaults.
    local dbColors = {
        dispel = {
            (g and g.dispelBorderColorR) or 0.25,
            (g and g.dispelBorderColorG) or 0.75,
            (g and g.dispelBorderColorB) or 1.00,
        },
        aggro = {
            (g and g.aggroBorderColorR) or 1.00,
            (g and g.aggroBorderColorG) or 0.50,
            (g and g.aggroBorderColorB) or 0.00,
        },
        purge = {
            (g and g.purgeBorderColorR) or 1.00,
            (g and g.purgeBorderColorG) or 0.85,
            (g and g.purgeBorderColorB) or 0.00,
        },
    }
    for i = 1, 3 do
        local key = order[i]
        local col = dbColors[key] or { 1, 1, 1 }
        _prioRows[i].key = key
        _prioRows[i].slotIndex = i
        _prioRows[i].frame._stripe:SetColorTexture(col[1], col[2], col[3], 1)
        _prioRows[i].frame._label:SetText(TR(_PRIO_LABELS[key] or key))
        _prioRows[i].frame._numText:SetText(tostring(i))
    end
    _Prio_SnapAll()
end
_Prio_InitRows()

_G.MSUF_PrioRows_Reinit = function()
    _Prio_InitRows()
    local g = MSUF_DB and MSUF_DB.general
    _Prio_SetEnabled(g and g.highlightPrioEnabled == 1)
end

prioCheck:SetScript("OnClick", function(self)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local on = self:GetChecked() and true or false
    MSUF_DB.general.highlightPrioEnabled = on and 1 or 0
    _Prio_SetEnabled(on)
    _Prio_SaveOrder()
end)
do
    local g = MSUF_DB and MSUF_DB.general
    prioCheck:SetChecked(g and g.highlightPrioEnabled == 1)
    _Prio_SetEnabled(g and g.highlightPrioEnabled == 1)
end

-- Bars menu style: boxed layout like the new Castbar/Focus Kick menus
-- (Two framed columns: Bar appearance / Power Bar Settings)
do
    -- Panel height must include the HP + Power Spacer controls at the bottom of the right column.
    -- Keep this as a single constant so creation + live re-layout always match (no drift/regressions).
    -- Increased slightly to ensure the Highlight Border section (and dropdown buttons) never clip at the bottom.
    local BARS_PANEL_H = 1170
    -- Create panels once
    if not _G["MSUF_BarsMenuPanelLeft"] then
        local function SetupPanel(panel)
            panel:SetBackdrop({
                bgFile   = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
                edgeFile = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.20)
            panel:SetBackdropBorderColor(1, 1, 1, 0.15)
         end
        local leftPanel = CreateFrame("Frame", "MSUF_BarsMenuPanelLeft", barGroup, "BackdropTemplate")
        leftPanel:SetSize(330, BARS_PANEL_H)
        leftPanel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, -172)
        SetupPanel(leftPanel)
        local rightPanel = CreateFrame("Frame", "MSUF_BarsMenuPanelRight", barGroup, "BackdropTemplate")
        rightPanel:SetSize(320, BARS_PANEL_H)
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
        SetupPanel(rightPanel)
        local leftHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        leftHeader:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 16, -12)
        leftHeader:SetText(TR("Bar appearance"))
        local rightHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        rightHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -12)
        rightHeader:SetText(TR("Power Bar Settings"))
        _G.MSUF_BarsMenuRightHeader = rightHeader
        -- Section labels in left panel
        local absorbHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        absorbHeader:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -18)
        absorbHeader:SetText(TR("Absorb Display"))
        _G.MSUF_BarsMenuAbsorbHeader = absorbHeader
        local texHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        texHeader:SetText(TR("Bar texture (SharedMedia)"))
        _G.MSUF_BarsMenuTexturesHeader = texHeader
        local gradHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        gradHeader:SetText(TR("Gradient Options"))
        _G.MSUF_BarsMenuGradientHeader = gradHeader
        -- Highlight border section label in left panel
        local highlightHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        highlightHeader:SetText(TR("Bar Highlight Border"))
        _G.MSUF_BarsMenuHighlightHeader = highlightHeader
        -- Section label in right panel
        local borderHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        borderHeader:SetText(TR("Border & Text Options"))
        _G.MSUF_BarsMenuBorderHeader = borderHeader
        -- Inline-dropdown helper
        -- Label sits on the left; value text can be RIGHT-aligned (default)
        -- or CENTERed (used for SharedMedia texture dropdowns so the chosen
        -- texture name is more readable).
        local function MakeInlineDropdown(drop, labelText, labelOffsetX, valueAlign)
            labelOffsetX = (labelOffsetX ~= nil) and labelOffsetX or 28
            valueAlign = valueAlign or "RIGHT"
            if not drop or not labelText then  return end
            local name = drop:GetName()
            if not name then  return end
            local txt = _G[name .. "Text"]
            if txt then
                txt:ClearAllPoints()
                if valueAlign == "CENTER" then
                    -- Centered value: keep it away from the arrow on the right.
                    txt:SetPoint("CENTER", drop, "CENTER", 18, 2)
                    txt:SetWidth(170)
                    txt:SetJustifyH("CENTER")
                    if txt.SetWordWrap then txt:SetWordWrap(false) end
                else
                    -- Right-aligned value.
                    -- Give the value text a real width so it doesn't collapse into 2-3 chars.
                    txt:SetPoint("LEFT",  drop, "LEFT", 120, 2)
                    txt:SetPoint("RIGHT", drop, "RIGHT", -30, 2)
                    txt:SetJustifyH("RIGHT")
                end
                if txt.SetFontObject then txt:SetFontObject("GameFontNormalSmall") end
                txt:SetTextColor(0.95, 0.95, 0.95, 1)
            end
            if not drop._msufInlineLabel then
                local lab = drop:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                lab:SetPoint("LEFT", drop, "LEFT", labelOffsetX, 2)
                lab:SetTextColor(0.85, 0.85, 0.85, 1)
                if labelOffsetX and labelOffsetX ~= 28 then
                    lab:SetWidth(90)
                    lab:SetJustifyH("CENTER")
                else
                    lab:SetWidth(0)
                    lab:SetJustifyH("LEFT")
                end
                drop._msufInlineLabel = lab
            end
            drop._msufInlineLabel:SetText(labelText)
         end
        _G.MSUF_BarsMenu_MakeInlineDropdown = MakeInlineDropdown
    end
    local leftPanel  = _G["MSUF_BarsMenuPanelLeft"]
    local rightPanel = _G["MSUF_BarsMenuPanelRight"]
    -- Enforce layout (so tweaks apply even if panels already exist)
    if leftPanel then
        leftPanel:ClearAllPoints()
        leftPanel:SetSize(330, BARS_PANEL_H)
        leftPanel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, -172)
    end
    if rightPanel and leftPanel then
        rightPanel:ClearAllPoints()
        rightPanel:SetSize(320, BARS_PANEL_H)
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
    end
    -- Hide old title if still around
    if barsTitle then barsTitle:Hide() end
    -- Absorb section
    if absorbDisplayLabel and _G.MSUF_BarsMenuAbsorbHeader then
        absorbDisplayLabel:ClearAllPoints()
        absorbDisplayLabel:SetPoint("TOPLEFT", _G.MSUF_BarsMenuAbsorbHeader, "TOPLEFT", 0, 0)
        absorbDisplayLabel:SetText(TR("Absorb Display"))
    end
    -- Divider line under "Absorb Display"
    local absorbLine = leftPanel and leftPanel.MSUF_SectionLine_Absorb
    if leftPanel then
        if not absorbLine then
            absorbLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Absorb = absorbLine
            absorbLine:SetColorTexture(1, 1, 1, 0.20)
            absorbLine:SetHeight(1)
        end
        absorbLine:ClearAllPoints()
        if absorbDisplayLabel then
            absorbLine:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
            absorbLine:SetWidth(296)
            absorbLine:Show()
        else
            absorbLine:Hide()
        end
    end
    if absorbDisplayDrop and absorbDisplayLabel then
        absorbDisplayDrop:ClearAllPoints()
        if absorbLine and absorbLine:IsShown() then
            absorbDisplayDrop:SetPoint("TOPLEFT", absorbLine, "BOTTOMLEFT", 0, -6)
        else
            absorbDisplayDrop:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
        end
        UIDropDownMenu_SetWidth(absorbDisplayDrop, 260)
    end
-- Absorb texture overrides (under Absorb anchoring)
if absorbTextureLabel and absorbAnchorDrop then
    absorbTextureLabel:ClearAllPoints()
    absorbTextureLabel:SetPoint("TOPLEFT", absorbAnchorDrop, "BOTTOMLEFT", 16, -12)
    absorbTextureLabel:SetText(TR("Absorb bar texture (SharedMedia)"))
end
if absorbBarTextureDrop and absorbTextureLabel then
    absorbBarTextureDrop:ClearAllPoints()
    absorbBarTextureDrop:SetPoint("TOPLEFT", absorbTextureLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(absorbBarTextureDrop, 260)
    if _G.MSUF_BarsMenu_MakeInlineDropdown then _G.MSUF_BarsMenu_MakeInlineDropdown(absorbBarTextureDrop, "Absorb", nil, "CENTER") end
end
if healAbsorbTextureDrop and absorbBarTextureDrop then
    healAbsorbTextureDrop:ClearAllPoints()
    healAbsorbTextureDrop:SetPoint("TOPLEFT", absorbBarTextureDrop, "BOTTOMLEFT", 0, -8)
    UIDropDownMenu_SetWidth(healAbsorbTextureDrop, 260)
    if _G.MSUF_BarsMenu_MakeInlineDropdown then _G.MSUF_BarsMenu_MakeInlineDropdown(healAbsorbTextureDrop, "Heal-Absorb", nil, "CENTER") end
end
if absorbTexTestCB and healAbsorbTextureDrop then
    absorbTexTestCB:ClearAllPoints()
    absorbTexTestCB:SetPoint("TOPLEFT", healAbsorbTextureDrop, "BOTTOMLEFT", 16, -8)
end
-- Textures section (foreground + background)
    local texHeader = _G.MSUF_BarsMenuTexturesHeader
    if texHeader and (healAbsorbTextureDrop or absorbBarTextureDrop or absorbAnchorDrop or absorbDisplayDrop) and leftPanel then
        texHeader:ClearAllPoints()
        local _absAnchor = absorbTexTestCB or healAbsorbTextureDrop or absorbBarTextureDrop or absorbAnchorDrop or absorbDisplayDrop
        texHeader:SetPoint("TOPLEFT", _absAnchor, "BOTTOMLEFT", 16, -18)
    end
    if barTextureLabel and texHeader then
        barTextureLabel:ClearAllPoints()
        barTextureLabel:SetPoint("TOPLEFT", texHeader, "TOPLEFT", 0, 0)
        barTextureLabel:SetText(TR("Bar texture (SharedMedia)"))
    end
    -- Divider line under "Bar texture (SharedMedia)"
    local texturesLine = leftPanel and leftPanel.MSUF_SectionLine_Textures
    if leftPanel then
        if not texturesLine then
            texturesLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Textures = texturesLine
            texturesLine:SetColorTexture(1, 1, 1, 0.20)
            texturesLine:SetHeight(1)
        end
        texturesLine:ClearAllPoints()
        if barTextureLabel then
            texturesLine:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -4)
            texturesLine:SetWidth(296)
            texturesLine:Show()
        else
            texturesLine:Hide()
        end
    end
    if barTextureDrop and barTextureLabel then
        barTextureDrop:ClearAllPoints()
        if texturesLine and texturesLine:IsShown() then
            barTextureDrop:SetPoint("TOPLEFT", texturesLine, "BOTTOMLEFT", 0, -6)
        else
            barTextureDrop:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -6)
        end
        UIDropDownMenu_SetWidth(barTextureDrop, 260)
        if _G.MSUF_BarsMenu_MakeInlineDropdown then
            -- Keep label on the left, show the selected texture name centered.
            _G.MSUF_BarsMenu_MakeInlineDropdown(barTextureDrop, "Foreground", nil, "CENTER")
        end
    end
    if barBgTextureLabel and barTextureDrop then
        barBgTextureLabel:ClearAllPoints()
        barBgTextureLabel:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 16, -12)
        barBgTextureLabel:SetText(TR("")) -- hidden; we use inline label
        barBgTextureLabel:Hide()
    end
    if barBgTextureDrop and barTextureDrop then
        barBgTextureDrop:ClearAllPoints()
        barBgTextureDrop:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 0, -20)
        UIDropDownMenu_SetWidth(barBgTextureDrop, 260)
        if _G.MSUF_BarsMenu_MakeInlineDropdown then
            -- Keep label on the left, show the selected texture name centered.
            _G.MSUF_BarsMenu_MakeInlineDropdown(barBgTextureDrop, "Background", nil, "CENTER")
        end
    end
    -- If the bar texture preview exists (LSM mode), hide it (mockup-style)
    if _G.MSUF_BarTexturePreview then _G.MSUF_BarTexturePreview:Hide() end
    if barTextureInfo then barTextureInfo:Hide() end
    -- Gradient section
    local gradHeader = _G.MSUF_BarsMenuGradientHeader
    local gradAnchor = barBgTextureDrop or barTextureDrop or absorbDisplayDrop
    if gradHeader and gradAnchor then
        gradHeader:ClearAllPoints()
        -- Align this section title like the other left-panel section headers.
        -- Dropdown rows are anchored 16px left of the section title, but the Background Alpha
        -- slider is already aligned with the title. So we adjust the X-offset depending on
        -- which widget we're anchoring below.
        local xOff = 16
        -- Extra breathing room below the Background Alpha slider so the section title never clips.
        gradHeader:SetPoint("TOPLEFT", gradAnchor, "BOTTOMLEFT", xOff, -32)
        gradHeader:Show()
    end
    -- Divider line under "Gradient Options"
    local gradLine = leftPanel and leftPanel.MSUF_SectionLine_Gradient
    if leftPanel then
        if not gradLine then
            gradLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Gradient = gradLine
            gradLine:SetColorTexture(1, 1, 1, 0.20)
            gradLine:SetHeight(1)
        end
        gradLine:ClearAllPoints()
        if gradHeader then
            gradLine:SetPoint("TOPLEFT", gradHeader, "BOTTOMLEFT", -16, -4)
            gradLine:SetWidth(296)
            gradLine:Show()
        else
            gradLine:Hide()
        end
    end
    if gradientCheck and gradHeader then
        gradientCheck:ClearAllPoints()
        if gradLine and gradLine:IsShown() then
            gradientCheck:SetPoint("TOPLEFT", gradLine, "BOTTOMLEFT", 16, -18)
        else
            gradientCheck:SetPoint("TOPLEFT", gradHeader, "BOTTOMLEFT", 0, -18)
        end
    end
    if powerGradientCheck and gradientCheck then
        powerGradientCheck:ClearAllPoints()
        powerGradientCheck:SetPoint("TOPLEFT", gradientCheck, "BOTTOMLEFT", 0, -8)
    end
    if gradientStrengthSlider and powerGradientCheck then
        gradientStrengthSlider:ClearAllPoints()
        gradientStrengthSlider:SetPoint("TOPLEFT", powerGradientCheck, "BOTTOMLEFT", 0, -18)
        if gradientStrengthSlider.SetWidth then gradientStrengthSlider:SetWidth(260) end
    end
if gradientDirPad and gradientCheck then
        gradientDirPad:ClearAllPoints()
        -- Fixed X so long labels can't push the pad into the right column.
        gradientDirPad:SetPoint("TOPLEFT", gradientCheck, "TOPLEFT", 196, -3)
        gradientDirPad:Show()
    end
    -- Right panel: power bar settings
    if targetPowerBarCheck and rightPanel then
        targetPowerBarCheck:ClearAllPoints()
        targetPowerBarCheck:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -50)
    end
    if bossPowerBarCheck and targetPowerBarCheck then
        bossPowerBarCheck:ClearAllPoints()
        bossPowerBarCheck:SetPoint("TOPLEFT", targetPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end
    if playerPowerBarCheck and bossPowerBarCheck then
        playerPowerBarCheck:ClearAllPoints()
        playerPowerBarCheck:SetPoint("TOPLEFT", bossPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end
    if focusPowerBarCheck and playerPowerBarCheck then
        focusPowerBarCheck:ClearAllPoints()
        focusPowerBarCheck:SetPoint("TOPLEFT", playerPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end
    if powerBarHeightLabel and focusPowerBarCheck then
        powerBarHeightLabel:ClearAllPoints()
        powerBarHeightLabel:SetPoint("TOPLEFT", focusPowerBarCheck, "BOTTOMLEFT", 0, -18)
    end
    if powerBarHeightEdit and powerBarHeightLabel then
        powerBarHeightEdit:ClearAllPoints()
        powerBarHeightEdit:SetPoint("LEFT", powerBarHeightLabel, "RIGHT", 10, 0)
    end
    if powerBarEmbedCheck and powerBarHeightLabel then
        powerBarEmbedCheck:ClearAllPoints()
        powerBarEmbedCheck:SetPoint("TOPLEFT", powerBarHeightLabel, "BOTTOMLEFT", 0, -10)
    end
    if powerBarBorderCheck and powerBarEmbedCheck then
        powerBarBorderCheck:ClearAllPoints()
        powerBarBorderCheck:SetPoint("TOPLEFT", powerBarEmbedCheck, "BOTTOMLEFT", 0, -10)
    end
    if powerBarBorderSizeLabel and powerBarBorderCheck then
        powerBarBorderSizeLabel:ClearAllPoints()
        powerBarBorderSizeLabel:SetPoint("TOPLEFT", powerBarBorderCheck, "BOTTOMLEFT", 0, -10)
    end
    if powerBarBorderSizeEdit and powerBarBorderSizeLabel then
        powerBarBorderSizeEdit:ClearAllPoints()
        powerBarBorderSizeEdit:SetPoint("LEFT", powerBarBorderSizeLabel, "RIGHT", 10, 0)
    end
-- Bar outline thickness: render as a section TITLE (like "Gradient Options")
-- and place the slider under a divider line (hide the slider's own title text).
if _G.MSUF_BarsMenuBorderHeader then _G.MSUF_BarsMenuBorderHeader:Hide() end
local outlineAnchor = gradientCheck or gradLine or gradHeader
local outlineHeader = leftPanel and leftPanel.MSUF_SectionHeader_Outline
if leftPanel and not outlineHeader then
    outlineHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    leftPanel.MSUF_SectionHeader_Outline = outlineHeader
    outlineHeader:SetText(TR("Outline thickness"))
end
if outlineHeader and outlineAnchor then
    outlineHeader:ClearAllPoints()
    if gradientDirPad and gradientCheck then
        -- Align section to the left edge, but place it BELOW the pad (pad is taller than the checkbox row).
        outlineHeader:SetPoint("TOPLEFT", gradientDirPad, "BOTTOMLEFT", -196, -84)
    else
        outlineHeader:SetPoint("TOPLEFT", outlineAnchor, "BOTTOMLEFT", 0, -84)
    end
    outlineHeader:Show()
end
local outlineLine = leftPanel and leftPanel.MSUF_SectionLine_Outline
if leftPanel then
    if not outlineLine then
        outlineLine = leftPanel:CreateTexture(nil, "ARTWORK")
        leftPanel.MSUF_SectionLine_Outline = outlineLine
        outlineLine:SetColorTexture(1, 1, 1, 0.20)
        outlineLine:SetHeight(1)
    end
    outlineLine:ClearAllPoints()
    if outlineHeader then
        outlineLine:SetPoint("TOPLEFT", outlineHeader, "BOTTOMLEFT", -16, -4)
        outlineLine:SetWidth(296)
        outlineLine:Show()
    else
        outlineLine:Hide()
    end
end
if barOutlineThicknessSlider and outlineLine and outlineLine:IsShown() then
    barOutlineThicknessSlider:ClearAllPoints()
    barOutlineThicknessSlider:SetPoint("TOPLEFT", outlineLine, "BOTTOMLEFT", 16, -14)
    barOutlineThicknessSlider:SetWidth(280)
    -- Hide the slider's built-in title text; we use the section header above.
    local sName = barOutlineThicknessSlider.GetName and barOutlineThicknessSlider:GetName()
    if sName and _G then
        local t = _G[sName .. "Text"]
        if t then
            t:SetText(TR(""))
            t:Hide()
        end
    end
end
-- Match Power bar outline slider width to Outline thickness (both 280)
do
    local dpb = _G.MSUF_DPBOutlineSlider
    local s = dpb and (dpb.slider or dpb)
    if s and s.SetWidth then
        s:SetWidth(280)
    end
end

-- Left panel: Highlight border section (Aggro/Dispel + future border highlights)
do
    local leftPanel = _G["MSUF_BarsMenuPanelLeft"]
    local dpb = _G.MSUF_DPBOutlineSlider
    local outlineSlider = (dpb and (dpb.slider or dpb)) or barOutlineThicknessSlider

    -- Hide the simple label created during initial panel build; we render this section
    -- using the same header+divider style as "Gradient Options" / "Outline thickness".
    local legacyHeader = _G.MSUF_BarsMenuHighlightHeader
    if legacyHeader then legacyHeader:Hide() end

    -- Section header Ã¢â‚¬â€ compact font
    local highlightHeader = leftPanel and leftPanel.MSUF_SectionHeader_Highlight
    if leftPanel and not highlightHeader then
        highlightHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        leftPanel.MSUF_SectionHeader_Highlight = highlightHeader
        highlightHeader:SetText(TR("Bar Highlight Border"))
    end

    if highlightHeader and outlineSlider then
        highlightHeader:ClearAllPoints()
        highlightHeader:SetPoint("TOPLEFT", outlineSlider, "BOTTOMLEFT", 0, -62)
        highlightHeader:Show()
    elseif highlightHeader then
        highlightHeader:Hide()
    end

    -- Divider line under the header (same styling as other section dividers)
    local highlightLine = leftPanel and leftPanel.MSUF_SectionLine_Highlight
    if leftPanel then
        if not highlightLine then
            highlightLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Highlight = highlightLine
            highlightLine:SetColorTexture(1, 1, 1, 0.20)
            highlightLine:SetHeight(1)
        end
        highlightLine:ClearAllPoints()
        if highlightHeader and highlightHeader:IsShown() then
            highlightLine:SetPoint("TOPLEFT", highlightHeader, "BOTTOMLEFT", -16, -4)
            highlightLine:SetWidth(296)
            highlightLine:Show()
        else
            highlightLine:Hide()
        end
    end

    -- Re-anchor highlight thickness slider + Aggro/Dispel/Purge dropdowns + priority widget
    local hlSlider = _G["MSUF_HighlightBorderThicknessSlider"]
    local aggroDrop = _G["MSUF_AggroOutlineDropdown"]
    local aggroTest = _G["MSUF_AggroOutlineTestCheck"]
    local dispelDrop = _G["MSUF_DispelOutlineDropdown"]
    local dispelTest = _G["MSUF_DispelOutlineTestCheck"]
    local purgeDrop = _G["MSUF_PurgeOutlineDropdown"]
    local purgeTest = _G["MSUF_PurgeOutlineTestCheck"]
    local prioChk = _G["MSUF_HighlightPrioCheck"]
    local prioCont = _G["MSUF_HighlightPrioContainer"]

    if hlSlider and highlightLine and highlightLine:IsShown() then
        hlSlider:ClearAllPoints()
        hlSlider:SetPoint("TOPLEFT", highlightLine, "BOTTOMLEFT", 16, -18)
        hlSlider:SetWidth(280)
    end

    if aggroDrop and hlSlider then
        aggroDrop:ClearAllPoints()
        aggroDrop:SetPoint("TOPLEFT", hlSlider, "BOTTOMLEFT", -16, -28)
        UIDropDownMenu_SetWidth(aggroDrop, 170)
		if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(aggroDrop, "LEFT") end
    end
    if aggroTest and aggroDrop then
        aggroTest:ClearAllPoints()
        aggroTest:SetPoint("LEFT", aggroDrop, "RIGHT", 6, -4)
    end
    if dispelDrop and aggroDrop then
        dispelDrop:ClearAllPoints()
        dispelDrop:SetPoint("TOPLEFT", aggroDrop, "BOTTOMLEFT", 0, -12)
        UIDropDownMenu_SetWidth(dispelDrop, 170)
    end
	if dispelTest and dispelDrop then
		dispelTest:ClearAllPoints()
		dispelTest:SetPoint("LEFT", dispelDrop, "RIGHT", 6, -4)
	end
    if purgeDrop and dispelDrop then
        purgeDrop:ClearAllPoints()
        purgeDrop:SetPoint("TOPLEFT", dispelDrop, "BOTTOMLEFT", 0, -12)
        UIDropDownMenu_SetWidth(purgeDrop, 170)
    end
    if purgeTest and purgeDrop then
        purgeTest:ClearAllPoints()
        purgeTest:SetPoint("LEFT", purgeDrop, "RIGHT", 6, -4)
    end
    if prioChk and purgeDrop then
        prioChk:ClearAllPoints()
        prioChk:SetPoint("TOPLEFT", purgeDrop, "BOTTOMLEFT", 16, -10)
    end
    if prioCont and prioChk then
        prioCont:ClearAllPoints()
        prioCont:SetPoint("TOPLEFT", prioChk, "BOTTOMLEFT", -2, -4)
    end
end
-- Bar scope: positioned ABOVE both panels so it's always visible at the top.
do
    local leftPanel2 = _G["MSUF_BarsMenuPanelLeft"]
    -- Hide the old scope section line inside the left panel (no longer needed there).
    if leftPanel2 and leftPanel2.MSUF_SectionLine_BarScope then
        leftPanel2.MSUF_SectionLine_BarScope:Hide()
    end
    -- Anchor scope header + dropdown above the two-column panels.
    local scopeHeader = barGroup._msufBarScopeHeader
    if scopeHeader then
        scopeHeader:ClearAllPoints()
        scopeHeader:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 16, -120)
        scopeHeader:Show()
    end
    if hpPowerScopeLabel and scopeHeader then
        hpPowerScopeLabel:ClearAllPoints()
        hpPowerScopeLabel:SetPoint("LEFT", scopeHeader, "RIGHT", 12, 0)
        hpPowerScopeLabel:SetText(TR("Configure settings for"))
    end
    if hpPowerScopeDrop and hpPowerScopeLabel then
        hpPowerScopeDrop:ClearAllPoints()
        hpPowerScopeDrop:SetPoint("LEFT", hpPowerScopeLabel, "RIGHT", -10, -2)
        UIDropDownMenu_SetWidth(hpPowerScopeDrop, 160)
    end
    if hpPowerOverrideCheck and hpPowerScopeDrop then
        hpPowerOverrideCheck:ClearAllPoints()
        hpPowerOverrideCheck:SetPoint("LEFT", hpPowerScopeDrop, "RIGHT", -10, 0)
    end
end
-- Right panel: text modes anchor directly under power bar border (scope dropdown moved to left)
    local textTopAnchor = powerBarBorderSizeLabel or powerBarBorderCheck or powerBarEmbedCheck or powerBarHeightLabel
    if hpModeLabel then
        hpModeLabel:ClearAllPoints()
        if textTopAnchor then
            hpModeLabel:SetPoint("TOPLEFT", textTopAnchor, "BOTTOMLEFT", 0, -28)
        end
    end
    local textModesLine
    if rightPanel then
        if not rightPanel.MSUF_SectionLine_TextModes then
            local ln = rightPanel:CreateTexture(nil, "ARTWORK")
            rightPanel.MSUF_SectionLine_TextModes = ln
            ln:SetColorTexture(1, 1, 1, 0.20)
            ln:SetHeight(1)
        end
        textModesLine = rightPanel.MSUF_SectionLine_TextModes
    end
    if textModesLine and hpModeLabel then
        textModesLine:ClearAllPoints()
        textModesLine:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -4)
        textModesLine:SetWidth(286)
        textModesLine:Show()
    elseif textModesLine then
        textModesLine:Hide()
    end
    if hpModeDrop and hpModeLabel then
        hpModeDrop:ClearAllPoints()
        if textModesLine and textModesLine:IsShown() then
            hpModeDrop:SetPoint("TOPLEFT", textModesLine, "BOTTOMLEFT", 0, -6)
        else
            hpModeDrop:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -6)
        end
        UIDropDownMenu_SetWidth(hpModeDrop, 260)
    end
    -- Keep Text Separators block stable on resize (no regressions)
    if sepHeader and powerModeDrop then
        sepHeader:ClearAllPoints()
        sepHeader:SetPoint("TOPLEFT", powerModeDrop, "BOTTOMLEFT", 16, -12)
    end
    if hpSepLabel and sepHeader then
        hpSepLabel:ClearAllPoints()
        hpSepLabel:SetPoint("TOPLEFT", sepHeader, "BOTTOMLEFT", 0, -10)
    end
    if powerSepLabel and hpSepLabel then
        powerSepLabel:ClearAllPoints()
        powerSepLabel:SetPoint("LEFT", hpSepLabel, "RIGHT", 120, 0)
    end
    if hpSepDrop and hpSepLabel then
        hpSepDrop:ClearAllPoints()
        -- Move both separator dropdowns down by 7px (relative to the prior -9 offset)
        hpSepDrop:SetPoint("TOPLEFT", hpSepLabel, "BOTTOMLEFT", -16, -16)
    end
    if powerSepDrop and powerSepLabel then
        powerSepDrop:ClearAllPoints()
        powerSepDrop:SetPoint("TOPLEFT", powerSepLabel, "BOTTOMLEFT", -16, -16)
    end
    if hpSpacerCheck and hpSepDrop then
        hpSpacerCheck:ClearAllPoints()
        hpSpacerCheck:SetPoint("TOPLEFT", hpSepDrop, "BOTTOMLEFT", 16, -14)
    end
    if hpSpacerSlider and hpSpacerCheck then
        hpSpacerSlider:ClearAllPoints()
        hpSpacerSlider:SetPoint("TOPLEFT", hpSpacerCheck, "BOTTOMLEFT", 0, -30)
        if hpSpacerSlider.SetWidth then hpSpacerSlider:SetWidth(260) end
    end
end
-- Keep the Bars tab toggles/controls visually in sync (same behavior as Fonts/Misc toggles)
local function MSUF_SyncBarsTabToggles()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local b = (MSUF_DB and MSUF_DB.bars) or {}
    local function SafeToggleUpdate(cb)
        if cb and cb.__msufToggleUpdate then pcall(cb.__msufToggleUpdate) end
     end
    local function SyncCB(cb, val)
        if cb then
            cb:SetChecked(val and true or false)
            SafeToggleUpdate(cb)
        end
     end
    local hpGradEnabled = (g.enableGradient ~= false)
    local powerGradEnabled = (g.enablePowerGradient ~= false)
    local gradEnabled = (hpGradEnabled or powerGradEnabled)
    SyncCB(gradientCheck, hpGradEnabled)
    SyncCB(powerGradientCheck, powerGradEnabled)
    if gradientDirPad then
        if gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end
        if gradientDirPad.SetEnabledVisual then gradientDirPad:SetEnabledVisual(gradEnabled) end
    end
    if gradientStrengthSlider then
        local v = tonumber(g.gradientStrength)
        if type(v) ~= "number" then v = 0.45 end
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        MSUF_SetLabeledSliderValue(gradientStrengthSlider, v)
        MSUF_SetLabeledSliderEnabled(gradientStrengthSlider, gradEnabled)
    end
    -- Bar outline thickness (0..6) should always show the current value in the editbox on open.
    if barOutlineThicknessSlider then
        local t = tonumber(b.barOutlineThickness)
        if type(t) ~= "number" then t = 1 end
        t = math.floor(t + 0.5)
        if t < 0 then t = 0 elseif t > 6 then t = 6 end
        MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t)
        MSUF_SetLabeledSliderEnabled(barOutlineThicknessSlider, true)
    -- Highlight border thickness (1..6) for aggro/dispel/purge overlay.
    if highlightBorderThicknessSlider then
        local ht = tonumber(g.highlightBorderThickness)
        if type(ht) ~= "number" then ht = 2 end
        ht = math.floor(ht + 0.5)
        if ht < 1 then ht = 1 elseif ht > 6 then ht = 6 end
        MSUF_SetLabeledSliderValue(highlightBorderThicknessSlider, ht)
        MSUF_SetLabeledSliderEnabled(highlightBorderThicknessSlider, true)
    end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local mode = g.aggroOutlineMode or 0
        local dd = _G["MSUF_AggroOutlineDropdown"]
        if dd then
            if mode == 1 then
                UIDropDownMenu_SetText(dd, TR("Aggro border on"))
            else
                UIDropDownMenu_SetText(dd, TR("Aggro border off"))
            end
        end

-- Dispel border dropdown
local dispelDrop = _G["MSUF_DispelOutlineDropdown"]
if dispelDrop then
	UIDropDownMenu_SetText(dispelDrop, TR("Dispel border off"))
	if (g.dispelOutlineMode or 0) == 1 then
		UIDropDownMenu_SetText(dispelDrop, TR("Dispel border on"))
	end
end

-- Purge border dropdown
local purgeDrop = _G["MSUF_PurgeOutlineDropdown"]
if purgeDrop then
	UIDropDownMenu_SetText(purgeDrop, TR("Purge border off"))
	if (g.purgeOutlineMode or 0) == 1 then
		UIDropDownMenu_SetText(purgeDrop, TR("Purge border on"))
	end
end

-- Highlight priority
local prioChk = _G["MSUF_HighlightPrioCheck"]
if prioChk then
	prioChk:SetChecked((g.highlightPrioEnabled or 0) == 1)
end
if type(_G.MSUF_PrioRows_Reinit) == "function" then
	_G.MSUF_PrioRows_Reinit()
end

    end
    SyncCB(targetPowerBarCheck, b.showTargetPowerBar)
    SyncCB(bossPowerBarCheck, b.showBossPowerBar)
    SyncCB(playerPowerBarCheck, b.showPlayerPowerBar)
    SyncCB(focusPowerBarCheck, b.showFocusPowerBar)
    SyncCB(powerBarEmbedCheck, b.embedPowerBarIntoHealth)
    SyncCB(powerBarBorderCheck, b.powerBarBorderEnabled)
    local anyPBEnabled = true
    if (b.showTargetPowerBar == false) and (b.showBossPowerBar == false) and (b.showPlayerPowerBar == false) and (b.showFocusPowerBar == false) then anyPBEnabled = false end
    local function SetControlEnabled(ctrl, enabled, wantTextColor)
        if not ctrl then  return end
        if enabled then
            if ctrl.Enable then ctrl:Enable() end
            if ctrl.SetEnabled then ctrl:SetEnabled(true) end
            if ctrl.EnableMouse then ctrl:EnableMouse(true) end
            if wantTextColor and ctrl.SetTextColor then ctrl:SetTextColor(1, 1, 1) end
            if ctrl.SetAlpha then ctrl:SetAlpha(1) end
        else
            if ctrl.Disable then ctrl:Disable() end
            if ctrl.SetEnabled then ctrl:SetEnabled(false) end
            if ctrl.EnableMouse then ctrl:EnableMouse(false) end
            if ctrl.ClearFocus then ctrl:ClearFocus() end
            if wantTextColor and ctrl.SetTextColor then ctrl:SetTextColor(0.55, 0.55, 0.55) end
            if ctrl.SetAlpha then ctrl:SetAlpha(0.55) end
        end
     end
    if powerBarHeightLabel and powerBarHeightLabel.SetTextColor then
        if anyPBEnabled then
            powerBarHeightLabel:SetTextColor(1, 1, 1, 1)
        else
            powerBarHeightLabel:SetTextColor(0.35, 0.35, 0.35, 1)
        end
    end
    SetControlEnabled(powerBarHeightEdit, anyPBEnabled, true)
    SetControlEnabled(powerBarEmbedCheck, anyPBEnabled, false)
    -- Power bar border controls: disabled if NO powerbars are enabled.
    local borderEnabled = (b.powerBarBorderEnabled == true)
    SetControlEnabled(powerBarBorderCheck, anyPBEnabled, false)
    if powerBarBorderSizeLabel and powerBarBorderSizeLabel.SetTextColor then
        if anyPBEnabled and borderEnabled then
            powerBarBorderSizeLabel:SetTextColor(1, 1, 1, 1)
        else
            powerBarBorderSizeLabel:SetTextColor(0.35, 0.35, 0.35, 1)
        end
    end
    SetControlEnabled(powerBarBorderSizeEdit, (anyPBEnabled and borderEnabled), true)
    -- Smooth power bar + realtime text toggles sync
    local smoothCB = _G["MSUF_SmoothPowerBarCheck"]
    if smoothCB then
        local sv = b.smoothPowerBar
        if sv == nil then sv = true end
        smoothCB:SetChecked(sv)
    end
    local rtCB = _G["MSUF_RealtimePowerTextCheck"]
    if rtCB then
        local rv = b.realtimePowerText
        if rv == nil then rv = true end
        rtCB:SetChecked(rv)
    end
 end
 MSUF_BarsMenu_QueueScrollUpdate()
if barGroup and barGroup.HookScript then barGroup:HookScript('OnShow', MSUF_SyncBarsTabToggles) end
MSUF_BarsApplyGradient = function()
    -- Live-apply gradient changes (HP + Power). No reload required.
    -- Ensure the strength isn't accidentally zeroed (old hidden slider could leave 0, making gradients look "dead").
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if (g.enableGradient ~= false) or (g.enablePowerGradient ~= false) then
        local s = tonumber(g.gradientStrength)
        if type(s) ~= "number" or s <= 0 then
            g.gradientStrength = 0.45
        end
    end
    if gradientDirPad and gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end
    -- Prefer immediate apply outside combat so visual changes (esp. gradients) show instantly.
    if InCombatLockdown and InCombatLockdown() then
        ApplyAllSettings()
    elseif type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then
        _G.MSUF_ApplyAllSettings_Immediate()
    else
        ApplyAllSettings()
    end
    -- Extra safety: force an immediate repaint of bars/gradients.
    -- Heavy-visual work is throttled; if we apply inside the throttle window and nothing else
    -- triggers a future update tick, gradients can appear to "only apply after /reload".
    local function ForceRepaintOnce()
        local frames = _G and _G.MSUF_UnitFrames
        if type(frames) ~= "table" then
            if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
             return
        end
        local upd = _G.UpdateSimpleUnitFrame
        local updPow = _G.MSUF_UFCore_UpdatePowerBarFast
        for _, f in pairs(frames) do
            if f and f.unit and f.hpBar then
                -- Bypass heavy-visual throttle for this apply.
                f._msufHeavyVisualNextAt = 0
                if type(upd) == "function" then
                    upd(f)
                elseif type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                    _G.MSUF_RequestUnitframeUpdate(f, true, false, "BarsApplyGradient", true)
                end
                if type(updPow) == "function" then
                    updPow(f)
                end
            end
        end
     end
    ForceRepaintOnce()
    -- One extra pass after the throttle window; coalesced so slider-drag doesn't queue dozens of timers.
    if C_Timer and C_Timer.After then
        if not _G.__MSUF_BARS_GRAD_REPAINT2 then
            _G.__MSUF_BARS_GRAD_REPAINT2 = true
            C_Timer.After(0.08, function()
                _G.__MSUF_BARS_GRAD_REPAINT2 = false
                ForceRepaintOnce()
             end)
        end
    end
 end
if _G and _G.MSUF_Options_BindDBBoolCheck then
    _G.MSUF_Options_BindDBBoolCheck(gradientCheck, "general.enableGradient", MSUF_BarsApplyGradient, MSUF_SyncBarsTabToggles)
    _G.MSUF_Options_BindDBBoolCheck(powerGradientCheck, "general.enablePowerGradient", MSUF_BarsApplyGradient, MSUF_SyncBarsTabToggles)
end
do
    local SIMPLE_BAR_SLIDERS = {
        {
            slider = gradientStrengthSlider,
            min = 0, max = 1,
            setDB = function(v)
                EnsureDB()
                MSUF_DB.general = MSUF_DB.general or {}
                MSUF_DB.general.gradientStrength = v
             end,
            apply = function()
                if type(MSUF_BarsApplyGradient) == "function" then
                    MSUF_BarsApplyGradient()
                else
                    ApplyAllSettings()
                end
             end,
        },
        {
            slider = barOutlineThicknessSlider,
            min = 0, max = 6, integer = true,
            setDB = function(v)
                EnsureDB()
                MSUF_DB.bars = MSUF_DB.bars or {}
                MSUF_DB.bars.barOutlineThickness = v
             end,
            apply = function()
                if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then
                    _G.MSUF_ApplyBarOutlineThickness_All()
                else
                    ApplyAllSettings()
                end
             end,
        },
    }
    local function Clamp(v, minV, maxV, asInt)
        v = tonumber(v) or minV
        if asInt then v = math.floor(v + 0.5) end
        if v < minV then v = minV end
        if v > maxV then v = maxV end
         return v
    end
    for _, spec in ipairs(SIMPLE_BAR_SLIDERS) do
        if spec.slider then
            spec.slider.onValueChanged = function(self, value)
                local v = Clamp(value, spec.min, spec.max, spec.integer)
                if spec.setDB then spec.setDB(v) end
                if spec.apply then spec.apply() end
             end
        end
    end
end
    if _G and _G.MSUF_Options_BindDBBoolCheck then
        local function Bind(cb, path, apply)
            if cb then _G.MSUF_Options_BindDBBoolCheck(cb, path, apply or ApplyAllSettings, MSUF_SyncBarsTabToggles) end
         end
        Bind(targetPowerBarCheck, "bars.showTargetPowerBar")
        Bind(bossPowerBarCheck,   "bars.showBossPowerBar")
        Bind(playerPowerBarCheck, "bars.showPlayerPowerBar")
        Bind(focusPowerBarCheck,  "bars.showFocusPowerBar")
        Bind(powerBarEmbedCheck, "bars.embedPowerBarIntoHealth", function()
            if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == 'function' then _G.MSUF_ApplyPowerBarEmbedLayout_All() end
            ApplyAllSettings()
         end)
        Bind(powerBarBorderCheck, "bars.powerBarBorderEnabled", function()
            if type(_G.MSUF_ApplyPowerBarBorder_All) == 'function' then
                _G.MSUF_ApplyPowerBarBorder_All()
            else
                ApplyAllSettings()
            end
         end)
    end
    if powerBarBorderSizeEdit then
        powerBarBorderSizeEdit:SetScript("OnEnterPressed", function(self)
            MSUF_UpdatePowerBarBorderSizeFromEdit(self)
            self:ClearFocus()
         end)
        powerBarBorderSizeEdit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
         end)
        powerBarBorderSizeEdit:SetScript("OnEditFocusLost", function(self)
            MSUF_UpdatePowerBarBorderSizeFromEdit(self)
         end)
    end
    if powerBarHeightEdit then
        powerBarHeightEdit:SetScript("OnEnterPressed", function(self)
            MSUF_UpdatePowerBarHeightFromEdit(self)
            self:ClearFocus()
         end)
        powerBarHeightEdit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
         end)
        powerBarHeightEdit:SetScript("OnEditFocusLost", function(self)
            MSUF_UpdatePowerBarHeightFromEdit(self)
         end)
    end
    -- -----------------------------------------------------------------
    -- Store bars-specific widgets on panel for LoadFromDB / SyncBarsTab
    -- -----------------------------------------------------------------
    panel.gradientCheck              = gradientCheck
    panel.powerGradientCheck         = powerGradientCheck
    panel.gradientDirPad             = gradientDirPad or _G["MSUF_GradientDirectionPad"]
    panel.targetPowerBarCheck        = targetPowerBarCheck
    panel.bossPowerBarCheck          = bossPowerBarCheck
    panel.playerPowerBarCheck        = playerPowerBarCheck
    panel.focusPowerBarCheck         = focusPowerBarCheck
    panel.powerBarHeightEdit         = powerBarHeightEdit
    panel.powerBarEmbedCheck         = powerBarEmbedCheck
    panel.powerBarBorderCheck        = powerBarBorderCheck
    panel.powerBarBorderSizeEdit     = powerBarBorderSizeEdit
    panel.hpModeDrop                 = hpModeDrop
    panel.barTextureDrop             = barTextureDrop
    panel.barOutlineThicknessSlider  = barOutlineThicknessSlider
    panel.highlightBorderThicknessSlider = highlightBorderThicknessSlider
    panel.aggroOutlineDrop           = aggroOutlineDrop
    panel.aggroTestCheck             = aggroTestCheck
    panel.dispelOutlineDrop          = dispelOutlineDrop
    panel.dispelTestCheck            = dispelTestCheck
    panel.purgeOutlineDrop           = purgeOutlineDrop
    panel.purgeTestCheck             = purgeTestCheck
    panel.prioCheck                  = prioCheck
    panel.updateThrottleSlider       = updateThrottleSlider
    panel.powerBarHeightSlider       = powerBarHeightSlider
    panel.infoTooltipDisableCheck    = infoTooltipDisableCheck
    -- Export gradient apply function to _G for GradientDirectionPad (stays in Core)
    if type(MSUF_BarsApplyGradient) == "function" then
        _G.MSUF_BarsApplyGradient = MSUF_BarsApplyGradient
    end
end -- ns.MSUF_Options_Bars_Build
