local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local CallGlobal = AP.CallGlobal
local DB = AP.DB
local G = AP.G
local Bars = AP.Bars
local Gameplay = AP.Gameplay
local BoolValue = AP.BoolValue
local NumValue = AP.NumValue
local SetValue = AP.SetValue
local DeepCopyTable = AP.DeepCopyTable
local BindTableToggle = AP.BindTableToggle
local BindTableSlider = AP.BindTableSlider
local BindTableDropdown = AP.BindTableDropdown
local BindValueDropdown = AP.BindValueDropdown
local ReadRGB = AP.ReadRGB
local WriteRGB = AP.WriteRGB
local BindTableColor = AP.BindTableColor
local BindSeparateRGB = AP.BindSeparateRGB
local ApplyAuras = AP.ApplyAuras
local MoveWidget = W.MoveWidget or AP.MoveWidget
local LabelAt = AP.LabelAt
local DividerAt = AP.DividerAt
local BindValueToggle = AP.BindValueToggle
local BindValueSlider = AP.BindValueSlider
local ToggleAt = AP.ToggleAt
local ValueToggleAt = AP.ValueToggleAt
local SliderAt = AP.SliderAt
local ValueSliderAt = AP.ValueSliderAt
local DropdownAt = AP.DropdownAt
local ValueDropdownAt = AP.ValueDropdownAt
local ColorAt = AP.ColorAt
local ScopedToggleAt = AP.ScopedToggleAt
local ScopedSliderAt = AP.ScopedSliderAt
local ScopedDropdownAt = AP.ScopedDropdownAt
local TogglePillAt = AP.TogglePillAt
local SetControlEnabled = AP.SetControlEnabled
local function ApplyClassPower()
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    M.RequestGeneralApply("MSUF2_CLASSPOWER", { preview = true, applyAll = false })
end

local function ShowClassPowerReloadPrompt()
    if _G.StaticPopupDialogs and not _G.StaticPopupDialogs["MSUF_CLASSPOWER_ENABLE_RELOAD"] then
        _G.StaticPopupDialogs["MSUF_CLASSPOWER_ENABLE_RELOAD"] = {
            text = "Class Resources were enabled or disabled.\n\nA UI reload is required to fully apply this change.\n\nReload now?",
            button1 = RELOADUI,
            button2 = CANCEL,
            OnAccept = function() if ReloadUI then ReloadUI() end end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    if StaticPopup_Show then StaticPopup_Show("MSUF_CLASSPOWER_ENABLE_RELOAD") end
end

local function TextureValues(followText)
    local ui = ns and ns.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then
        return ui.StatusBarTextureItems(followText)
    end
    local out = {}
    if followText then out[#out + 1] = { value = "", text = followText } end
    for _, name in ipairs({ "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills", "Outline" }) do
        out[#out + 1] = { value = name, text = name }
    end
    return out
end

local function BindBarsAlphaPercent(ctx, section, label, key, default, apply, step)
    local slider = W.Slider(section, label, 0, 100, step or 5, 300)
    M.BindSlider(ctx, slider,
        function()
            local value = NumValue(Bars(), key, default or 0)
            if value <= 1 then value = value * 100 end
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            return floor(value + 0.5)
        end,
        function(v)
            v = tonumber(v) or ((default or 0) * 100)
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            SetValue(Bars(), key, v / 100, apply)
        end)
    return slider
end

local function ApplyDetachedPowerBar()
    CallGlobal("MSUF_DetachedPowerBar_RefreshTextures")
    CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    M.RequestGeneralApply("MSUF2_DETACHED_POWER_BAR", { preview = true, power = true, applyAll = false })
end

local function ApplyDetachedPowerBarOutline()
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    ApplyDetachedPowerBar()
end

local function IsMSUFEditModeActive()
    if type(_G.MSUF_IsMSUFEditModeActive) == "function" then return _G.MSUF_IsMSUFEditModeActive() and true or false end
    local st = _G.MSUF_EditState
    if type(st) == "table" and st.active ~= nil then return st.active == true end
    local em2 = _G.MSUF_EM2
    if em2 and em2.State and type(em2.State.IsActive) == "function" then return em2.State.IsActive() and true or false end
    return _G.MSUF_UnitEditModeActive == true
end

local function IsEditModeCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local QUICK_SETUP_FLAG = "quickSetupClassBarOffered"
local QUICK_CP_HEIGHT = 4
local QUICK_DPB_HEIGHT = 6
local QUICK_DPB_GAP = 2
local QUICK_CDM_GAP = 2
local QUICK_FALLBACK_Y_FRAC = 0.60

local QUICK_BARS_KEYS = {
    "showClassPower",
    "classPowerShowText",
    "classPowerAnchorToCooldown",
    "classPowerWidthMode",
    "showEleMaelstrom",
    "showEbonMight",
    "showChargedComboPoints",
    "runeShowTime",
    "runeShowTimeText",
    "classPowerOffsetX",
    "classPowerOffsetY",
    "classPowerOutline",
    "detachedPowerBarWidthMode",
    "detachedPowerBarOutline",
}

local QUICK_PLAYER_KEYS = {
    "powerBarDetached",
    "detachedPowerBarSyncClassPower",
    "detachedPowerBarAnchorToClassPower",
    "detachedPowerBarTextOnBar",
    "detachedPowerBarOffsetX",
    "detachedPowerBarOffsetY",
    "hpPowerTextOverride",
    "hpTextMode",
    "textLeft",
    "textCenter",
    "textRight",
    "powerTextMode",
    "powerTextLeft",
    "powerTextCenter",
    "powerTextRight",
    "hpTextSeparator",
    "powerTextSeparator",
    "absorbTextMode",
    "absorbAnchorMode",
}

local quickSetupUndoSnapshot
local quickSetupFirstRunChecked = false

local function QuickTr(text)
    return (M.Tr and M.Tr(text)) or text
end

local function QuickCopyValue(value)
    if type(value) ~= "table" then return value end
    if type(DeepCopyTable) == "function" then return DeepCopyTable(value) end
    if type(CopyTable) == "function" then return CopyTable(value) end
    local out = {}
    for k, v in pairs(value) do out[k] = QuickCopyValue(v) end
    return out
end

local function QuickSnapshot()
    local db = M.EnsureDB()
    local snap = { bars = {}, player = {} }
    local bars = db.bars or {}
    local player = db.player or {}
    for i = 1, #QUICK_BARS_KEYS do
        local key = QUICK_BARS_KEYS[i]
        snap.bars[key] = QuickCopyValue(bars[key])
    end
    for i = 1, #QUICK_PLAYER_KEYS do
        local key = QUICK_PLAYER_KEYS[i]
        snap.player[key] = QuickCopyValue(player[key])
    end
    return snap
end

local function QuickRestore(snap)
    if type(snap) ~= "table" then return end
    local db = M.EnsureDB()
    db.bars = db.bars or {}
    db.player = db.player or {}
    if type(snap.bars) == "table" then
        for i = 1, #QUICK_BARS_KEYS do
            local key = QUICK_BARS_KEYS[i]
            db.bars[key] = QuickCopyValue(snap.bars[key])
        end
    end
    if type(snap.player) == "table" then
        for i = 1, #QUICK_PLAYER_KEYS do
            local key = QUICK_PLAYER_KEYS[i]
            db.player[key] = QuickCopyValue(snap.player[key])
        end
    end
end

local function QuickGetVisibleCDM()
    local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer"))
        or _G.EssentialCooldownViewer
    if ecv and ecv.IsShown and ecv:IsShown() and ecv.GetHeight and ecv.GetCenter then
        local h = ecv:GetHeight()
        if type(h) == "number" and h > 0 then return ecv end
    end
    return nil
end

local function QuickPlayerFrame()
    return (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player) or _G.MSUF_player
end

local function QuickClassPowerVisible()
    local c = _G.MSUF_ClassPowerContainer
    return c and c.IsShown and c:IsShown()
end

local function QuickCalcCPAboveCDM(ecv)
    local bars = Bars()
    local player = M.EnsureDB().player or {}
    local cpH = tonumber(bars.classPowerHeight) or QUICK_CP_HEIGHT
    local dpbH = tonumber(player.detachedPowerBarHeight) or QUICK_DPB_HEIGHT
    local ecvH = (ecv and ecv.GetHeight and ecv:GetHeight()) or 0
    return {
        cpOffsetX = 0,
        cpOffsetY = math.ceil(ecvH + QUICK_CDM_GAP + cpH + QUICK_DPB_GAP + dpbH),
        dpbOffsetX = 0,
        dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = true,
        anchorDPBtoCP = true,
    }
end

local function QuickCalcDPBAboveCDMNoCP(ecv)
    local player = M.EnsureDB().player or {}
    local dpbH = tonumber(player.detachedPowerBarHeight) or QUICK_DPB_HEIGHT
    local fallback = {
        cpOffsetX = 0, cpOffsetY = 0,
        dpbOffsetX = 0, dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = true, anchorDPBtoCP = true,
    }
    local pf = QuickPlayerFrame()
    if not (pf and pf.GetLeft and pf.GetBottom and pf.GetEffectiveScale and ecv and ecv.GetCenter and ecv.GetTop and ecv.GetWidth) then
        return fallback
    end
    local pfLeft, pfBottom = pf:GetLeft(), pf:GetBottom()
    if not (pfLeft and pfBottom) then return fallback end
    local pfScale = (pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
    local ecvScale = (ecv.GetEffectiveScale and ecv:GetEffectiveScale()) or 1
    if pfScale <= 0 then pfScale = 1 end
    if ecvScale <= 0 then ecvScale = 1 end

    local ecvCenterX = (select(1, ecv:GetCenter()) or 0) * ecvScale
    local ecvTop = (ecv:GetTop() or 0) * ecvScale
    local ecvWidth = (ecv:GetWidth() or 200) * ecvScale
    local targetLeft = ecvCenterX - (ecvWidth * 0.5)
    local targetTop = ecvTop + QUICK_CDM_GAP * pfScale + dpbH * pfScale

    return {
        cpOffsetX = 0,
        cpOffsetY = 0,
        dpbOffsetX = floor((targetLeft - pfLeft * pfScale) / pfScale + 0.5),
        dpbOffsetY = floor((targetTop - pfBottom * pfScale) / pfScale + 0.5),
        anchorCPtoCDM = true,
        anchorDPBtoCP = false,
    }
end

local function QuickCalcScreenCenter()
    local fallback = {
        cpOffsetX = 0, cpOffsetY = 0,
        dpbOffsetX = 0, dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = false, anchorDPBtoCP = true,
    }
    local pf = QuickPlayerFrame()
    if not (pf and pf.GetLeft and pf.GetTop and pf.GetWidth and pf.GetEffectiveScale) then return fallback end
    local pfLeft, pfTop, pfW = pf:GetLeft(), pf:GetTop(), pf:GetWidth()
    if not (pfLeft and pfTop and pfW) then return fallback end
    local pfScale = (pf:GetEffectiveScale()) or 1
    if pfScale <= 0 then pfScale = 1 end
    local uip = UIParent
    local uipScale = (uip and uip.GetEffectiveScale and uip:GetEffectiveScale()) or 1
    if uipScale <= 0 then uipScale = 1 end
    local screenW = (uip and uip.GetWidth and uip:GetWidth()) or 1920
    local screenH = (uip and uip.GetHeight and uip:GetHeight()) or 1080
    local cpW = floor((pfW or 275) + 0.5)
    if cpW < 30 then cpW = 275 end
    return {
        cpOffsetX = floor((screenW * uipScale * 0.5) / pfScale - pfLeft - 2 - cpW * 0.5 + 0.5),
        cpOffsetY = floor((screenH * uipScale * QUICK_FALLBACK_Y_FRAC) / pfScale - pfTop + 2 + 0.5),
        dpbOffsetX = 0,
        dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = false,
        anchorDPBtoCP = true,
    }
end

local function QuickApplyPhase1(offsets)
    local db = M.EnsureDB()
    db.bars = db.bars or {}
    db.player = db.player or {}
    local bars = db.bars
    local player = db.player
    local general = db.general or {}

    bars.showClassPower = true
    bars.classPowerShowText = true
    bars.classPowerAnchorToCooldown = offsets.anchorCPtoCDM and true or false
    bars.classPowerWidthMode = "cooldown"
    bars.detachedPowerBarWidthMode = "cooldown"
    bars.showEleMaelstrom = true
    bars.showEbonMight = true
    bars.showChargedComboPoints = true
    bars.runeShowTime = true
    bars.runeShowTimeText = true
    bars.classPowerOffsetX = offsets.cpOffsetX
    bars.classPowerOffsetY = offsets.cpOffsetY
    bars.classPowerOutline = 1
    bars.detachedPowerBarOutline = 1

    player.powerBarDetached = true
    player.detachedPowerBarSyncClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarTextOnBar = true
    player.detachedPowerBarOffsetX = offsets.dpbOffsetX
    player.detachedPowerBarOffsetY = offsets.dpbOffsetY
    player.hpPowerTextOverride = true

    if player.hpTextMode == nil then player.hpTextMode = general.hpTextMode end
    if player.powerTextMode == nil then player.powerTextMode = general.powerTextMode end
    if player.textLeft == nil and player.textCenter == nil and player.textRight == nil then
        player.textLeft = "NONE"
        player.textCenter = "NONE"
        player.textRight = player.hpTextMode or general.hpTextMode or "CURPERCENT"
    end
    if player.powerTextLeft == nil and player.powerTextCenter == nil and player.powerTextRight == nil then
        player.powerTextLeft = "NONE"
        player.powerTextCenter = "NONE"
        player.powerTextRight = player.powerTextMode or general.powerTextMode or "CURPERCENT"
    end
    if player.hpTextSeparator == nil then player.hpTextSeparator = general.hpTextSeparator end
    if player.powerTextSeparator == nil then player.powerTextSeparator = general.powerTextSeparator or general.hpTextSeparator end
    if player.absorbTextMode == nil then player.absorbTextMode = general.absorbTextMode end
    if player.absorbAnchorMode == nil then player.absorbAnchorMode = general.absorbAnchorMode end
    player.powerTextMode = "CURRENT"
    player.powerTextLeft = "NONE"
    player.powerTextCenter = "CURRENT"
    player.powerTextRight = "NONE"
end

local function QuickApplyPhase2NoCP(offsets)
    local db = M.EnsureDB()
    db.player = db.player or {}
    local player = db.player
    player.detachedPowerBarSyncClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarOffsetX = offsets.dpbOffsetX
    player.detachedPowerBarOffsetY = offsets.dpbOffsetY
end

local function QuickRefreshAll(reason)
    ApplyClassPower()
    ApplyDetachedPowerBarOutline()
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, false, true, reason or "ClassPowerQuickSetup")
end

local function QuickMarkOffered()
    local db = M.EnsureDB()
    db.general = db.general or {}
    db.general[QUICK_SETUP_FLAG] = true
end

local function QuickWasOffered()
    local db = M.EnsureDB()
    return db.general and db.general[QUICK_SETUP_FLAG] == true
end

local function QuickEnsurePopups()
    if not _G.StaticPopupDialogs then return end
    if not _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_RESULT then
        _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_RESULT = {
            text = "%s",
            button1 = OKAY,
            button2 = QuickTr("Undo"),
            OnAccept = function() quickSetupUndoSnapshot = nil end,
            OnCancel = function()
                if quickSetupUndoSnapshot then
                    QuickRestore(quickSetupUndoSnapshot)
                    quickSetupUndoSnapshot = nil
                    QuickRefreshAll("ClassPowerQuickSetupUndo")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = false,
            preferredIndex = 3,
        }
    end
    if not _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_OFFER then
        _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_OFFER = {
            text = QuickTr("Welcome to Class Resources!\n\n"
                .. "Would you like to automatically set up a\n"
                .. "detached Class Bar positioned above your\n"
                .. "Essential Cooldowns?\n\n"
                .. "This configures class resources, power bar,\n"
                .. "anchoring and width matching in one click.\n\n"
                .. "You can always run this later via the\n"
                .. "|cff00ff00Quick Setup: Class Bar|r button below."),
            button1 = QuickTr("Setup Now"),
            button2 = QuickTr("Not Now"),
            OnAccept = function()
                QuickMarkOffered()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.05, function()
                        if _G.MSUF2_ClassPowerQuickSetup then _G.MSUF2_ClassPowerQuickSetup() end
                    end)
                elseif _G.MSUF2_ClassPowerQuickSetup then
                    _G.MSUF2_ClassPowerQuickSetup()
                end
            end,
            OnCancel = QuickMarkOffered,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            showAlert = true,
        }
    end
end

local function ExecuteQuickSetup()
    QuickEnsurePopups()
    QuickMarkOffered()
    local ecv = QuickGetVisibleCDM()
    local offsets = ecv and QuickCalcCPAboveCDM(ecv) or QuickCalcScreenCenter()

    quickSetupUndoSnapshot = QuickSnapshot()
    QuickApplyPhase1(offsets)
    ApplyClassPower()

    local popupText
    if ecv and not QuickClassPowerVisible() then
        QuickApplyPhase2NoCP(QuickCalcDPBAboveCDMNoCP(ecv))
        popupText = "Quick Setup applied!\n\nPower Bar is positioned above\nEssential Cooldowns.\n\nYour spec has no class resource bar.\nIf you respec, it will appear automatically.\n\nUse Edit Mode for fine-tuning."
    elseif ecv then
        popupText = "Quick Setup applied!\n\nClass Power + Power Bar are now\npositioned above Essential Cooldowns.\n\nUse Edit Mode for fine-tuning."
    else
        popupText = "Quick Setup applied!\n\nClass Power + Power Bar are detached\nand positioned at screen center.\n\nEssential Cooldowns not detected.\nEnable it for automatic anchoring.\n\nUse Edit Mode for fine-tuning."
    end

    QuickRefreshAll("ClassPowerQuickSetup")
    if StaticPopup_Show then StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_RESULT", QuickTr(popupText)) end
end

_G.MSUF2_ClassPowerQuickSetup = ExecuteQuickSetup
_G.MSUF_QuickSetup_ResetFirstRun = function()
    local db = M.EnsureDB()
    db.general = db.general or {}
    db.general[QUICK_SETUP_FLAG] = nil
    quickSetupFirstRunChecked = false
end

local function MaybeOfferQuickSetup()
    if quickSetupFirstRunChecked or QuickWasOffered() then return end
    quickSetupFirstRunChecked = true
    QuickEnsurePopups()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            if not QuickWasOffered() and StaticPopup_Show then
                StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_OFFER")
            end
        end)
    elseif StaticPopup_Show then
        StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_OFFER")
    end
end

local function BuildClassPower(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Class Resources", "Native class-resource layout, visibility and text controls.", 94)

    local colors = T.Button(head, "Class Color", 112, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(colors) end
    colors:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -14)
    colors:SetScript("OnClick", function() M.SelectPage("opt_colors") end)

    local edit = T.Button(head, "MSUF Edit Mode", 128, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(edit) end
    edit:SetPoint("RIGHT", colors, "LEFT", -10, 0)

    local quickSetup = T.Button(head, "Quick Setup: Class Bar", 158, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(quickSetup) end
    quickSetup:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -54)
    quickSetup:SetScript("OnClick", ExecuteQuickSetup)
    quickSetup:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(QuickTr("Quick Setup: Detached Class Bar"), 1, 1, 1)
        GameTooltip:AddLine(QuickTr("One-click setup for a ready-to-use class bar:"), 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(QuickTr("Detaches power bar from unit frame"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(QuickTr("Positions class bar ABOVE Essential Cooldowns"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(QuickTr("Match width: Essential Cooldowns"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(QuickTr("Syncs & anchors power bar to class resources"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ")
        local ecv = QuickGetVisibleCDM()
        if ecv and QuickClassPowerVisible() then
            GameTooltip:AddLine(QuickTr("CDM + Class Power detected"), 0.3, 0.9, 0.3)
        elseif ecv then
            GameTooltip:AddLine(QuickTr("CDM detected (no class resource for this spec)"), 0.9, 0.8, 0.3)
        else
            GameTooltip:AddLine(QuickTr("CDM not visible - will center on screen"), 0.9, 0.7, 0.3)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(QuickTr("Click to apply. Undo available in popup."), 0.5, 0.8, 0.5)
        GameTooltip:Show()
    end)
    quickSetup:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, head, quickSetup, { width = 88 })
    end
    local function RefreshEditButton()
        local active = IsMSUFEditModeActive()
        if edit.SetText then edit:SetText(active and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode")) end
        if edit.SetActive then edit:SetActive(false) end
        if edit.SetEnabled then edit:SetEnabled(active or not IsEditModeCombatLocked()) end
    end
    edit:SetScript("OnClick", function()
        local active = IsMSUFEditModeActive()
        if (not active) and IsEditModeCombatLocked() then
            if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
            RefreshEditButton()
            return
        end
        local fn = _G.MSUF_SetMSUFEditModeDirect or _G.MSUF_SetEditMode
        if type(fn) == "function" then pcall(fn, not active) end
        RefreshEditButton()
    end)
    M.AddRefresher(ctx, RefreshEditButton)
    RefreshEditButton()

    local layoutWidth = ctx.width or 900
    local compactLayout = layoutWidth < 620
    local display = b:CollapsibleSection("classpower_display", "Layout", compactLayout and 444 or 268, true)
    local cpControls = {}
    local textControls = {}
    local dpbControls = {}
    local altManaControls = {}

    local cpEnable = BindTableToggle(ctx, display, "Enable", Bars, "showClassPower", true, function()
        ApplyClassPower()
        ShowClassPowerReloadPrompt()
    end)
    local cpHeight = BindTableSlider(ctx, display, "Height", 1, 40, 1, 300, Bars, "classPowerHeight", 4, ApplyClassPower)
    local cpWidthMode = BindTableDropdown(ctx, display, "Width mode", {
        { value = "player", text = "Player frame" },
        { value = "cooldown", text = "Essential Cooldowns" },
        { value = "utility", text = "Utility Cooldowns" },
        { value = "tracked_buffs", text = "Tracked Buffs" },
        { value = "custom", text = "Custom" },
    }, 260, Bars, "classPowerWidthMode", "player", ApplyClassPower)
    local cpWidth = BindTableSlider(ctx, display, "Width", 30, 800, 1, 300, Bars, "classPowerWidth", 0, ApplyClassPower)
    local cpX = BindTableSlider(ctx, display, "Offset X", -800, 800, 1, 300, Bars, "classPowerOffsetX", 0, ApplyClassPower)
    local cpY = BindTableSlider(ctx, display, "Offset Y", -800, 800, 1, 300, Bars, "classPowerOffsetY", 0, ApplyClassPower)
    local cpLevel = BindTableSlider(ctx, display, "Frame level", 0, 30, 1, 300, Bars, "classPowerFrameLevelOffset", 5, ApplyClassPower)
    cpControls[#cpControls + 1] = cpHeight
    cpControls[#cpControls + 1] = cpWidthMode
    cpControls[#cpControls + 1] = cpX
    cpControls[#cpControls + 1] = cpY
    cpControls[#cpControls + 1] = cpLevel
    local layoutLeftX = 32
    local layoutRightX = compactLayout and layoutLeftX or min(max(430, floor(layoutWidth * 0.52)), max(360, layoutWidth - 360))
    local layoutLeftW = compactLayout and max(250, layoutWidth - layoutLeftX - 32) or max(250, layoutRightX - layoutLeftX - 42)
    local layoutRightW = compactLayout and layoutLeftW or max(250, layoutWidth - layoutRightX - 32)
    local layoutControlW = compactLayout and max(250, min(320, layoutWidth - layoutLeftX - 42)) or 300
    local positionTopY = compactLayout and -266 or -64
    LabelAt(display, "Bar", layoutLeftX, -38, layoutLeftW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(display, "Position", layoutRightX, compactLayout and -240 or -38, layoutRightW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpEnable, display, layoutLeftX, -64)
    MoveWidget(cpHeight, display, layoutLeftX, -98, layoutControlW)
    MoveWidget(cpWidthMode, display, layoutLeftX, -150, layoutControlW)
    MoveWidget(cpWidth, display, layoutLeftX, -202, layoutControlW)
    MoveWidget(cpX, display, layoutRightX, positionTopY, layoutControlW)
    MoveWidget(cpY, display, layoutRightX, positionTopY - 52, layoutControlW)
    MoveWidget(cpLevel, display, layoutRightX, positionTopY - 104, layoutControlW)

    local behavior = b:CollapsibleSection("classpower_behavior", "Behavior", 206, false)
    local cpAnchor = BindTableToggle(ctx, behavior, "Anchor to Essential Cooldown", Bars, "classPowerAnchorToCooldown", false, ApplyClassPower)
    local cpCharged = BindTableToggle(ctx, behavior, "Show empowered combo points", Bars, "showChargedComboPoints", true, ApplyClassPower)
    local cpText = BindTableToggle(ctx, behavior, "Show resource text", Bars, "classPowerShowText", false, ApplyClassPower)
    local cpRune = BindTableToggle(ctx, behavior, "Show rune time (per rune)", Bars, "runeShowTime", true, ApplyClassPower)
    local cpReverse = BindTableToggle(ctx, behavior, "Fill right-to-left", Bars, "classPowerFillReverse", false, ApplyClassPower)
    local cpEle = BindTableToggle(ctx, behavior, "Show Maelstrom bar (Ele)", Bars, "showEleMaelstrom", false, ApplyClassPower)
    local cpEbon = BindTableToggle(ctx, behavior, "Show Ebon Might timer (Aug)", Bars, "showEbonMight", true, ApplyClassPower)
    local cpShadow = BindTableToggle(ctx, behavior, "Show Insanity bar (Shadow)", Bars, "showShadowMana", false, ApplyClassPower)
    local cpPrediction = BindTableToggle(ctx, behavior, "Show resource prediction", Bars, "classPowerShowPrediction", true, ApplyClassPower)
    for _, control in ipairs({ cpAnchor, cpCharged, cpText, cpRune, cpReverse, cpEle, cpEbon, cpShadow, cpPrediction }) do
        cpControls[#cpControls + 1] = control
    end
    local behaviorRightX = min(max(380, floor((ctx.width or 900) * 0.45)), max(320, (ctx.width or 900) - 420))
    MoveWidget(cpAnchor, behavior, 14, -38)
    MoveWidget(cpCharged, behavior, 14, -70)
    MoveWidget(cpText, behavior, 14, -102)
    MoveWidget(cpRune, behavior, 14, -134)
    MoveWidget(cpReverse, behavior, 14, -166)
    MoveWidget(cpEle, behavior, behaviorRightX, -38)
    MoveWidget(cpEbon, behavior, behaviorRightX, -70)
    MoveWidget(cpShadow, behavior, behaviorRightX, -102)
    MoveWidget(cpPrediction, behavior, behaviorRightX, -134)

    local visual = b:CollapsibleSection("classpower_visuals", "Style", 420, false)
    local cpColor = BindTableToggle(ctx, visual, "Color by resource type", Bars, "classPowerColorByType", true, ApplyClassPower)
    local cpComboColor = BindTableDropdown(ctx, visual, "Combo point colors", {
        { value = "default", text = "Resource color" },
        { value = "ramp", text = "Combo ramp" },
        { value = "custom", text = "Custom slots" },
    }, 260, Bars, "classPowerComboPointColorMode", "default", ApplyClassPower)
    local cpFont = BindTableSlider(ctx, visual, "Font size", 6, 32, 1, 300, Bars, "classPowerFontSize", 16, ApplyClassPower)
    local cpTextX = BindTableSlider(ctx, visual, "Text X", -200, 200, 1, 300, Bars, "classPowerTextOffsetX", 0, ApplyClassPower)
    local cpTextY = BindTableSlider(ctx, visual, "Text Y", -200, 200, 1, 300, Bars, "classPowerTextOffsetY", 0, ApplyClassPower)
    local cpBg = BindBarsAlphaPercent(ctx, visual, "BG opacity", "classPowerBgAlpha", 0.3, ApplyClassPower, 1)
    local cpSeparator = BindTableSlider(ctx, visual, "Separator", 0, 4, 1, 300, Bars, "classPowerTickWidth", 1, ApplyClassPower)
    local cpOutline = BindTableSlider(ctx, visual, "Outline", 0, 4, 1, 300, Bars, "classPowerOutline", 1, ApplyClassPower)
    local cpFilled = BindBarsAlphaPercent(ctx, visual, "Filled %", "classPowerFilledAlpha", 1.0, ApplyClassPower, 5)
    local cpEmpty = BindBarsAlphaPercent(ctx, visual, "Empty %", "classPowerEmptyAlpha", 0.3, ApplyClassPower, 5)
    local cpGap = BindTableSlider(ctx, visual, "Pip gap", 0, 8, 1, 300, Bars, "classPowerGap", 0, ApplyClassPower)
    local cpFgTex = BindTableDropdown(ctx, visual, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "classPowerTexture", "", ApplyClassPower)
    local cpBgTex = BindTableDropdown(ctx, visual, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "classPowerBgTexture", "", ApplyClassPower)
    for _, control in ipairs({ cpColor, cpComboColor, cpBg, cpSeparator, cpOutline, cpFilled, cpEmpty, cpGap, cpFgTex, cpBgTex }) do
        cpControls[#cpControls + 1] = control
    end
    textControls[#textControls + 1] = cpFont
    textControls[#textControls + 1] = cpTextX
    textControls[#textControls + 1] = cpTextY
    local styleWidth = ctx.width or 900
    local styleLeftX = 32
    local styleMidX = min(max(360, floor(styleWidth * 0.36)), max(320, styleWidth - 650))
    local styleRightX = min(max(styleMidX + 300, floor(styleWidth * 0.66)), max(styleMidX + 270, styleWidth - 390))
    local styleLeftW = max(240, styleMidX - styleLeftX - 28)
    local styleMidW = max(240, styleRightX - styleMidX - 28)
    local styleRightW = max(240, styleWidth - styleRightX - 32)
    local styleLeftControlW = max(260, min(322, styleMidX - styleLeftX - 20))
    local styleMidControlW = max(240, min(286, styleRightX - styleMidX - 24))
    local styleRightControlW = max(240, min(286, styleWidth - styleRightX - 36))
    LabelAt(visual, "Resource", styleLeftX, -38, styleLeftW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(visual, "Text", styleMidX, -38, styleMidW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(visual, "Opacity", styleRightX, -38, styleRightW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpColor, visual, styleLeftX, -64)
    MoveWidget(cpComboColor, visual, styleLeftX, -96, styleLeftControlW)
    LabelAt(visual, "Textures", styleLeftX, -158, styleLeftW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpFgTex, visual, styleLeftX, -184, styleLeftControlW)
    MoveWidget(cpBgTex, visual, styleLeftX, -238, styleLeftControlW)
    MoveWidget(cpFont, visual, styleMidX, -64, styleMidControlW)
    MoveWidget(cpTextX, visual, styleMidX, -116, styleMidControlW)
    MoveWidget(cpTextY, visual, styleMidX, -168, styleMidControlW)
    MoveWidget(cpBg, visual, styleRightX, -64, styleRightControlW)
    MoveWidget(cpFilled, visual, styleRightX, -116, styleRightControlW)
    MoveWidget(cpEmpty, visual, styleRightX, -168, styleRightControlW)
    W.DividerAt(visual, -222, styleRightX, 32)
    LabelAt(visual, "Pips & Border", styleRightX, -240, styleRightW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpSeparator, visual, styleRightX, -266, styleRightControlW)
    MoveWidget(cpOutline, visual, styleRightX, -318, styleRightControlW)
    MoveWidget(cpGap, visual, styleRightX, -370, styleRightControlW)

    local visibility = b:CollapsibleSection("classpower_visibility", "Auto-Hide", 170, false)
    local hideOOC = BindTableToggle(ctx, visibility, "Hide out of combat", Bars, "classPowerHideOOC", false, ApplyClassPower)
    local hideFull = BindTableToggle(ctx, visibility, "Hide when full", Bars, "classPowerHideWhenFull", false, ApplyClassPower)
    local hideEmpty = BindTableToggle(ctx, visibility, "Hide when empty", Bars, "classPowerHideWhenEmpty", false, ApplyClassPower)
    for _, control in ipairs({ hideOOC, hideFull, hideEmpty }) do cpControls[#cpControls + 1] = control end

    local dpb = b:CollapsibleSection("classpower_detached_power", "Detached Power Bar", 352, false)
    W.Text(dpb, "Only applies when power bar is detached.", 14, -38, ctx.width - 28, T.colors.muted)
    dpb._msuf2CursorY = -72
    local dpbMode = W.Dropdown(dpb, "Width mode", {
        { value = "manual", text = "Manual" },
        { value = "cooldown", text = "Essential Cooldowns" },
        { value = "utility", text = "Utility Cooldowns" },
        { value = "tracked_buffs", text = "Tracked Buffs" },
    }, 260)
    M.BindDropdown(ctx, dpbMode,
        function() return Bars().detachedPowerBarWidthMode or "manual" end,
        function(v)
            Bars().detachedPowerBarWidthMode = (v ~= "manual") and v or nil
            ApplyDetachedPowerBar()
        end)
    local dpbFg = BindTableDropdown(ctx, dpb, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "detachedPowerBarTexture", "", ApplyDetachedPowerBar)
    local dpbBg = BindTableDropdown(ctx, dpb, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "detachedPowerBarBgTexture", "", ApplyDetachedPowerBar)
    local dpbOutline = BindTableSlider(ctx, dpb, "Power bar outline", 0, 6, 1, 300, Bars, "detachedPowerBarOutline", 1, ApplyDetachedPowerBarOutline)
    for _, control in ipairs({ dpbMode, dpbFg, dpbBg, dpbOutline }) do dpbControls[#dpbControls + 1] = control end

    local altMana = b:CollapsibleSection("classpower_alt_mana", "Alternative Mana Bar", 238, false)
    W.Text(altMana, "Shadow, Ret, Ele, Enh, Balance, Feral, WW", 14, -38, ctx.width - 28, T.colors.muted)
    altMana._msuf2CursorY = -72
    local altManaToggle = BindTableToggle(ctx, altMana, "Show mana bar (dual resource)", Bars, "showAltMana", false, ApplyClassPower)
    local altManaHeight = BindTableSlider(ctx, altMana, "Height", 2, 30, 1, 300, Bars, "altManaHeight", 4, ApplyClassPower)
    local altManaY = BindTableSlider(ctx, altMana, "Y offset", -50, 50, 1, 300, Bars, "altManaOffsetY", -2, ApplyClassPower)
    altManaControls[#altManaControls + 1] = altManaHeight
    altManaControls[#altManaControls + 1] = altManaY

    M.AddRefresher(ctx, function()
        local bars = Bars()
        local cpOn = BoolValue(bars, "showClassPower", true)
        local textOn = cpOn and BoolValue(bars, "classPowerShowText", false)
        local customWidth = cpOn and ((bars.classPowerWidthMode or "player") == "custom")
        local anyDetached = false
        local db = M.EnsureDB()
        for _, key in ipairs({ "player", "target", "focus" }) do
            if db[key] and db[key].powerBarDetached then anyDetached = true; break end
        end
        for i = 1, #cpControls do SetControlEnabled(cpControls[i], cpOn) end
        SetControlEnabled(cpWidth, customWidth)
        for i = 1, #textControls do SetControlEnabled(textControls[i], textOn) end
        for i = 1, #dpbControls do SetControlEnabled(dpbControls[i], anyDetached) end
        local altOn = BoolValue(bars, "showAltMana", false)
        for i = 1, #altManaControls do SetControlEnabled(altManaControls[i], altOn) end
        SetControlEnabled(altManaToggle, true)
        SetControlEnabled(cpEnable, true)
    end)
    MaybeOfferQuickSetup()

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("classpower", { title = "MSUF Class Resources", build = BuildClassPower, version = 7 })
