-- MSUF_GF_HealerBuffs_Editor.lua — Group Frames Phase 5b: Healer Buff Editor
-- Config UI for healer buff placement: enable/disable, spec preset toggle,
-- icon size/spacing/anchor, manual slot management.
-- Midnight 12.0 secret-safe.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end
local HB = GF.HealerBuffs
if not HB then return end

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local C_Spell = _G.C_Spell
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring

local FAMILY_DATA = HB.FAMILY_DATA
local FAMILY_BY_ID = HB.FAMILY_BY_ID
local SPEC_PRESETS = HB.SPEC_PRESETS

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(ns) == "table" and type(ns.Translate) == "function" then
        return ns.Translate(text)
    end
    local locale = (type(ns) == "table" and ns.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

------------------------------------------------------------------------
-- Editor frame (slash command accessible)
------------------------------------------------------------------------
local _editorFrame

local function GetSpellTexture(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then return tex end
    end
    local _, _, icon = GetSpellInfo(spellId)
    return icon
end

local function BuildFamilyDropdownList()
    local list = {}
    for _, fam in ipairs(FAMILY_DATA) do
        local tex = fam.spellIds[1] and GetSpellTexture(fam.spellIds[1])
        list[#list + 1] = {
            id       = fam.id,
            name     = fam.name or fam.id,
            class    = fam.classToken,
            texture  = tex,
        }
    end
    return list
end

local function RefreshEditor()
    if not _editorFrame or not _editorFrame:IsShown() then return end
    -- Rebuild slot display
    local kind = _editorFrame._kind or "party"
    local hbConf = HB.EnsureConf(kind)
    local slots = hbConf.slots or {}

    -- Update enable checkbox
    if _editorFrame._enableCheck then
        _editorFrame._enableCheck:SetChecked(hbConf.enabled == true)
    end
    if _editorFrame._presetCheck then
        _editorFrame._presetCheck:SetChecked(hbConf.useSpecPreset ~= false)
    end
    if _editorFrame._sizeSlider then
        _editorFrame._sizeSlider:SetValue(hbConf.iconSize or 20)
    end
    if _editorFrame._spacingSlider then
        _editorFrame._spacingSlider:SetValue(hbConf.spacing or 1)
    end

    -- Rebuild slot rows
    local slotContainer = _editorFrame._slotContainer
    if slotContainer then
        -- Hide existing rows
        if slotContainer._rows then
            for i = 1, #slotContainer._rows do
                slotContainer._rows[i]:Hide()
            end
        end

        if hbConf.useSpecPreset then
            -- Show spec preset info
            local specId = _G.GetSpecializationInfo and _G.GetSpecialization and _G.GetSpecializationInfo(_G.GetSpecialization())
            local preset = specId and SPEC_PRESETS[specId]
            if preset then
                slotContainer._rows = slotContainer._rows or {}
                for i, famId in ipairs(preset) do
                    local fam = FAMILY_BY_ID[famId]
                    if fam then
                        local row = slotContainer._rows[i]
                        if not row then
                            row = CreateFrame("Frame", nil, slotContainer)
                            row:SetHeight(24)
                            slotContainer._rows[i] = row
                        end
                        row:SetPoint("TOPLEFT", slotContainer, "TOPLEFT", 0, -(i-1) * 26)
                        row:SetPoint("RIGHT", slotContainer, "RIGHT", 0, 0)
                        row:SetHeight(24)

                        if not row._icon then
                            row._icon = row:CreateTexture(nil, "ARTWORK")
                            row._icon:SetSize(20, 20)
                            row._icon:SetPoint("LEFT", row, "LEFT", 4, 0)
                            row._icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                        end
                        local tex = fam.spellIds[1] and GetSpellTexture(fam.spellIds[1])
                        if tex then row._icon:SetTexture(tex) end

                        if not row._label then
                            row._label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                            row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
                            row._label:SetJustifyH("LEFT")
                        end
                        row._label:SetText(fam.name or famId)

                        if not row._class then
                            row._class = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                            row._class:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                            row._class:SetJustifyH("RIGHT")
                            row._class:SetTextColor(0.6, 0.6, 0.6, 1)
                        end
                        row._class:SetText(fam.classToken or "")

                        row:Show()
                    end
                end
            end
        else
            -- Manual slots (editable)
            slotContainer._rows = slotContainer._rows or {}
            for i, slotCfg in ipairs(slots) do
                local fam = slotCfg.familyId and FAMILY_BY_ID[slotCfg.familyId]
                if fam then
                    local row = slotContainer._rows[i]
                    if not row then
                        row = CreateFrame("Frame", nil, slotContainer)
                        slotContainer._rows[i] = row
                    end
                    row:SetPoint("TOPLEFT", slotContainer, "TOPLEFT", 0, -(i-1) * 26)
                    row:SetPoint("RIGHT", slotContainer, "RIGHT", -30, 0)
                    row:SetHeight(24)

                    if not row._icon then
                        row._icon = row:CreateTexture(nil, "ARTWORK")
                        row._icon:SetSize(20, 20)
                        row._icon:SetPoint("LEFT", row, "LEFT", 4, 0)
                        row._icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    end
                    local tex = fam.spellIds[1] and GetSpellTexture(fam.spellIds[1])
                    if tex then row._icon:SetTexture(tex) end

                    if not row._label then
                        row._label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                        row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
                        row._label:SetJustifyH("LEFT")
                    end
                    row._label:SetText(fam.name or slotCfg.familyId)

                    -- Remove button
                    if not row._removeBtn then
                        row._removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
                        row._removeBtn:SetSize(20, 20)
                        row._removeBtn:SetPoint("RIGHT", row, "RIGHT", 24, 0)
                    end
                    local removeIdx = i
                    row._removeBtn:SetScript("OnClick", function()
                        local hbc = HB.EnsureConf(_editorFrame._kind or "party")
                        table.remove(hbc.slots, removeIdx)
                        RefreshEditor()
                        GF.RefreshVisuals()
                    end)

                    row:Show()
                end
            end
        end
    end
end

local function CreateEditor()
    if _editorFrame then return _editorFrame end

    local f = CreateFrame("Frame", "MSUF_GF_HealerBuffEditor", UIParent, "BackdropTemplate")
    f:SetSize(340, 420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f._kind = "party"

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
    title:SetText(Tr("Healer Buff Placement"))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    local yOff = -40

    -- Enable checkbox
    local enableCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 12, yOff)
    enableCheck:SetSize(26, 26)
    enableCheck.text = enableCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    enableCheck.text:SetPoint("LEFT", enableCheck, "RIGHT", 4, 0)
    enableCheck.text:SetText(Tr("Enable Healer Buff Indicators"))
    enableCheck:SetScript("OnClick", function(self)
        local hbConf = HB.EnsureConf(f._kind)
        hbConf.enabled = self:GetChecked() == true
        GF.RefreshVisuals()
    end)
    f._enableCheck = enableCheck
    yOff = yOff - 30

    -- Use Spec Preset checkbox
    local presetCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    presetCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 12, yOff)
    presetCheck:SetSize(26, 26)
    presetCheck.text = presetCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    presetCheck.text:SetPoint("LEFT", presetCheck, "RIGHT", 4, 0)
    presetCheck.text:SetText(Tr("Auto-detect from current spec"))
    presetCheck:SetScript("OnClick", function(self)
        local hbConf = HB.EnsureConf(f._kind)
        hbConf.useSpecPreset = self:GetChecked() == true
        RefreshEditor()
        GF.RefreshVisuals()
    end)
    f._presetCheck = presetCheck
    yOff = yOff - 30

    -- Icon Size slider
    local sizeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    sizeLabel:SetText(Tr("Icon Size"))
    local sizeSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 100, yOff - 2)
    sizeSlider:SetSize(180, 16)
    sizeSlider:SetMinMaxValues(10, 40)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetScript("OnValueChanged", function(self, val)
        local hbConf = HB.EnsureConf(f._kind)
        hbConf.iconSize = math.floor(val + 0.5)
        GF.RefreshVisuals()
    end)
    f._sizeSlider = sizeSlider
    yOff = yOff - 30

    -- Spacing slider
    local spLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, yOff)
    spLabel:SetText(Tr("Spacing"))
    local spSlider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    spSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 100, yOff - 2)
    spSlider:SetSize(180, 16)
    spSlider:SetMinMaxValues(0, 10)
    spSlider:SetValueStep(1)
    spSlider:SetObeyStepOnDrag(true)
    spSlider:SetScript("OnValueChanged", function(self, val)
        local hbConf = HB.EnsureConf(f._kind)
        hbConf.spacing = math.floor(val + 0.5)
        GF.RefreshVisuals()
    end)
    f._spacingSlider = spSlider
    yOff = yOff - 36

    -- Slot container (scrollable list of families)
    local slotLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    slotLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, yOff)
    slotLabel:SetText(Tr("Active Spell Indicators:"))
    yOff = yOff - 20

    local slotContainer = CreateFrame("Frame", nil, f)
    slotContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 12, yOff)
    slotContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40)
    f._slotContainer = slotContainer

    -- Add button (only for manual mode)
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 22)
    addBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    addBtn:SetText(Tr("Add Spell..."))
    addBtn:SetScript("OnClick", function()
        -- Simple: cycle through families, add first not-yet-added
        local hbConf = HB.EnsureConf(f._kind)
        if hbConf.useSpecPreset then
            print(Tr("|cff888888MSUF:|r Switch to manual mode first (uncheck auto-detect)"))
            return
        end
        local existing = {}
        for _, s in ipairs(hbConf.slots) do existing[s.familyId] = true end
        for _, fam in ipairs(FAMILY_DATA) do
            if not existing[fam.id] then
                hbConf.slots[#hbConf.slots + 1] = { familyId = fam.id }
                RefreshEditor()
                GF.RefreshVisuals()
                return
            end
        end
        print(Tr("|cff888888MSUF:|r All spell families already added"))
    end)

    -- Party/Raid toggle
    local toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    toggleBtn:SetSize(80, 22)
    toggleBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    toggleBtn:SetText(Tr("Party"))
    toggleBtn:SetScript("OnClick", function(self)
        if f._kind == "party" then
            f._kind = "raid"
            self:SetText(Tr("Raid"))
        else
            f._kind = "party"
            self:SetText(Tr("Party"))
        end
        RefreshEditor()
    end)

    f:Hide()
    _editorFrame = f
    return f
end

------------------------------------------------------------------------
-- Public: Toggle editor
------------------------------------------------------------------------
------------------------------------------------------------------------
-- SI redirect: when Spell Indicators are enabled, direct user to Options
------------------------------------------------------------------------
local function IsSIEnabled(kind)
    local conf = GF.GetConf and GF.GetConf(kind or "party")
    return conf and conf.spellIndicators and conf.spellIndicators.enabled
end

local function PrintSIRedirect()
    local msg = "|cff00ccff[MSUF]|r Spell Indicators are enabled. Use |cff00ff00/msuf|r → Group Frames → Spell Indicators to configure."
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

function HB.ShowEditor(kind)
    if IsSIEnabled(kind) then PrintSIRedirect(); return end
    local f = CreateEditor()
    f._kind = kind or "party"
    RefreshEditor()
    f:Show()
end

function HB.HideEditor()
    if _editorFrame then _editorFrame:Hide() end
end

function HB.ToggleEditor(kind)
    if IsSIEnabled(kind) then PrintSIRedirect(); return end
    local f = CreateEditor()
    if f:IsShown() then
        f:Hide()
    else
        f._kind = kind or "party"
        RefreshEditor()
        f:Show()
    end
end

------------------------------------------------------------------------
-- Global exports
------------------------------------------------------------------------
_G.MSUF_GF_HB_ShowEditor   = HB.ShowEditor
_G.MSUF_GF_HB_HideEditor   = HB.HideEditor
_G.MSUF_GF_HB_ToggleEditor  = HB.ToggleEditor
