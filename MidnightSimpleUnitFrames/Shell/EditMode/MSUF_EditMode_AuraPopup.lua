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
        spacingKey = "buffSpacing",
        defaultX = 0,
        defaultY = 36,
        defaultSize = 26,
    },
    debuff = {
        label = "Debuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        spacingKey = "debuffSpacing",
        defaultX = 0,
        defaultY = 6,
        defaultSize = 26,
    },
    custom1 = { label = "Custom 1", customIndex = 1, xKey = "x", yKey = "y", sizeKey = "size", spacingKey = "spacing", defaultX = 0, defaultY = 0, defaultSize = 24, defaultSpacing = 2 },
    custom2 = { label = "Custom 2", customIndex = 2, xKey = "x", yKey = "y", sizeKey = "size", spacingKey = "spacing", defaultX = 0, defaultY = 0, defaultSize = 24, defaultSpacing = 2 },
    custom3 = { label = "Custom 3", customIndex = 3, xKey = "x", yKey = "y", sizeKey = "size", spacingKey = "spacing", defaultX = 0, defaultY = 0, defaultSize = 24, defaultSpacing = 2 },
    custom4 = { label = "Dots on target", customIndex = 4, xKey = "x", yKey = "y", sizeKey = "size", spacingKey = "spacing", defaultX = 0, defaultY = 0, defaultSize = 24, defaultSpacing = 2 },
}

local pf
local Sync
local Util = EM2.Util or {}
local FramePositionValues = Util.FramePositionValues
local TranslateFramePosition = Util.TranslateFramePosition
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

local function LaneLabel(unit, kind, spec)
    if unit == "player" and kind == "custom4" then return "Defensive Buffs" end
    if spec and spec.customIndex and spec.customIndex < 4 then
        local db = _G.MSUF_DB
        local auras = db and db.auras3
        local scope = IsBoss(unit) and "boss" or unit
        local root = auras and auras.customContainers
        local record = root and type(root.perUnit) == "table" and root.perUnit[scope] or nil
        local item = record and type(record.items) == "table" and record.items[spec.customIndex] or nil
        if item and type(item.name) == "string" and item.name ~= "" then return item.name end
    end
    return spec and spec.label or tostring(kind or "")
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
        local unitCfg = a2.perUnit[unit]
        --- Match the Menu Model ownership contract: while Shared Layout is in
        --- use, the local table is dormant and must not spring back to life on
        --- the first Edit Mode write. Start from the currently effective shared
        --- values and materialize only the fields edited below.
        if unitCfg.overrideLayout ~= true then unitCfg.layout = {} end
        unitCfg.layout = unitCfg.layout or {}
        return unitCfg.layout, unitCfg
    end
    local pu = a2.perUnit and a2.perUnit[unit]
    return (pu and pu.layout) or {}, pu
end

local function AffectedUnits(unit, shared)
    if IsBoss(unit) and (not shared or shared.bossEditTogether ~= false) then
        return { "boss1", "boss2", "boss3", "boss4", "boss5" }
    end
    return { unit }
end

--- Aura layout offsets remain anchor-local runtime values. The popup mirrors
--- the existing Edit Mode readout and translates explicit edits back into that
--- owner; it does not migrate or normalize anchors. Measure the lane body, not
--- the 18px editor chrome.
local function ActiveLaneFrame(unit, kind)
    local a3 = MSUF and MSUF.MSUF_Auras3
    local edit = a3 and a3.EditMode
    local groups = edit and edit.groups
    local group = groups and groups[unit] and groups[unit][kind]
    local parent = pf and pf.parent
    if not group and parent and parent._msufA3Unit == unit and parent._msufA3MoverKind == kind then
        group = parent
    end
    return group and (group.Body or group) or nil
end

local function ReadValue(layout, shared, layoutKey, sharedKey, fallback)
    if layout and layout[layoutKey] ~= nil then return layout[layoutKey] end
    if shared and shared[sharedKey] ~= nil then return shared[sharedKey] end
    return fallback
end

local function RuntimeLayout(unit)
    local layout, unitCfg = UnitLayout(unit, false)
    if unitCfg and unitCfg.overrideLayout == true then return layout or {} end
    return {}
end

local function CustomPlaced(unit, spec, create)
    if not (spec and spec.customIndex) then return nil end
    local item
    if create then
        local a3 = MSUF and MSUF.MSUF_Auras3
        local model = a3 and a3.MenuModel
        item = model and type(model.CustomContainer) == "function"
            and model.CustomContainer(unit, spec.customIndex, true) or nil
    else
        local auras = AurasDB(false)
        local scope = IsBoss(unit) and "boss" or unit
        local root = auras and auras.customContainers
        local record = root and type(root.perUnit) == "table" and root.perUnit[scope] or nil
        item = record and type(record.items) == "table" and record.items[spec.customIndex] or nil
    end
    if not item then return nil end
    if create and type(item.placed) ~= "table" then item.placed = {} end
    return type(item.placed) == "table" and item.placed or nil
end

local SPEC_DEFAULTS = {
    x = "defaultX",
    y = "defaultY",
    size = "defaultSize",
    spacing = "defaultSpacing",
}
local function ReadSpecValue(unit, spec, field, shared)
    local fallback = spec and spec[SPEC_DEFAULTS[field]]
    if field == "spacing" and fallback == nil then fallback = 2 end
    local key = spec and spec[field .. "Key"]
    if spec and spec.customIndex then
        local placed = CustomPlaced(unit, spec, false)
        return placed and placed[key] ~= nil and placed[key] or fallback
    end
    local layout = RuntimeLayout(unit)
    if field == "spacing" then
        return ReadValue(layout, shared, key, key, ReadValue(layout, shared, "spacing", "spacing", fallback))
    end
    return ReadValue(layout, shared, key, key, fallback)
end

local function ReadVisiblePosition(unit, kind, currentX, currentY)
    local frame = ActiveLaneFrame(unit, kind)
    if frame and type(FramePositionValues) == "function" then
        local x, y = FramePositionValues(frame)
        if x ~= nil and y ~= nil then return x, y end
    end
    return currentX, currentY
end

local function TranslateVisiblePosition(unit, kind, currentX, currentY, displayX, displayY)
    local frame = ActiveLaneFrame(unit, kind)
    if frame and type(TranslateFramePosition) == "function" then
        return TranslateFramePosition(frame, currentX, currentY, displayX, displayY)
    end
    local x, y = tonumber(displayX) or currentX, tonumber(displayY) or currentY
    return x, y, x ~= currentX or y ~= currentY
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

local function ApplyBossTogether()
    if Quick.BlockConfigCombatLocked() or not (pf and IsBoss(pf.unit)) then return end
    local sh = Shared(true)
    if not sh then return end
    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
        _G.MSUF_EM_UndoBeforeChange("aura", pf.unit)
    end
    sh.bossEditTogether = pf.bossTogetherBtn and pf.bossTogetherBtn._checked == true or false
    if pf and pf:IsShown() then Sync() end
end

local function ApplyCustom(unit, activeGroup, spec, shared)
    local units = AffectedUnits(unit, shared)
    local currentX = ReadSpecValue(unit, spec, "x", shared)
    local currentY = ReadSpecValue(unit, spec, "y", shared)
    local currentSize = ReadSpecValue(unit, spec, "size", shared)
    local currentSpacing = ReadSpecValue(unit, spec, "spacing", shared)
    local visibleX, visibleY = ReadVisiblePosition(unit, activeGroup, currentX, currentY)
    local displayX = ReadBox(pf.xBox, visibleX ~= nil and visibleX or currentX)
    local displayY = ReadBox(pf.yBox, visibleY ~= nil and visibleY or currentY)
    local spacing = ReadBox(pf.spacingBox, currentSpacing, 0, 64)
    local size = ReadBox(pf.sizeBox, currentSize, 10, 80)
    local geometryChanged = currentSize ~= size or currentSpacing ~= spacing
    local x, y, positionChanged
    if not geometryChanged then
        x, y, positionChanged = TranslateVisiblePosition(unit, activeGroup,
            currentX, currentY, displayX, displayY)
    end
    if not geometryChanged and not positionChanged then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
        _G.MSUF_EM_UndoBeforeChange("aura", unit)
    end

    if geometryChanged then
        for i = 1, #units do
            local placed = CustomPlaced(units[i], spec, true)
            if placed then
                placed[spec.spacingKey] = spacing
                placed[spec.sizeKey] = size
            end
        end
        ReapplyAuras(units)
        x, y, positionChanged = TranslateVisiblePosition(unit, activeGroup,
            currentX, currentY, displayX, displayY)
    end

    if positionChanged then
        for i = 1, #units do
            local placed = CustomPlaced(units[i], spec, true)
            if placed then
                placed[spec.xKey] = x
                placed[spec.yKey] = y
            end
        end
    end

    if not geometryChanged or positionChanged then ReapplyAuras(units) end
    if pf and pf:IsShown() then Sync() end
end

local function Apply()
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local activeGroup, spec = ActiveGroup()
    if spec.customIndex then
        ApplyCustom(pf.unit, activeGroup, spec, Shared(false) or {})
        return
    end
    local a2 = AurasDB(true)
    local sh = Shared(true)
    if not (a2 and sh) then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("aura", pf.unit) end

    local units = AffectedUnits(pf.unit, sh)
    local sourceLayout = RuntimeLayout(pf.unit)
    local currentX = ReadValue(sourceLayout, sh, spec.xKey, spec.xKey, spec.defaultX)
    local currentY = ReadValue(sourceLayout, sh, spec.yKey, spec.yKey, spec.defaultY)
    local currentSize = ReadValue(sourceLayout, sh, spec.sizeKey, spec.sizeKey, spec.defaultSize)
    local currentSpacing = ReadValue(sourceLayout, sh, spec.spacingKey, spec.spacingKey,
        ReadValue(sourceLayout, sh, "spacing", "spacing", 2))
    local visibleX, visibleY
    local positionFrame = ActiveLaneFrame(pf.unit, activeGroup)
    if type(FramePositionValues) == "function" then
        visibleX, visibleY = FramePositionValues(positionFrame)
    end
    local displayX = ReadBox(pf.xBox, visibleX ~= nil and visibleX or currentX)
    local displayY = ReadBox(pf.yBox, visibleY ~= nil and visibleY or currentY)
    local spacing = ReadBox(pf.spacingBox, currentSpacing, 0, 64)
    local size = ReadBox(pf.sizeBox, currentSize, 10, 80)

    local before = {}
    local geometryChanged = false
    for i = 1, #units do
        local unitLayout = RuntimeLayout(units[i])
        local values = {
            x = ReadValue(unitLayout, sh, spec.xKey, spec.xKey, spec.defaultX),
            y = ReadValue(unitLayout, sh, spec.yKey, spec.yKey, spec.defaultY),
            size = ReadValue(unitLayout, sh, spec.sizeKey, spec.sizeKey, spec.defaultSize),
            spacing = ReadValue(unitLayout, sh, spec.spacingKey, spec.spacingKey,
                ReadValue(unitLayout, sh, "spacing", "spacing", 2)),
        }
        before[i] = values
        if values.size ~= size or values.spacing ~= spacing then geometryChanged = true end
    end

    local function WriteLayout()
        for i = 1, #units do
            local layout, unitCfg = UnitLayout(units[i], true)
            if layout and unitCfg then
                unitCfg.overrideLayout = true
                -- The popup edits one lane at a time, so Spacing writes that
                -- lane's key; the shared `spacing` stays as the legacy fallback.
                layout[spec.spacingKey] = spacing
                layout[spec.sizeKey] = size
                layout.width = nil
                layout.height = nil
            end
        end
    end

    local function WritePosition(x, y)
        for i = 1, #units do
            local layout, unitCfg = UnitLayout(units[i], true)
            if layout and unitCfg then
                unitCfg.overrideLayout = true
                layout[spec.xKey] = x
                layout[spec.yKey] = y
            end
        end
    end

    -- A size/gap change can move a lane's visible reference edges. Materialize
    -- that geometry first, then translate the displayed position back into the
    -- lane's anchor-local offsets.
    if geometryChanged then
        WriteLayout()
        ReapplyAuras(units)
        positionFrame = ActiveLaneFrame(pf.unit, activeGroup)
    end

    local x, y
    if positionFrame and type(TranslateFramePosition) == "function" then
        x, y = TranslateFramePosition(positionFrame, currentX, currentY, displayX, displayY)
    else
        x, y = displayX, displayY
    end
    WritePosition(x, y)

    local positionChanged = false
    for i = 1, #units do
        if before[i].x ~= x or before[i].y ~= y then
            positionChanged = true
            break
        end
    end
    if not geometryChanged then
        WriteLayout()
        ReapplyAuras(units)
    elseif positionChanged then
        ReapplyAuras(units)
    end
    if pf and pf:IsShown() then Sync() end
end

local function ResetPosition()
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local _, activeSpec = ActiveGroup()
    if activeSpec.customIndex then
        local shared = Shared(false) or {}
        local currentX = ReadSpecValue(pf.unit, activeSpec, "x", shared)
        local currentY = ReadSpecValue(pf.unit, activeSpec, "y", shared)
        if currentX == activeSpec.defaultX and currentY == activeSpec.defaultY then return end
        if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
            _G.MSUF_EM_UndoBeforeChange("aura", pf.unit)
        end
        local units = AffectedUnits(pf.unit, shared)
        for i = 1, #units do
            local placed = CustomPlaced(units[i], activeSpec, true)
            if placed then
                placed[activeSpec.xKey] = activeSpec.defaultX
                placed[activeSpec.yKey] = activeSpec.defaultY
            end
        end
        ReapplyAuras(units)
        if pf and pf:IsShown() then Sync() end
        return
    end
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
    local activeGroup, spec = ActiveGroup()
    if spec and spec.customIndex then
        local menu = MSUF and MSUF.MSUF2
        if menu then
            menu.unitAuraTabSelection = menu.unitAuraTabSelection or {}
            menu.unitAuraTabSelection[key] = activeGroup
        end
    end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, "auras", nil, { source = "aura-popup", menu = false })
    end
    if Util.SetMenuFocusRequest then Util.SetMenuFocusRequest({
        key = key,
        component = spec and spec.customIndex and activeGroup or "auras",
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
    local layout = RuntimeLayout(pf.unit)
    local activeGroup, spec = ActiveGroup()
    if pf._titleFS then
        local laneLabel = spec.customIndex and LaneLabel(pf.unit, activeGroup, spec) or "Auras"
        pf._titleFS:SetText(Quick.Tr(UnitLabel(pf.unit)) .. " " .. Quick.Tr(laneLabel))
    end
    SetLabel(pf.xBoxLabel, "X")
    SetLabel(pf.yBoxLabel, "Y")
    SetLabel(pf.sizeBoxLabel, "Size")
    SetLabel(pf.spacingBoxLabel, "Spacing")
    if pf.buffLaneBtn and pf.buffLaneBtn.SetCheckedVisual then pf.buffLaneBtn:SetCheckedVisual(activeGroup == "buff") end
    if pf.debuffLaneBtn and pf.debuffLaneBtn.SetCheckedVisual then pf.debuffLaneBtn:SetCheckedVisual(activeGroup == "debuff") end
    if spec.customIndex then
        local currentX = ReadSpecValue(pf.unit, spec, "x", sh)
        local currentY = ReadSpecValue(pf.unit, spec, "y", sh)
        local x, y = ReadVisiblePosition(pf.unit, activeGroup, currentX, currentY)
        Quick.SetBoxText(pf.spacingBox, ReadSpecValue(pf.unit, spec, "spacing", sh))
        Quick.SetBoxText(pf.xBox, x ~= nil and x or currentX)
        Quick.SetBoxText(pf.yBox, y ~= nil and y or currentY)
        Quick.SetBoxText(pf.sizeBox, ReadSpecValue(pf.unit, spec, "size", sh))
    else
        Quick.SetBoxText(pf.spacingBox,
            ReadValue(layout, sh, spec.spacingKey, spec.spacingKey, ReadValue(layout, sh, "spacing", "spacing", 2)))
        local x, y
        if type(FramePositionValues) == "function" then
            x, y = FramePositionValues(ActiveLaneFrame(pf.unit, activeGroup))
        end
        Quick.SetBoxText(pf.xBox, x ~= nil and x or ReadValue(layout, sh, spec.xKey, spec.xKey, spec.defaultX))
        Quick.SetBoxText(pf.yBox, y ~= nil and y or ReadValue(layout, sh, spec.yKey, spec.yKey, spec.defaultY))
        Quick.SetBoxText(pf.sizeBox, ReadValue(layout, sh, spec.sizeKey, spec.sizeKey, spec.defaultSize))
    end
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
    pf.bossTogetherBtn = Quick.ToggleAt(pf, "Edit Boss 1-5 together", 160, -242, 240, 28, ApplyBossTogether,
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
        if pf.bossTogetherBtn and pf.bossTogetherBtn:IsShown() then
            return pf.bossTogetherBtn._checked == true
        end
        return nil
    end
    local widget = ASSISTANT_AURA_FIELDS[field] and pf[ASSISTANT_AURA_FIELDS[field]]
    return widget and tonumber(widget.GetText and widget:GetText()) or nil
end
function AuraPopup.SetAssistantField(field, value)
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit and pf:IsShown()) then return false end
    if field == "lane" then
        if not GROUP_SPECS[value] then return false end
        SetActiveGroup(value)
    elseif field == "bossTogether" then
        if not (pf.bossTogetherBtn and pf.bossTogetherBtn:IsShown()) then return false end
        local checked = value == true
        if pf.bossTogetherBtn.SetCheckedVisual then pf.bossTogetherBtn:SetCheckedVisual(checked) end
        pf.bossTogetherBtn._checked = checked
        ApplyBossTogether()
    else
        local widget = ASSISTANT_AURA_FIELDS[field] and pf[ASSISTANT_AURA_FIELDS[field]]
        if not widget then return false end
        Quick.SetBoxText(widget, tonumber(value))
        Apply()
    end
    return AuraPopup.GetAssistantField(field) == value
end
