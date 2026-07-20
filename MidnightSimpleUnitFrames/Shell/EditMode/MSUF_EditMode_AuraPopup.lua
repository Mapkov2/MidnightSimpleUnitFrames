--- MSUF_EditMode_AuraPopup.lua - Menu2-style quick aura bounds popup.
--- Adjusts aura group offsets/sizes from edit mode while delegating saved config and live
--- refresh to Auras3/Menu2 helpers. It should not run aura scans itself.

local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local max, min = math.max, math.min
local Style = _G.MSUF_EM2_Menu2Style or {}
local Quick = EM2.QuickPopup or Style.QuickPopup
if not Quick then return end

local GROUP_SPECS = {
    buff = {
        label = "Buffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        defaultX = 0,
        defaultY = 36,
        defaultSize = 26,
    },
    debuff = {
        label = "Debuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        defaultX = 0,
        defaultY = 6,
        defaultSize = 26,
    },
}

local pf
local Sync
local Util = EM2.Util or {}
local SyncMovers = (EM2.Util and EM2.Util.SyncMovers) or function() if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end end
local UnitPageKey = Util.UnitPageKey or function() return "uf_player" end
local NormalizeSimpleUnit = Util.NormalizeSimpleUnit or function(unit)
    if unit == "boss" then return "boss1" end
    if type(unit) == "string" and unit:match("^boss%d+$") then return unit end
    if unit == "player" or unit == "target" or unit == "focus" then return unit end
    return nil
end
local function NormalizeAuraUnit(unit)
    local normalized = NormalizeSimpleUnit(unit, true)
    return normalized ~= "pet" and normalized or nil
end

local function ButtonOpts(sync)
    return {
        peelSkin = true,
        sync = sync,
    }
end

local function IsBoss(unit)
    return type(unit) == "string" and unit:match("^boss%d+$")
end

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if IsBoss(unit) then return "Boss " .. (unit:match("%d+") or "1") end
    return tostring(unit or "")
end

local function ActiveGroup()
    local kind = _G.MSUF_EM2_ActiveAuraGroup
    if not GROUP_SPECS[kind] then kind = "buff" end
    return kind, GROUP_SPECS[kind]
end

local function AurasDB(create)
    local db = _G.MSUF_DB
    if not db then return nil end
    if create then db.auras3 = db.auras3 or {} end
    return db.auras3
end

local function Shared(create)
    local a2 = AurasDB(create)
    if not a2 then return nil end
    if create then a2.shared = a2.shared or {} end
    return a2.shared or {}
end

local function UnitLayout(unit, create)
    local a2 = AurasDB(create)
    if not a2 then return nil end
    if create then
        a2.perUnit = a2.perUnit or {}
        a2.perUnit[unit] = a2.perUnit[unit] or {}
        a2.perUnit[unit].layout = a2.perUnit[unit].layout or {}
        return a2.perUnit[unit].layout, a2.perUnit[unit]
    end
    local pu = a2.perUnit and a2.perUnit[unit]
    return (pu and pu.layout) or {}, pu
end

local function EffectiveUnit(unit, shared)
    if IsBoss(unit) and (not shared or shared.bossEditTogether ~= false) then return "boss1" end
    return unit
end

local function AffectedUnits(unit, shared)
    if IsBoss(unit) and (not shared or shared.bossEditTogether ~= false) then
        return { "boss1", "boss2", "boss3", "boss4", "boss5" }
    end
    return { unit }
end

local function ReadValue(layout, shared, layoutKey, sharedKey, fallback)
    if layout and layout[layoutKey] ~= nil then return layout[layoutKey] end
    if shared and shared[sharedKey] ~= nil then return shared[sharedKey] end
    return fallback
end

local function ReapplyAuras(units)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RequestScope) == "function" then
        for i = 1, #units do a3.RequestScope(units[i], "EM2_AURA_POPUP_APPLY") end
    elseif a3 and type(a3.RefreshUnit) == "function" then
        for i = 1, #units do a3.RefreshUnit(units[i]) end
    elseif a3 and type(a3.RefreshAll) == "function" then
        a3.RefreshAll()
    end
    if a3 and type(a3.RefreshEditPreview) == "function" then
        local bossDone = false
        for i = 1, #units do
            local unit = units[i]
            if IsBoss(unit) then
                if not bossDone then
                    a3.RefreshEditPreview("boss")
                    bossDone = true
                end
            else
                a3.RefreshEditPreview(unit)
            end
        end
    end
    SyncMovers()
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then _G.MSUF_UFPreview_RequestRefresh("EM2_AURA_POPUP_APPLY") end
end

local function ReadBox(box, fallback, low, high)
    local v = Quick.San(box and box:GetText(), fallback)
    if low then v = max(low, v) end
    if high then v = min(high, v) end
    return v
end

local function Apply()
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local a2 = AurasDB(true)
    local sh = Shared(true)
    if not (a2 and sh) then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("aura", pf.unit) end

    if pf.bossTogetherBtn and pf.bossTogetherBtn:IsShown() then
        sh.bossEditTogether = pf.bossTogetherBtn._checked and true or false
    end
    local units = AffectedUnits(pf.unit, sh)
    local _, spec = ActiveGroup()
    local spacing = ReadBox(pf.spacingBox, 2, 0, 64)
    local x = ReadBox(pf.xBox, spec.defaultX)
    local y = ReadBox(pf.yBox, spec.defaultY)
    local size = ReadBox(pf.sizeBox, spec.defaultSize, 10, 80)

    for i = 1, #units do
        local layout, unitCfg = UnitLayout(units[i], true)
        if layout and unitCfg then
            unitCfg.overrideLayout = true
            layout.spacing = spacing
            layout[spec.xKey] = x
            layout[spec.yKey] = y
            layout[spec.sizeKey] = size
            layout.width = nil
            layout.height = nil
        end
    end

    ReapplyAuras(units)
end

local function ResetPosition()
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local a2 = AurasDB(true)
    if not a2 then return end
    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("aura", pf.unit) end
    local sh = Shared(true)
    local units = AffectedUnits(pf.unit, sh)
    local _, spec = ActiveGroup()
    for i = 1, #units do
        local layout, unitCfg = UnitLayout(units[i], true)
        if layout and unitCfg then
            unitCfg.overrideLayout = true
            layout[spec.xKey] = spec.defaultX
            layout[spec.yKey] = spec.defaultY
        end
    end
    ReapplyAuras(units)
    if pf and pf:IsShown() then Sync() end
end

local function CommitFields()
    Quick.ClearFocusedBoxes(pf and pf.spacingBox, pf and pf.xBox, pf and pf.yBox, pf and pf.sizeBox)
    Apply()
end

local function MenuUnit(unit)
    return IsBoss(unit) and "boss" or unit
end

local function OpenUnitAuras()
    if not (pf and pf.unit) then return end
    CommitFields()
    local key = MenuUnit(pf.unit)
    local pageKey = UnitPageKey(key)
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, "auras", nil, { source = "aura-popup", menu = false })
    end
    if Util.SetMenuFocusRequest then Util.SetMenuFocusRequest({
        key = key,
        component = "auras",
        pageKey = pageKey,
        sectionId = "auras3",
        source = "aura-popup",
    }) end
    Quick.OpenPage(pageKey, pf)
end

local function OpenGeneralAuras()
    if not (pf and pf.unit) then return end
    CommitFields()
    if Util.SetMenuFocusRequest then Util.SetMenuFocusRequest({
        key = "auras3",
        component = "auras",
        pageKey = "auras3",
        sectionId = "a2_layout",
        source = "aura-popup",
    }) end
    Quick.OpenPage("auras3", pf)
end

local function WirePopupFocus(btn)
    return Util.WirePopupFocus and Util.WirePopupFocus(btn, function() return pf and pf.unit and MenuUnit(pf.unit) end, "auras", "aura-popup") or btn
end

local function SetLabel(fs, text)
    if fs and fs.SetText then fs:SetText(Quick.Tr(text)) end
end

local function SetActiveGroup(kind)
    if not GROUP_SPECS[kind] then return end
    local current = _G.MSUF_EM2_ActiveAuraGroup
    if current ~= kind and pf and pf.unit and pf.xBox then
        Apply()
    end
    local export = (MSUF and MSUF.ExportPublic) or function(name, value) _G[name] = value end
    export("MSUF_EM2_ActiveAuraGroup", kind)
    if pf and pf.unit then export("MSUF_EM2_ActiveAuraUnit", pf.unit) end
    if pf and pf:IsShown() then Sync() end
end

function Sync()
    if not (pf and pf.unit) then return end
    local sh = Shared(false) or {}
    local layout = UnitLayout(EffectiveUnit(pf.unit, sh), false) or {}
    local activeGroup, spec = ActiveGroup()
    if pf._titleFS then pf._titleFS:SetText(Quick.Tr(UnitLabel(pf.unit)) .. " " .. Quick.Tr("Auras")) end
    SetLabel(pf.xBoxLabel, "X")
    SetLabel(pf.yBoxLabel, "Y")
    SetLabel(pf.sizeBoxLabel, "Size")
    SetLabel(pf.spacingBoxLabel, "Spacing")
    if pf.buffLaneBtn and pf.buffLaneBtn.SetCheckedVisual then pf.buffLaneBtn:SetCheckedVisual(activeGroup == "buff") end
    if pf.debuffLaneBtn and pf.debuffLaneBtn.SetCheckedVisual then pf.debuffLaneBtn:SetCheckedVisual(activeGroup == "debuff") end
    Quick.SetBoxText(pf.spacingBox, ReadValue(layout, sh, "spacing", "spacing", 2))
    Quick.SetBoxText(pf.xBox, ReadValue(layout, sh, spec.xKey, spec.xKey, spec.defaultX))
    Quick.SetBoxText(pf.yBox, ReadValue(layout, sh, spec.yKey, spec.yKey, spec.defaultY))
    Quick.SetBoxText(pf.sizeBox, ReadValue(layout, sh, spec.sizeKey, spec.sizeKey, spec.defaultSize))
    if pf.bossTogetherBtn and pf.bossTogetherBtn.SetCheckedVisual then
        local isBoss = IsBoss(pf.unit)
        pf.bossTogetherBtn:SetShown(isBoss)
        if isBoss then
            pf.bossTogetherBtn:ClearAllPoints()
            pf.bossTogetherBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 160, -242)
        end
        pf.bossTogetherBtn:SetCheckedVisual(sh.bossEditTogether ~= false)
        pf:SetHeight(isBoss and 390 or 350)
        local actionsY = isBoss and -282 or -244
        if pf.unitAurasBtn then
            pf.unitAurasBtn:ClearAllPoints()
            pf.unitAurasBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, actionsY)
        end
        if pf.generalAurasBtn then
            pf.generalAurasBtn:ClearAllPoints()
            pf.generalAurasBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 366, actionsY)
        end
    end
end

local function Build()
    if pf then return pf end

    pf = Quick.CreateShell("MSUF_EM2_AuraPopup", {
        width = 560,
        height = 350,
        title = "Auras",
        liveStatus = true,
        hoverSource = "aura-popup",
    })
    pf.buffLaneBtn = WirePopupFocus(Quick.ToggleAt(pf, "Buffs", 20, -58, 250, 32, function() SetActiveGroup("buff") end, ButtonOpts(function() if pf and pf:IsShown() then Sync() end end)))
    pf.debuffLaneBtn = WirePopupFocus(Quick.ToggleAt(pf, "Debuffs", 290, -58, 250, 32, function() SetActiveGroup("debuff") end, ButtonOpts(function() if pf and pf:IsShown() then Sync() end end)))
    Quick.ValueCard(pf, pf, 20, -102, 250, "Position", {
        { label = "X", key = "xBox", onChanged = Apply },
        { label = "Y", key = "yBox", onChanged = Apply },
    }, { height = 132, boxWidth = 64, peelSkin = true })
    Quick.ValueCard(pf, pf, 290, -102, 250, "Aura layout", {
        { label = "Size", key = "sizeBox", onChanged = Apply },
        { label = "Spacing", key = "spacingBox", onChanged = Apply },
    }, { height = 132, boxWidth = 64, peelSkin = true })
    pf.bossTogetherBtn = Quick.ToggleAt(pf, "Edit Boss 1-5 together", 160, -242, 240, 28, Apply,
        ButtonOpts(function() if pf and pf:IsShown() then Sync() end end))
    pf.unitAurasBtn = WirePopupFocus(Quick.ButtonAt(pf, "Open detailed settings", 20, -244, 334, 34, OpenUnitAuras, {
        variant = "primary", hoverWash = true,
    }))
    pf.generalAurasBtn = WirePopupFocus(Quick.ButtonAt(pf, "General aura settings", 366, -244, 174, 34, OpenGeneralAuras, ButtonOpts()))
    if Quick.AddFooterControls then
        Quick.AddFooterControls(pf, { anchor = "BOTTOM", bottomGap = 12, resetLabel = "Reset lane position", onResetPosition = ResetPosition })
    end
    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end
    return pf
end

local AuraPopup = {}
EM2.AuraPopup = AuraPopup

function AuraPopup.RefreshHistory()
    if pf and pf:IsShown() and pf._refreshUndoRedo then pf._refreshUndoRedo() end
end

function AuraPopup.Open(unit, parent)
    if Quick.BlockConfigCombatLocked() then return false end
    unit = NormalizeAuraUnit(unit)
    if not unit then return false end
    Build()
    pf.unit, pf.parent = unit, parent
    Sync()
    pf:Show()
    if Style.FadeIn then Style.FadeIn(pf, 0.12, 0.86, 1) end
    return true
end

function AuraPopup.Close()
    if pf then pf:Hide() end
end

function AuraPopup.IsOpen()
    return pf and pf:IsShown() or false
end

function AuraPopup.Sync()
    if pf and pf:IsShown() then Sync() end
end
local ASSISTANT_AURA_FIELDS = {
    x = "xBox", y = "yBox", size = "sizeBox", spacing = "spacingBox",
}
function AuraPopup.GetAssistantField(field)
    if not (pf and pf.unit and pf:IsShown()) then return nil end
    if field == "lane" then return ActiveGroup() end
    if field == "bossTogether" then
        return pf.bossTogetherBtn and pf.bossTogetherBtn:IsShown() and pf.bossTogetherBtn._checked == true or nil
    end
    local widget = ASSISTANT_AURA_FIELDS[field] and pf[ASSISTANT_AURA_FIELDS[field]]
    return widget and tonumber(widget.GetText and widget:GetText()) or nil
end
function AuraPopup.SetAssistantField(field, value)
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit and pf:IsShown()) then return false end
    if field == "lane" then
        if value ~= "buff" and value ~= "debuff" then return false end
        SetActiveGroup(value)
    elseif field == "bossTogether" then
        if not (pf.bossTogetherBtn and pf.bossTogetherBtn:IsShown()) then return false end
        local checked = value == true
        if pf.bossTogetherBtn.SetCheckedVisual then pf.bossTogetherBtn:SetCheckedVisual(checked) end
        pf.bossTogetherBtn._checked = checked
        Apply()
    else
        local widget = ASSISTANT_AURA_FIELDS[field] and pf[ASSISTANT_AURA_FIELDS[field]]
        if not widget then return false end
        Quick.SetBoxText(widget, tonumber(value))
        Apply()
    end
    return AuraPopup.GetAssistantField(field) == value
end
