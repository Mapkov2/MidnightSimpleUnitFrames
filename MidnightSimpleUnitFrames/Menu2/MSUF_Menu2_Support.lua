-- MSUF2 support features split out of the legacy standalone slash menu.
-- Keep this file free of page/UI construction so the old SlashMenu file can be
-- removed from the TOC without losing shared runtime helpers.

local addonName, ns = ...
ns = ns or {}

local floor = math.floor
local abs = math.abs

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function Print(msg)
    if type(print) == "function" then
        print("|cff00ff00MSUF:|r " .. tostring(msg or ""))
    end
end

local function IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return true end
    return (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false
end

local function ShowConfigCombatLockMessage()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    else
        Print("Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.")
    end
end

local function BlockConfigCombatLocked(silent)
    if not IsConfigCombatLocked() then return false end
    if not silent then ShowConfigCombatLockMessage() end
    return true
end

local function EnsureGeneral()
    if type(_G.EnsureDB) == "function" then pcall(_G.EnsureDB) end
    _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
    _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
    return _G.MSUF_DB.general
end

local function AddTooltip(widget, title, body)
    if not (widget and widget.SetScript) then return end
    widget:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title and title ~= "" then _G.GameTooltip:SetText(title, 1, 1, 1) end
        if body and body ~= "" then _G.GameTooltip:AddLine(body, 0.80, 0.86, 1.00, true) end
        _G.GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
end

_G.MSUF_AddTooltip = _G.MSUF_AddTooltip or AddTooltip

local function LeftJustifyButtonText(btn, leftPad)
    leftPad = leftPad or 10
    if not (btn and btn.GetFontString) then return end
    local fontString = btn:GetFontString()
    if not fontString then return end
    if fontString.SetJustifyH then fontString:SetJustifyH("LEFT") end
    if fontString.ClearAllPoints and fontString.SetPoint then
        fontString:ClearAllPoints()
        fontString:SetPoint("LEFT", btn, "LEFT", leftPad, 0)
        fontString:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    end
end

_G.MSUF_LeftJustifyButtonText = _G.MSUF_LeftJustifyButtonText or LeftJustifyButtonText
_G.LeftJustify = _G.LeftJustify or LeftJustifyButtonText

local tips = {
    "Bigger steps: Hold SHIFT while adjusting sliders to change values faster.",
    "Fine tuning: Hold CTRL while adjusting sliders for smaller steps.",
    "Quick reset: If something feels off, try /msuf reset for frame positions.",
    "Factory reset: Use Menu > Advanced > Factory Reset or /msuf fullreset confirm + /reload.",
    "Edit Mode: Use Toggle Edit Mode to move frames quickly, then fine-tune with the position popup.",
    "Profiles safety: Create a new profile before big experiments so you can switch back instantly.",
    "Colors: The Colors tab lets you customize fonts, bars, castbars and highlights.",
    "Gameplay: The Gameplay tab contains extra UI tools and warnings you can enable or disable.",
    "Recommended: Sensei Resource Bar pairs well with MSUF for clean resource tracking.",
    "UI scale tip: MSUF has its own UI scale, separate from Blizzard global UI scale.",
    "Troubleshoot: If visuals do not update, a quick /reload fixes most UI state issues.",
    "Readability: Slightly larger fonts often help more than bigger frames.",
    "During development of MSUF Unhalted, R41z0r and other addon developers helped out.",
    "Danders is a strong Party/Raidframe addon and works well with MSUF.",
    "Community: If you like MSUF, share it with a friend.",
}

function _G.MSUF_GetNextTip()
    local g = EnsureGeneral()
    local count = #tips
    if count == 0 then return nil, 0, 0 end
    local index = tonumber(g.tipCycleIndex) or 1
    index = floor(index)
    if index < 1 or index > count then index = 1 end
    local tip = tips[index]
    local nextIndex = index + 1
    if nextIndex > count then nextIndex = 1 end
    g.tipCycleIndex = nextIndex
    return tip, index, count
end

local pendingReloadRecommendedLabel

function _G.MSUF_ShowReloadRecommendedPopup(label)
    if BlockConfigCombatLocked(false) then
        return
    end
    if not _G.StaticPopupDialogs then return end

    pendingReloadRecommendedLabel = tostring(label or "")
    if pendingReloadRecommendedLabel == "" then pendingReloadRecommendedLabel = "these changes" end

    if not _G.StaticPopupDialogs.MSUF_RELOAD_RECOMMENDED then
        _G.StaticPopupDialogs.MSUF_RELOAD_RECOMMENDED = {
            text = "MSUF recommends reloading the UI to ensure all changes apply correctly.\n\nApply: %s\n\nReload now?",
            button1 = _G.RELOAD or "Reload",
            button2 = _G.CANCEL or "Not now",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function()
                pendingReloadRecommendedLabel = nil
                if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
            end,
            OnCancel = function()
                pendingReloadRecommendedLabel = nil
            end,
        }
    end

    _G.StaticPopup_Show("MSUF_RELOAD_RECOMMENDED", pendingReloadRecommendedLabel)
end

local copyLinkPopup

local function EnsureCopyLinkPopup()
    if copyLinkPopup then return copyLinkPopup end
    if not _G.CreateFrame then return nil end

    local frame = _G.CreateFrame("Frame", "MSUF_CopyLinkPopup", _G.UIParent, "BackdropTemplate")
    frame:SetSize(420, 150)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.90)
        frame:SetBackdropBorderColor(0.10, 0.10, 0.10, 0.90)
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("Link")
    frame._msufTitleFS = title

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText("Press Ctrl+C to copy:")
    hint:SetTextColor(0.90, 0.90, 0.90, 1)

    local editBox = _G.CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(360, 32)
    editBox:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    if editBox.SetTextInsets then editBox:SetTextInsets(8, 8, 0, 0) end
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnEnterPressed", function() frame:Hide() end)
    frame._msufEditBox = editBox

    local ok = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ok:SetSize(120, 24)
    ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    ok:SetText(_G.OKAY or "Okay")
    ok:SetScript("OnClick", function() frame:Hide() end)
    if type(_G.MSUF_SkinButton) == "function" then pcall(_G.MSUF_SkinButton, ok) end

    frame:SetScript("OnShow", function(self)
        if self._msufTitleFS then self._msufTitleFS:SetText(self._msufTitle or "Link") end
        if self._msufEditBox then
            self._msufEditBox:SetText(self._msufUrl or "")
            self._msufEditBox:HighlightText()
            self._msufEditBox:SetFocus()
        end
    end)
    frame:SetScript("OnHide", function(self)
        if self._msufEditBox then
            self._msufEditBox:SetText("")
            self._msufEditBox:ClearFocus()
        end
        self._msufTitle = nil
        self._msufUrl = nil
    end)
    frame:Hide()

    copyLinkPopup = frame
    return frame
end

function _G.MSUF_ShowCopyLink(title, url)
    local frame = EnsureCopyLinkPopup()
    if not frame then return end
    frame._msufTitle = tostring(title or "Link")
    frame._msufUrl = tostring(url or "")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    frame:Show()
    if frame.Raise then frame:Raise() end
end

do
    local version = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
        and _G.C_AddOns.GetAddOnMetadata(addonName or "MidnightSimpleUnitFrames", "Version")
    local isAlpha = type(version) == "string" and version:lower():find("alpha", 1, true) ~= nil
    if isAlpha and _G.StaticPopupDialogs and not _G.StaticPopupDialogs.MSUF_ALPHA_DISCORD then
        _G.StaticPopupDialogs.MSUF_ALPHA_DISCORD = {
            text = "|cffb088f0MSUF Alpha Build|r\n\nThis is an early Alpha version.\nPlease report bugs and share feedback on our Discord!\n\n|cff7289dahttps://discord.gg/JQnhZXnTAK|r",
            button1 = "Copy Discord Link",
            button2 = _G.CLOSE or "Close",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function()
                if type(_G.MSUF_ShowCopyLink) == "function" then
                    _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/JQnhZXnTAK")
                end
            end,
        }
    end
end

local pendingMsufScale
local pendingGlobalScale
local pendingDisableScaling
local pendingReloadOnScalingOff
local scaleApplyWatcher
local lastGlobalUiParentScale
local blizzardUiParentScale

local UI_SCALE_1080 = 768 / 1080
local UI_SCALE_1440 = 768 / 1440
local UI_SCALE_4K = 768 / 2160

local function IsGroupFrameUnitKey(unitKey)
    if type(unitKey) ~= "string" then return false end
    return unitKey:sub(1, 5) == "party" or unitKey:sub(1, 4) == "raid"
end

local function IsGroupFrameScaleEnabled(frame, unitKey)
    if not (frame and (frame._msufGFBuilt or frame._msufGFKind or IsGroupFrameUnitKey(unitKey))) then
        return true
    end

    local kind = frame._msufGFKind
    if not kind and IsGroupFrameUnitKey(unitKey) then
        kind = unitKey:sub(1, 4) == "raid" and "raid" or "party"
    end

    local gf = ns and ns.GF
    local conf = gf and type(gf.GetConf) == "function" and gf.GetConf(kind) or nil
    local mode = conf and conf.frameScaleMode or "off"
    return mode == "manual" or mode == "auto"
end

local function CollectMsufScaleFrames()
    local frames, seen = {}, {}
    local function add(frame, unitKey)
        if not frame or seen[frame] then return end
        if not IsGroupFrameScaleEnabled(frame, unitKey) then return end
        if type(frame) == "table" and type(frame.SetScale) == "function" then
            seen[frame] = true
            frames[#frames + 1] = frame
        end
    end

    if type(_G.MSUF_UnitFrames) == "table" then
        for unitKey, frame in pairs(_G.MSUF_UnitFrames) do add(frame, unitKey) end
    end
    add(_G.MSUF_PlayerCastbar)
    add(_G.MSUF_TargetCastbar)
    add(_G.MSUF_FocusCastbar)
    add(_G.MSUF_PlayerCastbarPreview)
    add(_G.MSUF_TargetCastbarPreview)
    add(_G.MSUF_FocusCastbarPreview)
    add(_G.MSUF_BossCastbar)
    add(_G.MSUF_BossCastbarPreview)
    return frames
end

local function GetSavedMsufScale()
    local g = EnsureGeneral()
    return Clamp(tonumber(g.msufUiScale) or tonumber(g.uiScale) or 1, 0.25, 1.5)
end

local function ScheduleUnitframeReanchorAfterScale()
    if _G.MSUF_ScaleReanchorPending then return end
    _G.MSUF_ScaleReanchorPending = true

    local function flush()
        _G.MSUF_ScaleReanchorPending = false
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            if type(_G.MSUF_RequestUnitFrameReanchorAfterCombat) == "function" then
                _G.MSUF_RequestUnitFrameReanchorAfterCombat()
            end
            return
        end
        if type(_G.MSUF_UpdateAllExternalAnchorProxies) == "function" then
            _G.MSUF_UpdateAllExternalAnchorProxies()
        end
        if type(_G.MSUF_ForceReanchorAllUnitFrames_Once) == "function" then
            local previous = _G.MSUF_ExternalAnchorForceReanchor
            _G.MSUF_ExternalAnchorForceReanchor = true
            pcall(_G.MSUF_ForceReanchorAllUnitFrames_Once, true)
            _G.MSUF_ExternalAnchorForceReanchor = previous
        end
    end

    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, flush) else flush() end
end

local EnsureScaleApplyAfterCombat
local ResetGlobalUiScale

local function ApplyMsufScale(scale)
    scale = tonumber(scale)
    if not scale then return end
    scale = Clamp(scale, 0.25, 1.5)

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingMsufScale = scale
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        return
    end

    local frames = CollectMsufScaleFrames()
    for i = 1, #frames do
        pcall(frames[i].SetScale, frames[i], scale)
    end
    ScheduleUnitframeReanchorAfterScale()
end

local function GetCurrentGlobalUiScale()
    if _G.UIParent and _G.UIParent.GetScale then return tonumber(_G.UIParent:GetScale()) end
    return nil
end

local function GetPixelPerfectScale()
    if type(_G.GetPhysicalScreenSize) == "function" then
        local _, height = _G.GetPhysicalScreenSize()
        height = tonumber(height)
        if height and height > 0 then return Clamp(768 / height, 0.3, 2.0) end
    end
    return UI_SCALE_1440
end

local function ResolveGlobalPresetScale(preset, scale)
    if preset == "1080p" then return UI_SCALE_1080 end
    if preset == "1440p" then return UI_SCALE_1440 end
    if preset == "4k" then return UI_SCALE_4K end
    if preset == "pixel" then return GetPixelPerfectScale() end
    return tonumber(scale)
end

local function EnsureGlobalUiScaleTable(g)
    if not g then return nil end
    local ui = type(g.UIScale) == "table" and g.UIScale or nil
    if not ui then
        ui = {}
        g.UIScale = ui
        local preset = g.globalUiScalePreset
        local scale = ResolveGlobalPresetScale(preset, g.globalUiScaleValue) or 1.0
        ui.Enabled = preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom"
        ui.Scale = scale
        ui._migratedFromGlobalPreset_v1 = true
    end
    if ui.Enabled == nil then
        local preset = g.globalUiScalePreset
        ui.Enabled = preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom"
    end
    ui.Enabled = ui.Enabled == true
    ui.Scale = Clamp(tonumber(ui.Scale) or ResolveGlobalPresetScale(g.globalUiScalePreset, g.globalUiScaleValue) or 1.0, 0.3, 1.5)
    g.disableScaling = false
    return ui
end

local function SetGlobalUiScaleState(enabled, scale, preset)
    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    if not ui then return end

    enabled = enabled == true
    ui.Enabled = enabled
    if scale ~= nil then ui.Scale = Clamp(tonumber(scale) or ui.Scale or 1.0, 0.3, 1.5) end

    if enabled then
        g.globalUiScalePreset = preset or g.globalUiScalePreset or "custom"
        g.globalUiScaleValue = ui.Scale
    else
        g.globalUiScalePreset = preset or "auto"
        g.globalUiScaleValue = nil
    end
end

local function CaptureBlizzardUiScale()
    if blizzardUiParentScale then return end
    local current = GetCurrentGlobalUiScale()
    if current and current > 0 then blizzardUiParentScale = current end
end

local function GetBlizzardCVarScale()
    local useUiScale
    if type(_G.GetCVarBool) == "function" then
        local ok, value = pcall(_G.GetCVarBool, "useUiScale")
        if ok then useUiScale = value end
    end
    if useUiScale == nil and type(_G.GetCVar) == "function" then
        local ok, value = pcall(_G.GetCVar, "useUiScale")
        if ok then useUiScale = tostring(value) == "1" end
    end
    if useUiScale and type(_G.GetCVar) == "function" then
        local ok, value = pcall(_G.GetCVar, "uiScale")
        value = ok and tonumber(value) or nil
        if value and value > 0 then return Clamp(value, 0.3, 2.0) end
    end
    if type(_G.GetPhysicalScreenSize) == "function" then
        local _, height = _G.GetPhysicalScreenSize()
        height = tonumber(height)
        if height and height > 0 then return Clamp(768 / height, 0.3, 2.0) end
    end
    if blizzardUiParentScale and blizzardUiParentScale > 0 then
        return Clamp(blizzardUiParentScale, 0.3, 2.0)
    end
    return nil
end

local function RestoreBlizzardUiScaleOnce()
    if type(_G.UIParent_UpdateScale) == "function" then
        local ok = pcall(_G.UIParent_UpdateScale)
        if ok then return true end
    end
    local scale = GetBlizzardCVarScale()
    if scale and _G.UIParent and _G.UIParent.SetScale then
        pcall(_G.UIParent.SetScale, _G.UIParent, scale)
        return true
    end
    return false
end

local function RestoreBlizzardUiScale(silent)
    if BlockConfigCombatLocked(silent) then
        return false
    end

    RestoreBlizzardUiScaleOnce()
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, RestoreBlizzardUiScaleOnce)
        _G.C_Timer.After(0.25, RestoreBlizzardUiScaleOnce)
        _G.C_Timer.After(1.0, RestoreBlizzardUiScaleOnce)
    end
    lastGlobalUiParentScale = nil
    if not silent then Print("Global UI scale restored to Blizzard settings.") end
    return true
end

local function WriteBlizzardUiScaleCVar(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return false end
    scale = Clamp(scale, 0.3, 1.5)
    local value = string.format("%.6f", scale)
    local ok = false
    if _G.C_CVar and type(_G.C_CVar.SetCVar) == "function" then
        pcall(_G.C_CVar.SetCVar, "useUiScale", "1")
        pcall(_G.C_CVar.SetCVar, "uiScale", value)
        ok = true
    end
    if type(_G.SetCVar) == "function" then
        pcall(_G.SetCVar, "useUiScale", "1")
        pcall(_G.SetCVar, "uiScale", value)
        ok = true
    end
    return ok
end

local function GetGlobalUiScaleHandoffValue(g, ui)
    local current = tonumber(GetCurrentGlobalUiScale())
    if current and current > 0 then return Clamp(current, 0.3, 1.5) end
    if not ui and g then ui = EnsureGlobalUiScaleTable(g) end
    local saved = ui and tonumber(ui.Scale)
    if saved and saved > 0 then return Clamp(saved, 0.3, 1.5) end
    if lastGlobalUiParentScale and lastGlobalUiParentScale > 0 then return Clamp(lastGlobalUiParentScale, 0.3, 1.5) end
    return 1.0
end

local function HandOffGlobalUiScaleToBlizzard(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return false end
    scale = Clamp(scale, 0.3, 1.5)
    WriteBlizzardUiScaleCVar(scale)
    if type(_G.UIParent_UpdateScale) == "function" then pcall(_G.UIParent_UpdateScale) end
    if _G.UIParent and _G.UIParent.SetScale then pcall(_G.UIParent.SetScale, _G.UIParent, scale) end
    blizzardUiParentScale = scale
    lastGlobalUiParentScale = nil
    return true
end

local function EnforceUIParentScale(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = Clamp(scale, 0.3, 1.5)
    if not (_G.UIParent and _G.UIParent.SetScale) then return end

    local current = _G.UIParent.GetScale and tonumber(_G.UIParent:GetScale()) or 0
    if abs((current or 0) - scale) > 0.001 then
        pcall(_G.UIParent.SetScale, _G.UIParent, scale)
    end
    lastGlobalUiParentScale = scale
end

local function SetGlobalUiScale(scale, silent)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = Clamp(scale, 0.3, 1.5)

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingGlobalScale = scale
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return
    end

    CaptureBlizzardUiScale()
    EnforceUIParentScale(scale)
    ScheduleUnitframeReanchorAfterScale()
    if not silent then Print(string.format("Global UI scale set to %.4f", scale)) end
end

ResetGlobalUiScale = function(silent)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingDisableScaling = true
        pendingGlobalScale = nil
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return false
    end

    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    local handoff = GetGlobalUiScaleHandoffValue(g, ui)
    HandOffGlobalUiScaleToBlizzard(handoff)
    SetGlobalUiScaleState(false, nil, "auto")
    pendingGlobalScale = nil
    if not silent then
        Print(string.format("Global UI scale disabled. Blizzard UI scale kept at %d%%.", floor(handoff * 100 + 0.5)))
    end
    ScheduleUnitframeReanchorAfterScale()
    return true
end

EnsureScaleApplyAfterCombat = function()
    if scaleApplyWatcher or not _G.CreateFrame then return end
    local frame = _G.CreateFrame("Frame")
    scaleApplyWatcher = frame
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        if _G.InCombatLockdown and _G.InCombatLockdown() then return end

        if pendingDisableScaling then
            pendingDisableScaling = nil
            pendingGlobalScale = nil
            ResetGlobalUiScale(true)
        else
            local msufScale = pendingMsufScale
            local globalScale = pendingGlobalScale
            pendingMsufScale = nil
            pendingGlobalScale = nil
            if msufScale then ApplyMsufScale(msufScale) end
            if globalScale then SetGlobalUiScale(globalScale, true) end
        end

        if pendingReloadOnScalingOff then
            pendingReloadOnScalingOff = nil
            if type(_G.ReloadUI) == "function" then
                _G.ReloadUI()
                return
            end
        end

        if not pendingDisableScaling and not pendingMsufScale and not pendingGlobalScale then
            frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            frame:SetScript("OnEvent", nil)
            scaleApplyWatcher = nil
        end
    end)
end

local function SetScalingDisabled(disable, silent)
    local g = EnsureGeneral()
    disable = disable == true
    g.disableScaling = false
    if not disable then
        pendingDisableScaling = nil
        return
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        pendingDisableScaling = true
        if EnsureScaleApplyAfterCombat then EnsureScaleApplyAfterCombat() end
        if not silent then ShowConfigCombatLockMessage() end
        return
    end
    ResetGlobalUiScale(true)
    pendingDisableScaling = nil
    pendingGlobalScale = nil
    if not silent then Print("Global UI scale disabled. Blizzard keeps the current UI size.") end
end

local function GetDesiredGlobalScaleFromDB()
    local g = EnsureGeneral()
    local ui = EnsureGlobalUiScaleTable(g)
    if ui and ui.Enabled then return tonumber(ui.Scale) end
    return nil
end

local function EnsureGlobalUiScaleApplied(silent)
    local want = tonumber(GetDesiredGlobalScaleFromDB())
    if want and want > 0 then SetGlobalUiScale(want, silent) end
end

local function ResetStandaloneWindowGeometry(frame, silent)
    local g = EnsureGeneral()
    g.flashFullW = 900
    g.flashFullH = 700
    g.flashFullPoint = "CENTER"
    g.flashFullRelPoint = "CENTER"
    g.flashFullX = -60
    g.flashFullY = 10
    local uiScale = (_G.UIParent and _G.UIParent.GetScale and _G.UIParent:GetScale()) or 1
    if not uiScale or uiScale == 0 then uiScale = 1 end
    g.flashFullXpx = -60 * uiScale
    g.flashFullYpx = 10 * uiScale
    g.msuf2WindowW = 900
    g.msuf2WindowH = 700
    g.slashMenuScale = 1.0

    local win = frame or _G.MSUF_StandaloneOptionsWindow or (_G.MSUF2 and _G.MSUF2.frame)
    if win then
        local scale = 1.0
        if _G.MSUF2 and type(_G.MSUF2.GetEffectiveMenuScale) == "function" then
            scale = _G.MSUF2.GetEffectiveMenuScale(1.0)
        end
        if win.SetScale then pcall(win.SetScale, win, scale) end
        if win.SetSize then pcall(win.SetSize, win, 900, 700) end
        if win.ClearAllPoints then pcall(win.ClearAllPoints, win) end
        if win.SetPoint then pcall(win.SetPoint, win, "CENTER", _G.UIParent, "CENTER", -60, 10) end
    end
    if not silent then Print("MSUF menu size reset to default.") end
end

_G.MSUF_ApplyMsufScale = ApplyMsufScale
_G.MSUF_GetSavedMsufScale = GetSavedMsufScale
_G.MSUF_SetScalingDisabled = SetScalingDisabled
if type(_G.MSUF_SetGlobalUiScale_GATED) == "function" then
    _G.MSUF_SetGlobalUiScale_RAW = SetGlobalUiScale
    _G.MSUF_SetGlobalUiScale = _G.MSUF_SetGlobalUiScale_GATED
else
    _G.MSUF_SetGlobalUiScale = SetGlobalUiScale
end
_G.MSUF_ResetGlobalUiScale = ResetGlobalUiScale
_G.MSUF_RestoreBlizzardUiScale = RestoreBlizzardUiScale
_G.MSUF_ResetStandaloneWindowGeometry = ResetStandaloneWindowGeometry
_G.MSUF_GetPixelPerfectScale = GetPixelPerfectScale

if type(_G.MSUF_InstallGlobalScaleGate) == "function" then
    _G.MSUF_InstallGlobalScaleGate()
end

local function ApplySavedScaleState(applyGlobalCVar)
    ApplyMsufScale(GetSavedMsufScale())
    local want = GetDesiredGlobalScaleFromDB()
    if want then
        if applyGlobalCVar then SetGlobalUiScale(want, true) end
        EnsureGlobalUiScaleApplied(true)
    end
end

local startupScaleApplyQueued
local startupScaleNeedsGlobalCVar
local function QueueStartupScaleApply(applyGlobalCVar)
    startupScaleNeedsGlobalCVar = startupScaleNeedsGlobalCVar or applyGlobalCVar == true
    if startupScaleApplyQueued then return end
    startupScaleApplyQueued = true

    local function flush()
        local needsGlobalCVar = startupScaleNeedsGlobalCVar
        startupScaleApplyQueued = nil
        startupScaleNeedsGlobalCVar = nil
        ApplySavedScaleState(needsGlobalCVar)
    end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, flush)
    else
        flush()
    end
end

local scaleEvents = _G.CreateFrame and _G.CreateFrame("Frame")
if scaleEvents then
    scaleEvents:RegisterEvent("PLAYER_LOGIN")
    scaleEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleEvents:SetScript("OnEvent", function(_, event)
        if event == "DISPLAY_SIZE_CHANGED" then
            ApplySavedScaleState(false)
        else
            QueueStartupScaleApply(event == "PLAYER_LOGIN")
        end
    end)
end

if _G.C_Timer and _G.C_Timer.After then
    QueueStartupScaleApply(true)
end
