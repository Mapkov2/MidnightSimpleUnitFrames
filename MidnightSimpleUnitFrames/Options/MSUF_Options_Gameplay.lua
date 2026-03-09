-- MSUF_Options_Gameplay.lua
-- Options panel for MidnightSimpleUnitFrames Gameplay module.
-- Lazy-init UI: zero overhead at runtime unless the panel is opened.
-- Split from MidnightSimpleUnitFrames_Gameplay.lua; runtime stays in that file.
local _, ns = ...
ns = ns or {}

------------------------------------------------------
-- Local WoW API shortcuts
------------------------------------------------------
local CreateFrame    = CreateFrame
local UIParent       = UIParent
local string_format  = string.format
local string_lower   = string.lower
local tostring       = tostring
local tonumber       = tonumber
local ipairs         = ipairs
local type           = type
local math_max       = math.max
local math_min       = math.min
local math_floor     = math.floor
local C_Spell        = C_Spell
local GetSpellInfo   = GetSpellInfo
local UIDropDownMenu_SetSelectedValue = UIDropDownMenu_SetSelectedValue
local UIDropDownMenu_SetText          = UIDropDownMenu_SetText

------------------------------------------------------
-- Toggle styling helper
-- _G.MSUF_StyleAllToggles does NOT exist (_G exports only the leaf helpers).
-- Build a local recursive walker using the globally exported leaf fns.
------------------------------------------------------
local function StyleAllToggles(root)
    if not root or not root.GetChildren then return end
    local StyleText  = rawget(_G, "MSUF_StyleToggleText") or (ns.MSUF_StyleToggleText) or function() end
    local StyleMark  = rawget(_G, "MSUF_StyleCheckmark")  or (ns.MSUF_StyleCheckmark)  or function() end
    for _, c in ipairs({ root:GetChildren() }) do
        if c and c.GetObjectType and c:GetObjectType() == "CheckButton" then
            StyleText(c); StyleMark(c)
        end
        if c and c.GetChildren then StyleAllToggles(c) end
    end
end

------------------------------------------------------
-- Runtime bridge: all calls to local runtime functions
-- go through ns (resolved lazily at call time so load
-- order of this file relative to the runtime is irrelevant).
------------------------------------------------------
local function EnsureGameplayDefaults()
    if ns.MSUF_EnsureGameplayDefaults then
        return ns.MSUF_EnsureGameplayDefaults()
    end
end

local function _GetCombatFrame()
    return ns.MSUF_GetCombatTimerFrame and ns.MSUF_GetCombatTimerFrame()
end

local function ApplyFontToCounter()
    if ns.MSUF_Gameplay_ApplyFontToCounter then
        ns.MSUF_Gameplay_ApplyFontToCounter()
    end
end

local function ApplyLockState()
    if ns.MSUF_Gameplay_ApplyLockState then
        ns.MSUF_Gameplay_ApplyLockState()
    end
end

local function MSUF_Gameplay_ApplyCombatTimerAnchor(g)
    if ns.MSUF_Gameplay_ApplyCombatTimerAnchorFn then
        ns.MSUF_Gameplay_ApplyCombatTimerAnchorFn(g)
    end
end

local function MSUF_Gameplay_TickCombatTimer()
    if ns.MSUF_Gameplay_TickCombatTimer then
        ns.MSUF_Gameplay_TickCombatTimer()
    end
end

local function _MSUF_GetCombatTimerAnchorFrame(g)
    return ns.MSUF_GetCombatTimerAnchorFrame and ns.MSUF_GetCombatTimerAnchorFrame(g)
end

local function MSUF_SetEnabledMeleeRangeCheck(id)
    if ns.MSUF_SetEnabledMeleeRangeCheck then
        ns.MSUF_SetEnabledMeleeRangeCheck(id)
    end
end

local function MSUF_BuildMeleeSpellCache()
    if ns.MSUF_BuildMeleeSpellCache then
        ns.MSUF_BuildMeleeSpellCache()
    end
end

local function MSUF_GetPlayerSpecID()
    return ns.MSUF_GetPlayerSpecID and ns.MSUF_GetPlayerSpecID()
end

-- Cache access for QuerySuggestions (replaces direct MSUF_MeleeSpellCache upvalue)
local function _GetMeleeSpellCache()
    return ns.MSUF_GetMeleeSpellCache and ns.MSUF_GetMeleeSpellCache()
end

------------------------------------------------------
function ns.MSUF_RegisterGameplayOptions_Full(parentCategory)
    local panel = (_G and _G.MSUF_GameplayPanel) or CreateFrame("Frame", "MSUF_GameplayPanel", UIParent)
    panel.name = "Gameplay"

    if panel.__MSUF_GameplayBuilt then
        return panel
    end

    local scrollFrame = CreateFrame("ScrollFrame", "MSUF_GameplayScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 0)

    local content = CreateFrame("Frame", "MSUF_GameplayScrollChild", scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetWidth(640)
    content:SetHeight(600)

    scrollFrame:SetScrollChild(content)

    local lastControl

    local function RequestApply()
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    end

    local function BindCheck(cb, key, after)
        cb:SetScript("OnClick", function(self)
            local g = EnsureGameplayDefaults()
            local oldVal = g[key]
            local newVal = self:GetChecked() and true or false
            g[key] = newVal

            -- One-time hint: ONLY when the user actually changes a setting here (not on menu open).
            -- Show it when enabling features whose colors live in Colors > Gameplay.
            if (oldVal ~= newVal) and newVal and (key == "enableCombatStateText" or key == "enableCombatCrosshair" or key == "enableCombatCrosshairMeleeRangeColor") then
                if ns and ns.MSUF_MaybeShowGameplayColorsTip then
                    ns.MSUF_MaybeShowGameplayColorsTip()
                end
            end

            if after then after(self, g) end

            -- Keep UI state consistent with Main menu behavior:
            -- when a parent toggle is off, dependent controls are disabled/greyed out.
            if panel and panel.MSUF_UpdateGameplayDisabledStates then
                panel:MSUF_UpdateGameplayDisabledStates()
            end

            RequestApply()
        end)
    end

	    local function BindSlider(sl, key, roundFunc, after, applyNow)
        sl:SetScript("OnValueChanged", function(self, value)
            -- UI sync (panel:refresh / drag-sync) should not write DB or trigger apply.
            if panel and panel._msufSuppressSliderChanges then
                return
            end
	            local g = EnsureGameplayDefaults()
	            -- Defensive: only call a real round/transform function.
	            if type(roundFunc) == "function" then
	                value = roundFunc(value)
	            end
            g[key] = value
            if after then after(self, g, value) end
            if applyNow then RequestApply() end
        end)
    end

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames - Gameplay")

    local subText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subText:SetWidth(600)
    subText:SetJustifyH("LEFT")
    subText:SetText("Here are several gameplay enhancement options you can toggle on or off.")

    -- Section header + separator line
    local sectionTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sectionTitle:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -14)
    sectionTitle:SetText("Crosshair melee spell")

    local separator = content:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(1, 1, 1, 0.15)
    separator:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -4)
    separator:SetSize(560, 1)

    sectionTitle:Hide()
    separator:Hide()

-- Shared melee range spell (shared)
local meleeSharedTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
meleeSharedTitle:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -18)
meleeSharedTitle:SetText("Melee range spell (crosshair)")
panel.meleeSharedTitle = meleeSharedTitle

local meleeSharedSubText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
meleeSharedSubText:SetPoint("TOPLEFT", meleeSharedTitle, "BOTTOMLEFT", 0, -4)
meleeSharedSubText:SetText("Used by: Crosshair melee-range color.")
panel.meleeSharedSubText = meleeSharedSubText

local meleeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
meleeLabel:SetPoint("TOPLEFT", meleeSharedSubText, "BOTTOMLEFT", 0, -10)
meleeLabel:SetText("Choose spell (type spell ID or name):")
panel.meleeSpellChooseLabel = meleeLabel

local meleeInput = CreateFrame("EditBox", "MSUF_Gameplay_MeleeSpellInput", content, "InputBoxTemplate")
meleeInput:SetSize(240, 20)
meleeInput:SetPoint("TOPLEFT", meleeLabel, "BOTTOMLEFT", -4, -6)
meleeInput:SetAutoFocus(false)
meleeInput:SetMaxLetters(60)
panel.meleeSpellInput = meleeInput
local MSUF_SuppressMeleeInputChange = false
local MSUF_SkipMeleeFocusLostResolve = false

-- Optional per-class storage for the shared melee range spell.
-- This allows users to keep one profile across multiple characters and still
-- use a valid class spell for range checking.
local perClassCB = CreateFrame("CheckButton", "MSUF_Gameplay_MeleeSpellPerClassCheck", content, "InterfaceOptionsCheckButtonTemplate")
perClassCB:SetPoint("TOPLEFT", meleeInput, "BOTTOMLEFT", 4, -6)
perClassCB.Text:SetText("Store per class")
panel.meleeSpellPerClassCheck = perClassCB

-- Optional per-spec storage: each specialization can have its own range spell.
-- Takes priority over per-class when both are enabled.
local perSpecCB = CreateFrame("CheckButton", "MSUF_Gameplay_MeleeSpellPerSpecCheck", content, "InterfaceOptionsCheckButtonTemplate")
perSpecCB:SetPoint("TOPLEFT", perClassCB, "BOTTOMLEFT", 0, 2)
perSpecCB.Text:SetText("Store per spec")
panel.meleeSpellPerSpecCheck = perSpecCB

local perStorageHint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
perStorageHint:SetPoint("TOPLEFT", perSpecCB, "BOTTOMLEFT", 20, -2)
perStorageHint:SetText("Keeps per character / spec settings.")
panel.meleeSpellPerStorageHint = perStorageHint

-- Tooltips for per-class / per-spec (since hint label may be hidden in compact layout)
local function _SetStorageTooltip(cb, title, body)
    cb:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(title, 1, 1, 1)
            GameTooltip:AddLine(body, 1, 0.82, 0, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end
_SetStorageTooltip(perClassCB, "Store per class", "Each class keeps its own melee range spell.\nAllows one profile across multiple characters.")
_SetStorageTooltip(perSpecCB, "Store per spec", "Each specialization keeps its own melee range spell.\nRequires 'Store per class' to be enabled.")

local meleeSelected = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
meleeSelected:SetPoint("LEFT", meleeInput, "RIGHT", 12, 0)
meleeSelected:SetText("Selected: (none)")
panel.meleeSpellSelectedText = meleeSelected

local meleeUsedBy = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
meleeUsedBy:SetPoint("TOPLEFT", meleeSelected, "BOTTOMLEFT", 0, -6)
meleeUsedBy:SetText("Used by: Crosshair color")
panel.meleeSpellUsedByText = meleeUsedBy

local meleeSharedWarn = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
meleeSharedWarn:SetPoint("TOPLEFT", meleeUsedBy, "BOTTOMLEFT", 0, -2)
meleeSharedWarn:SetText("|cffff8800No melee range spell selected â€” Crosshair will not work.|r")
meleeSharedWarn:Hide()
panel.meleeSpellWarningText = meleeSharedWarn

local suggestionFrame = CreateFrame("Frame", "MSUF_Gameplay_MeleeSpellSuggestions", content, "BackdropTemplate")
suggestionFrame:SetPoint("TOPLEFT", meleeInput, "BOTTOMLEFT", 0, -2)
suggestionFrame:SetSize(360, 8 * 18 + 10)
suggestionFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
suggestionFrame:SetBackdropColor(0, 0, 0, 0.85)
-- Ensure the dropdown is clickable and sits above other controls (sliders, checkboxes)
suggestionFrame:SetFrameStrata("TOOLTIP")
suggestionFrame:SetToplevel(true)
suggestionFrame:SetClampedToScreen(true)
suggestionFrame:SetFrameLevel((content and content.GetFrameLevel and (content:GetFrameLevel() + 200)) or 200)
suggestionFrame:Hide()
panel.meleeSuggestionFrame = suggestionFrame

-- Forward declare so suggestion button OnClick closures can call it safely.
local MSUF_SelectMeleeSpell

local suggestionButtons = {}
for i = 1, 8 do
    local b = CreateFrame("Button", nil, suggestionFrame)
    b:SetSize(340, 18)
    b:SetPoint("TOPLEFT", suggestionFrame, "TOPLEFT", 10, -6 - (i - 1) * 18)
    b:SetFrameLevel(suggestionFrame:GetFrameLevel() + i)

    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", b, "LEFT", 0, 0)
    t:SetJustifyH("LEFT")
    b.text = t

    b:SetScript("OnClick", function(selfBtn)
        local data = selfBtn.data
        if not data then return end
        -- Route through the shared selection helper so per-class storage stays in sync.
        MSUF_SelectMeleeSpell(data.id, data.name, true)
        MSUF_SkipMeleeFocusLostResolve = true
        meleeInput:ClearFocus()
        suggestionFrame:Hide()
    end)

    suggestionButtons[i] = b
end

local function UpdateSelectedTextFromDB()
    local g = EnsureGameplayDefaults()
    local id = 0
    -- Per-spec takes priority
    if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
        local specID = MSUF_GetPlayerSpecID()
        if specID then
            id = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0
        end
    end
    -- Per-class fallback
    if id <= 0 and g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
        local _, class = UnitClass("player")
        if class then
            id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0
        end
    end
    if id <= 0 then
        id = tonumber(g.nameplateMeleeSpellID) or 0
    end
    -- Shared spell warnings (only relevant if crosshair range-color mode is enabled)
    local rangeActive = (g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor) and true or false
    if panel and panel.meleeSpellWarningText then
        if rangeActive and id <= 0 then
            panel.meleeSpellWarningText:Show()
        else
            panel.meleeSpellWarningText:Hide()
        end
    end
    if panel and panel.crosshairRangeWarnText then
        if rangeActive and id <= 0 then
            panel.crosshairRangeWarnText:Show()
        else
            panel.crosshairRangeWarnText:Hide()
        end
    end

    if id > 0 then
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            if info then name = info.name end
        end
        if not name and GetSpellInfo then
            name = GetSpellInfo(id)
        end
        if name then
            meleeSelected:SetText(string_format("Selected: %s (%d)", name, id))
        else
            meleeSelected:SetText(string_format("Selected: ID %d", id))
        end
    else
        meleeSelected:SetText("Selected: (none)")
    end
end

local function QuerySuggestions(query)
    MSUF_BuildMeleeSpellCache()
    local MSUF_MeleeSpellCache = _GetMeleeSpellCache()
    if not MSUF_MeleeSpellCache or #MSUF_MeleeSpellCache == 0 then
        return {}
    end

    local q = string_lower(query or "")
    if q == "" then
        return {}
    end

    local out = {}
    for _, s in ipairs(MSUF_MeleeSpellCache) do
        if s.lower and s.lower:find(q, 1, true) then
            out[#out + 1] = s
            if #out >= 8 then
                break
            end
        end
    end
    return out
end

MSUF_SelectMeleeSpell = function(spellID, spellName, preferNameInBox)
    local g = EnsureGameplayDefaults()
    spellID = tonumber(spellID) or 0
    if spellID <= 0 then return end

    -- Persist selection (global + optional per-class + optional per-spec)
    if g.meleeSpellPerSpec then
        if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then
            g.nameplateMeleeSpellIDBySpec = {}
        end
        local specID = MSUF_GetPlayerSpecID()
        if specID then
            g.nameplateMeleeSpellIDBySpec[specID] = spellID
        end
    end
    if g.meleeSpellPerClass then
        if type(g.nameplateMeleeSpellIDByClass) ~= "table" then
            g.nameplateMeleeSpellIDByClass = {}
        end
        if UnitClass then
            local _, class = UnitClass("player")
            if class then
                g.nameplateMeleeSpellIDByClass[class] = spellID
            end
        end
    end
    g.nameplateMeleeSpellID = spellID

    if preferNameInBox and spellName and spellName ~= "" then
        MSUF_SuppressMeleeInputChange = true
        meleeInput:SetText(spellName)
        MSUF_SuppressMeleeInputChange = false
    end

    meleeSelected:SetText(string_format("Selected: %s (%d)", (spellName and spellName ~= "" and spellName) or ("ID " .. spellID), spellID))
    if g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor then
        MSUF_SetEnabledMeleeRangeCheck(spellID)
    end
    ns.MSUF_RequestGameplayApply()
end

local function MSUF_ResolveTypedMeleeSpell(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end

    local asNum = tonumber(text)
    if asNum and asNum > 0 then
        local name
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(asNum)
            if info then name = info.name end
        end
        if (not name) and GetSpellInfo then
            name = GetSpellInfo(asNum)
        end
        return asNum, name
    end

    local q = string_lower(text)
    local results = QuerySuggestions(text)
    -- Prefer exact match (case-insensitive)
    for i = 1, #results do
        if results[i] and results[i].lower == q then
            return results[i].id, results[i].name
        end
    end
    -- Otherwise, pick first suggestion
    if results[1] then
        return results[1].id, results[1].name
    end
    return nil
end

meleeInput:SetScript("OnEnterPressed", function(self)
    -- If dropdown is open, choose the first visible suggestion; otherwise try resolving typed text.
    local first = suggestionButtons[1] and suggestionButtons[1].data
    if suggestionFrame:IsShown() and first and first.id then
        MSUF_SelectMeleeSpell(first.id, first.name, true)
        suggestionFrame:Hide()
        MSUF_SkipMeleeFocusLostResolve = true
        self:ClearFocus()
        return
    end

    local id, name = MSUF_ResolveTypedMeleeSpell(self:GetText())
    if id then
        MSUF_SelectMeleeSpell(id, name, true)
    end
    suggestionFrame:Hide()
    MSUF_SkipMeleeFocusLostResolve = true
    self:ClearFocus()
end)
meleeInput:SetScript("OnTextChanged", function(self)
    if MSUF_SuppressMeleeInputChange then return end
    local txt = self:GetText() or ""
    local g = EnsureGameplayDefaults()

    local asNum = tonumber(txt)
    if asNum and asNum > 0 then
        if g.meleeSpellPerSpec then
            if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then
                g.nameplateMeleeSpellIDBySpec = {}
            end
            local specID = MSUF_GetPlayerSpecID()
            if specID then
                g.nameplateMeleeSpellIDBySpec[specID] = asNum
            end
        end
        if g.meleeSpellPerClass then
            if type(g.nameplateMeleeSpellIDByClass) ~= "table" then
                g.nameplateMeleeSpellIDByClass = {}
            end
            if UnitClass then
                local _, class = UnitClass("player")
                if class then
                    g.nameplateMeleeSpellIDByClass[class] = asNum
                end
            end
        end
        g.nameplateMeleeSpellID = asNum
        UpdateSelectedTextFromDB()
        if g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor then
            MSUF_SetEnabledMeleeRangeCheck(asNum)
            ns.MSUF_RequestGameplayApply()
        end
        suggestionFrame:Hide()
        return
    end

    local results = QuerySuggestions(txt)
    if #results == 0 then
        suggestionFrame:Hide()
        return
    end

    for i = 1, 8 do
        local b = suggestionButtons[i]
        local data = results[i]
        if data then
            b.data = data
            b.text:SetText(string_format("%s (%d)", data.name, data.id))
            b:Show()
        else
            b.data = nil
            b.text:SetText("")
            b:Hide()
        end
    end
    suggestionFrame:Show()
end)

-- Per-class checkbox behavior.
perClassCB:SetScript("OnClick", function(self)
    local g = EnsureGameplayDefaults()
    local want = self:GetChecked() and true or false
    g.meleeSpellPerClass = want
    if want then
        if type(g.nameplateMeleeSpellIDByClass) ~= "table" then
            g.nameplateMeleeSpellIDByClass = {}
        end
        if UnitClass then
            local _, class = UnitClass("player")
            if class then
                -- Seed class entry from current global spell if missing.
                if not g.nameplateMeleeSpellIDByClass[class] or tonumber(g.nameplateMeleeSpellIDByClass[class]) <= 0 then
                    g.nameplateMeleeSpellIDByClass[class] = tonumber(g.nameplateMeleeSpellID) or 0
                end
            end
        end
    else
        -- If per-class is disabled, per-spec makes no sense either.
        g.meleeSpellPerSpec = false
        if perSpecCB then perSpecCB:SetChecked(false) end
        if perSpecCB then perSpecCB:SetEnabled(false) end
    end

    -- Enable/disable per-spec checkbox based on per-class state
    if perSpecCB then perSpecCB:SetEnabled(want) end

    -- Refresh UI + apply immediately.
    if panel and panel.refresh then
        panel:refresh()
    end
    ns.MSUF_RequestGameplayApply()
end)

-- Per-spec checkbox behavior (only meaningful when per-class is also enabled).
perSpecCB:SetScript("OnClick", function(self)
    local g = EnsureGameplayDefaults()
    local want = self:GetChecked() and true or false
    g.meleeSpellPerSpec = want
    if want then
        if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then
            g.nameplateMeleeSpellIDBySpec = {}
        end
        -- Seed spec entry from current per-class or global spell if missing.
        local specID = MSUF_GetPlayerSpecID()
        if specID then
            if not g.nameplateMeleeSpellIDBySpec[specID] or tonumber(g.nameplateMeleeSpellIDBySpec[specID]) <= 0 then
                -- Try per-class first, then global
                local seed = 0
                if g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
                    local _, class = UnitClass("player")
                    if class then
                        seed = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0
                    end
                end
                if seed <= 0 then
                    seed = tonumber(g.nameplateMeleeSpellID) or 0
                end
                g.nameplateMeleeSpellIDBySpec[specID] = seed
            end
        end
    end

    -- Refresh UI + apply immediately.
    if panel and panel.refresh then
        panel:refresh()
    end
    ns.MSUF_RequestGameplayApply()
end)

meleeInput:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    suggestionFrame:Hide()
    UpdateSelectedTextFromDB()
end)

meleeInput:SetScript("OnEditFocusLost", function(self)
    suggestionFrame:Hide()
    if MSUF_SkipMeleeFocusLostResolve then
        MSUF_SkipMeleeFocusLostResolve = false
        UpdateSelectedTextFromDB()
        return
    end
    local id, name = MSUF_ResolveTypedMeleeSpell(self:GetText())
    if id then
        MSUF_SelectMeleeSpell(id, name, true)
    else
        UpdateSelectedTextFromDB()
    end
end)

    ------------------------------------------------------
    -- Options UI builder helpers (single-file factory)
    -- NOTE: Keep layout pixel-identical by preserving all SetPoint offsets.
    ------------------------------------------------------
    local function _MSUF_Sep(topRef, yOff)
        local t = content:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 0.15)
        t:SetPoint("TOP", topRef, "BOTTOM", 0, yOff or -24)
        t:SetPoint("LEFT", content, "LEFT", 20, 0)
        t:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        t:SetHeight(1)
        return t
    end

    local function _MSUF_Header(sep, text)
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        fs:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -10)
        fs:SetText(text)
        return fs
    end

    local function _MSUF_Label(template, point, rel, relPoint, x, y, text, field)
        local fs = content:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
        fs:SetPoint(point, rel, relPoint, x or 0, y or 0)
        fs:SetText(text or "")
        if field then panel[field] = fs end
        return fs
    end

    local function _MSUF_Check(name, point, rel, relPoint, x, y, text, field, key, after)
        local cb = CreateFrame("CheckButton", name, content, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint(point, rel, relPoint, x or 0, y or 0)
        cb.Text:SetText(text or "")
        if field then panel[field] = cb end
        if key then BindCheck(cb, key, after) end
        return cb
    end

    local function _MSUF_ColorSwatch(name, point, rel, relPoint, x, y, labelText, field, key, defaultRGB, after)
        local btn = CreateFrame("Button", name, content, "BackdropTemplate")
        btn:SetPoint(point, rel, relPoint, x or 0, y or 0)
        btn:SetSize(18, 18)
        btn:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        btn:SetBackdropColor(0, 0, 0, 0.8)
        btn:SetBackdropBorderColor(1, 1, 1, 0.25)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local sw = btn:CreateTexture(nil, "ARTWORK")
        sw:SetAllPoints()
        btn._msufSwatch = sw

        local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        label:SetText(labelText or "")
        btn._msufLabel = label

        if field then panel[field] = btn end

        local function GetDefault()
            if type(defaultRGB) == "table" then
                return defaultRGB[1] or 1, defaultRGB[2] or 1, defaultRGB[3] or 1
            end
            return 1, 1, 1
        end

        function btn:MSUF_Refresh()
            local g = EnsureGameplayDefaults()
            local dr, dg, db = GetDefault()
            local r, g2, b = _MSUF_NormalizeRGB(g and g[key], dr, dg, db)
            self._msufSwatch:SetColorTexture(r, g2, b, 1)
        end

        local function ApplyColor(r, g2, b)
            local g = EnsureGameplayDefaults()
            g[key] = { r, g2, b }
            btn:MSUF_Refresh()
            if type(after) == "function" then
                after()
            end
            ns.MSUF_RequestGameplayApply()
        end

        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                local r, g2, b = GetDefault()
                ApplyColor(r, g2, b)
                return
            end

            if not ColorPickerFrame then
                return
            end

            local g = EnsureGameplayDefaults()
            local r, g2, b = _MSUF_NormalizeRGB(g and g[key], 1, 1, 1)

            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = { r, g2, b }

            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                ApplyColor(nr, ng, nb)
            end

            ColorPickerFrame.cancelFunc = function(prev)
                if type(prev) == "table" then
                    ApplyColor(prev[1] or 1, prev[2] or 1, prev[3] or 1)
                end
            end

            ColorPickerFrame:SetColorRGB(r, g2, b)
            ColorPickerFrame:Show()
        end)

        btn:MSUF_Refresh()
        return btn, label
    end

    local function _MSUF_Slider(name, point, rel, relPoint, x, y, width, lo, hi, step, lowText, highText, titleText, field, key, roundFunc, after, applyNow)
        local sl = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
        sl:SetWidth(width or 220)
        sl:SetPoint(point, rel, relPoint, x or 0, y or 0)
        sl:SetMinMaxValues(lo, hi)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)

        local base = sl:GetName()
        if lowText then _G[base .. "Low"]:SetText(lowText) end
        if highText then _G[base .. "High"]:SetText(highText) end
        if titleText then _G[base .. "Text"]:SetText(titleText) end

        if field then panel[field] = sl end
        if key then BindSlider(sl, key, roundFunc, after, applyNow) end
        return sl
    end

    local function _MSUF_SliderTextRight(name)
        local t = _G[name .. "Text"]
        if t then
            t:ClearAllPoints()
            t:SetPoint("LEFT", _G[name], "RIGHT", 12, 0)
            t:SetJustifyH("LEFT")
        end
    end

    local function _MSUF_EditBox(name, point, rel, relPoint, x, y, w, h, field)
        local eb = CreateFrame("EditBox", name, content, "InputBoxTemplate")
        eb:SetSize(w or 220, h or 20)
        eb:SetAutoFocus(false)
        eb:SetPoint(point, rel, relPoint, x or 0, y or 0)
        if field then panel[field] = eb end
        return eb
    end
    local function _MSUF_Button(name, point, rel, relPoint, x, y, w, h, text, field, onClick)
        local b = CreateFrame("Button", name, content, "UIPanelButtonTemplate")
        b:SetSize(w or 60, h or 20)
        b:SetPoint(point, rel, relPoint, x or 0, y or 0)
        b:SetText(text or "")
        if field then panel[field] = b end
        if type(onClick) == "function" then
            b:SetScript("OnClick", onClick)
        end
        return b
    end

local function _MSUF_Dropdown(name, point, rel, relPoint, x, y, width, field)
    -- Simple UIDropDownMenu-based control (used sparingly in Gameplay to avoid heavy UI scaffolding).
    local dd = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(name, content) or CreateFrame("Frame", name, content, "UIDropDownMenuTemplate"))
    dd:SetPoint(point, rel, relPoint, x or 0, y or 0)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dd, width or 120)
    end
    if field then
        panel[field] = dd
    end
    return dd
end

    -- Combat Timer header + separator
    local combatSeparator = _MSUF_Sep(subText, -36)
    local combatHeader = _MSUF_Header(combatSeparator, "Combat Timer")

    -- In-combat timer checkbox
    local combatTimerCheck = _MSUF_Check("MSUF_Gameplay_CombatTimerCheck", "TOPLEFT", combatHeader, "BOTTOMLEFT", 0, -8, "Enable in-combat timer", "combatTimerCheck", "enableCombatTimer")

    -- Combat Timer anchor dropdown (None / Player / Target / Focus)
    local combatTimerAnchorLabel = _MSUF_Label("GameFontNormal", "LEFT", combatTimerCheck, "RIGHT", 220, 0, "Anchor", "combatTimerAnchorLabel")
    local combatTimerAnchorDD = _MSUF_Dropdown("MSUF_Gameplay_CombatTimerAnchorDropDown", "LEFT", combatTimerAnchorLabel, "RIGHT", 6, -2, 120, "combatTimerAnchorDropdown")

    local function _CombatTimerAnchor_Validate(v)
        if v ~= "none" and v ~= "player" and v ~= "target" and v ~= "focus" then
            return "none"
        end
        return v
    end

    local function _CombatTimerAnchor_Text(v)
        if v == "player" then return "Player" end
        if v == "target" then return "Target" end
        if v == "focus" then return "Focus" end
        return "None"
    end

    local function _CombatTimerAnchor_Set(v)
        local g = MSUF_DB and MSUF_DB.gameplay
        if not g then return end

        local preX, preY
        do
            local _cf = _GetCombatFrame()
            if _cf and _cf.GetCenter then
                preX, preY = _cf:GetCenter()
            end
        end

        local val = _CombatTimerAnchor_Validate(v)
        g.combatTimerAnchor = val

        -- Keep the timer in the same on-screen position when switching anchors
        if preX and preY then
            local anchor = _MSUF_GetCombatTimerAnchorFrame(g)
            local ax, ay
            if anchor and anchor.GetCenter then
                ax, ay = anchor:GetCenter()
            end
            if not ax or not ay then
                ax, ay = UIParent:GetCenter()
            end
            if ax and ay then
                g.combatOffsetX = preX - ax
                g.combatOffsetY = preY - ay
            end
        end

        
        -- Apply anchor immediately (independent of lock state)
        if _GetCombatFrame() then
            MSUF_Gameplay_ApplyCombatTimerAnchor(g)
            -- Refresh preview text positioning right away (no 1s wait)
            MSUF_Gameplay_TickCombatTimer()
        end

        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(combatTimerAnchorDD, val) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(combatTimerAnchorDD, _CombatTimerAnchor_Text(val)) end

        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
        if panel and panel.refresh then
            panel:refresh()
        end
    end

    if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
        UIDropDownMenu_Initialize(combatTimerAnchorDD, function(self, level)
            local g = MSUF_DB and MSUF_DB.gameplay
            local cur = _CombatTimerAnchor_Validate(g and g.combatTimerAnchor)

            local items = {
                {"none",  "None"},
                {"player", "Player"},
                {"target", "Target"},
                {"focus",  "Focus"},
            }

            for i = 1, #items do
                local value = items[i][1]
                local text  = items[i][2]
                local info = UIDropDownMenu_CreateInfo()
                info.text = text
                info.value = value
                info.checked = (cur == value)
                info.func = function(btn)
                    _CombatTimerAnchor_Set(btn and btn.value)
                    if CloseDropDownMenus then CloseDropDownMenus() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    do
        local g = MSUF_DB and MSUF_DB.gameplay
        local cur = _CombatTimerAnchor_Validate(g and g.combatTimerAnchor)
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(combatTimerAnchorDD, cur) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(combatTimerAnchorDD, _CombatTimerAnchor_Text(cur)) end
    end

    -- Combat Timer size slider
    local combatSlider = _MSUF_Slider("MSUF_Gameplay_CombatFontSizeSlider", "TOPLEFT", combatTimerCheck, "BOTTOMLEFT", 0, -24, 220, 10, 64, 1, "10 px", "64 px", "Timer size", "combatFontSizeSlider", "combatFontSize",
        function(v) return math.floor(v + 0.5) end,
        function() ApplyFontToCounter() end,
        false
    )

    -- Combat Timer lock checkbox
    local combatLock = _MSUF_Check("MSUF_Gameplay_LockCombatTimerCheck", "LEFT", combatSlider, "RIGHT", 40, 0, "Lock position", "lockCombatTimerCheck", "lockCombatTimer",
        function()
            ApplyLockState()
        end
    )

    -- Click-through toggle (affects UNLOCKED behavior):
    -- ON  = timer never steals clicks; unlock + hold ALT to drag.
    -- OFF = timer is draggable normally while unlocked.
    local combatClickThrough = _MSUF_Check("MSUF_Gameplay_CombatTimerClickThroughCheck", "TOPLEFT", combatLock, "BOTTOMLEFT", 0, -8,
        "Click-through (ALT to drag when unlocked)",
        "combatTimerClickThroughCheck", "combatTimerClickThrough",
        function()
            ApplyLockState()
        end
    )

    -- Precise position sliders (offset from chosen anchor)
    local combatPosLabel = _MSUF_Label("GameFontHighlight", "TOPLEFT", combatSlider, "BOTTOMLEFT", 0, -20, "Timer position (offset)", "combatTimerPosLabel")

    local combatOffsetXSlider = _MSUF_Slider("MSUF_Gameplay_CombatTimerOffsetXSlider", "TOPLEFT", combatPosLabel, "BOTTOMLEFT", 0, -12, 240, -800, 800, 1, "-800", "800", "X: 0",
        "combatTimerOffsetXSlider", "combatOffsetX",
        function(v) return math.floor(v + 0.5) end,
        function(self, g, v)
            local t = _G[self:GetName() .. "Text"]
            if t then t:SetText(string.format("X: %d", v)) end
            MSUF_Gameplay_ApplyCombatTimerAnchor(g)
            MSUF_Gameplay_TickCombatTimer()
        end,
        false
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_CombatTimerOffsetXSlider")

    local combatOffsetYSlider = _MSUF_Slider("MSUF_Gameplay_CombatTimerOffsetYSlider", "TOPLEFT", combatOffsetXSlider, "BOTTOMLEFT", 0, -12, 240, -800, 800, 1, "-800", "800", "Y: -200",
        "combatTimerOffsetYSlider", "combatOffsetY",
        function(v) return math.floor(v + 0.5) end,
        function(self, g, v)
            local t = _G[self:GetName() .. "Text"]
            if t then t:SetText(string.format("Y: %d", v)) end
            MSUF_Gameplay_ApplyCombatTimerAnchor(g)
            MSUF_Gameplay_TickCombatTimer()
        end,
        false
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_CombatTimerOffsetYSlider")

    -- Combat Enter/Leave header + separator
    local combatStateSeparator = _MSUF_Sep(combatOffsetYSlider, -24)
    local combatStateHeader = _MSUF_Header(combatStateSeparator, "Combat Enter/Leave")

    -- Combat state text checkbox
    local combatStateCheck = _MSUF_Check("MSUF_Gameplay_CombatStateCheck", "TOPLEFT", combatStateHeader, "BOTTOMLEFT", 0, -8, "Show combat enter/leave text", "combatStateCheck", "enableCombatStateText")

    -- Custom texts (enter/leave)
    local combatStateEnterLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", combatStateCheck, "BOTTOMLEFT", 0, -12, "Enter text", "combatStateEnterLabel")
    local combatStateEnterInput = _MSUF_EditBox("MSUF_Gameplay_CombatStateEnterInput", "TOPLEFT", combatStateEnterLabel, "BOTTOMLEFT", 0, -6, 220, 20, "combatStateEnterInput")

    local combatStateLeaveLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", combatStateEnterInput, "BOTTOMLEFT", 0, -12, "Leave text", "combatStateLeaveLabel")
    local combatStateLeaveInput = _MSUF_EditBox("MSUF_Gameplay_CombatStateLeaveInput", "TOPLEFT", combatStateLeaveLabel, "BOTTOMLEFT", 0, -6, 220, 20, "combatStateLeaveInput")

    local function CommitCombatStateTexts()
        local g = EnsureGameplayDefaults()
        g.combatStateEnterText = (combatStateEnterInput:GetText() or "")
        g.combatStateLeaveText = (combatStateLeaveInput:GetText() or "")
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
        -- If we're showing the unlocked preview, refresh it with the new text
        if g.enableCombatStateText and (not g.lockCombatState) and combatStateText then
            local enterText = g.combatStateEnterText
            if type(enterText) ~= "string" or enterText == "" then
                enterText = "+Combat"
            end
            combatStateText:SetText(enterText)
        end
    end

    combatStateEnterInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        CommitCombatStateTexts()
    end)
    combatStateEnterInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if panel and panel.refresh then
            panel:refresh()
        end
    end)
    combatStateEnterInput:SetScript("OnEditFocusLost", function()
        CommitCombatStateTexts()
    end)

    combatStateLeaveInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        CommitCombatStateTexts()
    end)
    combatStateLeaveInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if panel and panel.refresh then
            panel:refresh()
        end
    end)
    combatStateLeaveInput:SetScript("OnEditFocusLost", function()
        CommitCombatStateTexts()
    end)

    -- Combat Enter/Leave text size slider (shares range with combat timer)
    local combatStateSlider = _MSUF_Slider("MSUF_Gameplay_CombatStateFontSizeSlider", "TOPLEFT", combatStateLeaveInput, "BOTTOMLEFT", 0, -24, 220, 10, 64, 1, "10 px", "64 px", "Text size", "combatStateFontSizeSlider", "combatStateFontSize",
        function(v) return math.floor(v + 0.5) end,
        function() ApplyFontToCounter() end,
        false
    )

    -- Combat Enter/Leave lock checkbox (shares lock with combat timer)
    local combatStateLock = _MSUF_Check("MSUF_Gameplay_CombatStateLockCheck", "LEFT", combatStateLeaveInput, "RIGHT", 80, 0, "Lock position", "lockCombatStateCheck", "lockCombatState",
        function()
            ApplyLockState()
        end
    )

    -- Duration slider for combat enter/leave text
    local combatStateDurationSlider = _MSUF_Slider("MSUF_Gameplay_CombatStateDurationSlider", "LEFT", combatStateEnterInput, "RIGHT", 80, 0, 160, 0.5, 5.0, 0.5, "Short", "Long", "Duration (s)", "combatStateDurationSlider", "combatStateDuration",
        function(v) return math.floor(v * 10 + 0.5) / 10 end,
        nil,
        false
    )

    -- Reset button next to Duration (restore default 1.5s)
    local combatStateDurationReset = _MSUF_Button("MSUF_Gameplay_CombatStateDurationReset", "LEFT", combatStateSlider, "RIGHT", 40, 0, 60, 20, "Reset", "combatStateDurationResetButton")
    combatStateDurationReset:SetScript("OnClick", function()
        local g = EnsureGameplayDefaults()
        g.combatStateDuration = 1.5
        if panel and panel.combatStateDurationSlider then
            panel.combatStateDurationSlider:SetValue(1.5)
        end
        if ns and ns.MSUF_RequestGameplayApply then
            ns.MSUF_RequestGameplayApply()
        end
    end)

    -- Class-specific toggles header + separator
    local classSpecSeparator = _MSUF_Sep(combatStateSlider, -24)
    local classSpecHeader = _MSUF_Header(classSpecSeparator, "Class-specific toggles")

    -- Shaman: Player Totem tracker (player-only)
    local _isShaman = false
    local _isRogue = false
    if UnitClass then
        local _, _cls = UnitClass("player")
        _isShaman = (_cls == "SHAMAN")
        _isRogue = (_cls == "ROGUE")
    end

    local _classSpecAnchorRef = classSpecHeader
    local _totemsLeftBottom = nil
    local _totemsRightBottom = nil

    if _isShaman then
        local totemsTitle = _MSUF_Label("GameFontNormal", "TOPLEFT", classSpecHeader, "BOTTOMLEFT", 0, -10, "Shaman: Totem tracker", "playerTotemsTitle")
        panel.playerTotemsTitle = totemsTitle

        local totemsSub = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", totemsTitle, "BOTTOMLEFT", 0, -2, "Player-only. Secret-safe in combat.", "playerTotemsSubText")

        local totemsDismissHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", totemsSub, "BOTTOMLEFT", 0, -2, "Note: Right-click to dismiss totems is protected by Blizzard (secure) and not supported yet.", "playerTotemsDismissHint")
        panel.playerTotemsDismissHint = totemsDismissHint

        panel.playerTotemsSubText = totemsSub

        local totemsCheck = _MSUF_Check("MSUF_Gameplay_PlayerTotemsCheck", "TOPLEFT", totemsDismissHint, "BOTTOMLEFT", 0, -8, "Enable Totem tracker", "playerTotemsCheck", "enablePlayerTotems",
            function()
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            end
        )

        local function _RefreshTotemsPreviewButton()
            if panel and panel.playerTotemsPreviewButton and panel.playerTotemsPreviewButton.SetText then
                local active = (ns and ns.MSUF_PlayerTotems_IsPreviewActive and ns.MSUF_PlayerTotems_IsPreviewActive()) and true or false
                panel.playerTotemsPreviewButton:SetText(active and "Stop preview" or "Preview")
            end
        end

        local totemsShowText = _MSUF_Check("MSUF_Gameplay_PlayerTotemsShowTextCheck", "TOPLEFT", totemsCheck, "BOTTOMLEFT", 0, -8, "Show cooldown text", "playerTotemsShowTextCheck", "playerTotemsShowText",
            function()
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            end
        )

        local totemsScaleText = _MSUF_Check("MSUF_Gameplay_PlayerTotemsScaleTextCheck", "TOPLEFT", totemsShowText, "BOTTOMLEFT", 0, -8, "Scale text by icon size", "playerTotemsScaleByIconCheck", "playerTotemsScaleTextByIconSize",
            function()
                if ns and ns.MSUF_RequestGameplayApply then
                    ns.MSUF_RequestGameplayApply()
                end
                if panel and panel.MSUF_UpdateGameplayDisabledStates then
                    panel:MSUF_UpdateGameplayDisabledStates()
                end
            end
        )

        -- Preview button: keep it in the left column under the toggles (cleaner layout).
        -- Preview is Shaman-only and works even when the feature toggle is off (positioning).
        local totemsPreviewBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsPreviewButton", "TOPLEFT", totemsScaleText, "BOTTOMLEFT", 0, -12, 140, 22, "Preview", "playerTotemsPreviewButton")
        totemsPreviewBtn:SetScript("OnClick", function()
            if ns and ns.MSUF_PlayerTotems_TogglePreview then
                ns.MSUF_PlayerTotems_TogglePreview()
            end
            _RefreshTotemsPreviewButton()
        end)
        _RefreshTotemsPreviewButton()

        
-- Tip: positioning workflow
local totemsDragHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", totemsPreviewBtn, "BOTTOMLEFT", 0, -4, "Tip: Move the preview via mousedrag", "playerTotemsDragHint")
panel.playerTotemsDragHint = totemsDragHint

_totemsLeftBottom = totemsDragHint

	        -- Right column for layout/size controls (keeps the left side clean, avoids clipping)
	        local _totemsRightX = 300

	        local totemsIconSize = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsIconSizeSlider", "TOPLEFT", totemsCheck, "TOPLEFT", _totemsRightX, -2, 240, 8, 64, 1, "Small", "Big", "Icon size", "playerTotemsIconSizeSlider", "playerTotemsIconSize",
            function(v) return math.floor((v or 0) + 0.5) end,
            function()
                if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
            end,
            true
        )

        local totemsSpacing = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsSpacingSlider", "TOPLEFT", totemsIconSize, "BOTTOMLEFT", 0, -18, 240, 0, 20, 1, "Tight", "Wide", "Spacing", "playerTotemsSpacingSlider", "playerTotemsSpacing",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsOffsetX = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsOffsetXSlider", "TOPLEFT", totemsSpacing, "BOTTOMLEFT", 0, -18, 240, -200, 200, 1, "Left", "Right", "X offset", "playerTotemsOffsetXSlider", "playerTotemsOffsetX",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsOffsetY = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsOffsetYSlider", "TOPLEFT", totemsOffsetX, "BOTTOMLEFT", 0, -18, 240, -200, 200, 1, "Down", "Up", "Y offset", "playerTotemsOffsetYSlider", "playerTotemsOffsetY",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsFontSize = _MSUF_Slider("MSUF_Gameplay_PlayerTotemsFontSizeSlider", "TOPLEFT", totemsOffsetY, "BOTTOMLEFT", 0, -18, 240, 8, 64, 1, "Small", "Big", "Font size", "playerTotemsFontSizeSlider", "playerTotemsFontSize",
            function(v) return math.floor((v or 0) + 0.5) end,
            function() if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end end,
            true
        )

        local totemsLayoutLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", totemsFontSize, "BOTTOMLEFT", 0, -12, "Layout", "playerTotemsLayoutLabel")
        panel.playerTotemsLayoutLabel = totemsLayoutLabel

        local anchorPoints = {"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}
        local function _NextAnchor(cur)
            if type(cur) ~= "string" then
                return anchorPoints[1]
            end
            for i=1,#anchorPoints do
                if anchorPoints[i] == cur then
                    local j = i + 1
                    if j > #anchorPoints then j = 1 end
                    return anchorPoints[j]
                end
            end
            return anchorPoints[1]
                end

        -- Growth direction dropdown (RIGHT / LEFT / UP / DOWN)
        local growthDD = _MSUF_Dropdown("MSUF_Gameplay_PlayerTotemsGrowthDropDown", "TOPLEFT", totemsLayoutLabel, "BOTTOMLEFT", -16, -10, 110, "playerTotemsGrowthDropdown")

        local function _TotemsGrowth_Validate(v)
            if v ~= "LEFT" and v ~= "RIGHT" and v ~= "UP" and v ~= "DOWN" then
                return "RIGHT"
            end
            return v
        end

        local function _TotemsGrowth_Set(v)
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            local val = _TotemsGrowth_Validate(v)
            g.playerTotemsGrowthDirection = val

            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(growthDD, val) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(growthDD, val) end

            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end

        if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
            UIDropDownMenu_Initialize(growthDD, function(self, level)
                local g = MSUF_DB and MSUF_DB.gameplay
                local cur = _TotemsGrowth_Validate(g and g.playerTotemsGrowthDirection)

                local items = {
                    {"RIGHT", "Grow Right"},
                    {"LEFT",  "Grow Left"},
                    {"UP",    "Vertical Up"},
                    {"DOWN",  "Vertical Down"},
                }

                for i = 1, #items do
                    local value = items[i][1]
                    local text  = items[i][2]
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = text
                    info.value = value
                    info.checked = (cur == value)
                    info.func = function(btn)
                        _TotemsGrowth_Set(btn and btn.value)
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
        end

        -- Initial label/selection (kept in sync by panel.refresh)
        do
            local g = MSUF_DB and MSUF_DB.gameplay
            local cur = _TotemsGrowth_Validate(g and g.playerTotemsGrowthDirection)
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(growthDD, cur) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(growthDD, cur) end
        end

	        local anchorFromBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsAnchorFromBtn", "TOPLEFT", growthDD, "TOPRIGHT", 8, -4, 122, 20, "From: TOPLEFT", "playerTotemsAnchorFromButton", function()
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            g.playerTotemsAnchorFrom = _NextAnchor(g.playerTotemsAnchorFrom)
            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end)
        panel.playerTotemsAnchorFromButton = anchorFromBtn

	        local anchorToBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsAnchorToBtn", "TOPLEFT", growthDD, "BOTTOMLEFT", 16, -6, 240, 20, "To: BOTTOMLEFT", "playerTotemsAnchorToButton", function()
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            g.playerTotemsAnchorTo = _NextAnchor(g.playerTotemsAnchorTo)
            if panel and panel.refresh then panel:refresh() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end)
        panel.playerTotemsAnchorToButton = anchorToBtn

	        local resetTotemsBtn = _MSUF_Button("MSUF_Gameplay_PlayerTotemsResetBtn", "TOPLEFT", anchorToBtn, "BOTTOMLEFT", 0, -6, 240, 20, "Reset Totem tracker layout", "playerTotemsResetButton", function()
            local g = MSUF_DB and MSUF_DB.gameplay
            if not g then return end
            g.playerTotemsShowText = true
            g.playerTotemsScaleTextByIconSize = true
            g.playerTotemsIconSize = 24
            g.playerTotemsSpacing = 4
            g.playerTotemsOffsetX = 0
            g.playerTotemsOffsetY = -6
            g.playerTotemsAnchorFrom = "TOPLEFT"
            g.playerTotemsAnchorTo = "BOTTOMLEFT"
            g.playerTotemsGrowthDirection = "RIGHT"
            g.playerTotemsFontSize = 14
            g.playerTotemsTextColor = { 1, 1, 1 }
            if panel and panel.refresh then panel:refresh() end
            if panel and panel.MSUF_UpdateGameplayDisabledStates then panel:MSUF_UpdateGameplayDisabledStates() end
            if ns and ns.MSUF_RequestGameplayApply then ns.MSUF_RequestGameplayApply() end
        end)
        panel.playerTotemsResetButton = resetTotemsBtn
        _totemsRightBottom = resetTotemsBtn

        _classSpecAnchorRef = resetTotemsBtn
    else
        local shamanHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", classSpecHeader, "BOTTOMLEFT", 0, -10, "(Totem tracker is Shaman-only)", "playerTotemsNotShamanHint")
        panel.playerTotemsNotShamanHint = shamanHint
        _classSpecAnchorRef = shamanHint
    end

    -- Rogue: "The First Dance" tracker (separate class block)
    -- Place it clearly BELOW the Shaman block (right column bottom), aligned to the left column.
    local _rogueAnchorRef = _classSpecAnchorRef
    local _rogueSep = nil

    do
        -- If we're Shaman, _classSpecAnchorRef points at the right-column reset button.
        -- Add a subtle divider that spans both columns, then anchor Rogue block under it.
        local _sepX = (_isShaman and -300) or 0
        _rogueSep = panel:CreateTexture(nil, "ARTWORK")
        _rogueSep:SetColorTexture(1, 1, 1, 0.06)
        _rogueSep:SetHeight(1)
        _rogueSep:SetPoint("TOPLEFT", _rogueAnchorRef, "BOTTOMLEFT", _sepX, -18)
        _rogueSep:SetPoint("TOPRIGHT", _rogueAnchorRef, "BOTTOMRIGHT", 0, -18)
    end

    local rogueTitle = _MSUF_Label("GameFontNormal", "TOPLEFT", _rogueSep, "BOTTOMLEFT", 0, -12, "Rogue: First Dance tracker", "firstDanceTitle")
    local rogueSub = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", rogueTitle, "BOTTOMLEFT", 0, -2, "Optional helper. Shows a 6s timer after leaving combat.", "firstDanceSubText")
    local firstDanceCheck = _MSUF_Check("MSUF_Gameplay_FirstDanceCheck", "TOPLEFT", rogueSub, "BOTTOMLEFT", 0, -10, "Track 'The First Dance' (6s after leaving combat)", "firstDanceCheck", "enableFirstDanceTimer")
    if not _isRogue then
        firstDanceCheck:SetEnabled(false)
    end

    ------------------------------------------------------
    -- Rogue: Apex Alert (Trickster – Shadowstrike! hint)
    ------------------------------------------------------
    local _apexUISep = content:CreateTexture(nil, "ARTWORK")
    _apexUISep:SetColorTexture(1, 1, 1, 0.06)
    _apexUISep:SetHeight(1)
    _apexUISep:SetPoint("TOPLEFT", firstDanceCheck, "BOTTOMLEFT", 0, -14)
    _apexUISep:SetSize(560, 1)

    local apexTitle = _MSUF_Label("GameFontNormal", "TOPLEFT", _apexUISep, "BOTTOMLEFT", 0, -10,
        "Rogue: Apex Alert (Shadowstrike! hint)", "apexAlertTitle")
    local apexSub1 = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", apexTitle, "BOTTOMLEFT", 0, -2,
        "Shows |cff00ff00SHADOWSTRIKE!|r if Shadow Dance (185313) is active.", "apexAlertSub1")
    local apexSub2 = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", apexSub1, "BOTTOMLEFT", 0, -2,
        "|cff00ff00SHADOWSTRIKE!|r User needs to check himself if shadow tech stacks are above 5.", "apexAlertSub2")

    local apexCheck = _MSUF_Check("MSUF_Gameplay_ApexAlertCheck", "TOPLEFT", apexSub2, "BOTTOMLEFT", 0, -8,
        "Enable Apex Alert (Shadowstrike hint)", "apexAlertCheck", "enableApexAlert")
    if not _isRogue then apexCheck:SetEnabled(false) end
    panel.apexAlertCheck = apexCheck

    local apexLock = _MSUF_Check("MSUF_Gameplay_ApexAlertLockCheck", "LEFT", apexCheck, "RIGHT", 220, 0,
        "Lock position", "apexAlertLockCheck", "lockApexAlert",
        function()
            local g2 = EnsureGameplayDefaults()
            local f = _G.MSUF_ApexAlertFrame
            if f then f:EnableMouse(not (g2.lockApexAlert and true or false)) end
            -- Preview sofort zeigen/verstecken je nach Lock-State
            RequestApply()
        end)
    panel.apexAlertLockCheck = apexLock

    -- Schriftgröße (EditBox, Zahl)
    local apexFontLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", apexCheck, "BOTTOMLEFT", 0, -16,
        "Schriftgröße", "apexFontSizeLabel")
    local apexFontInput = _MSUF_EditBox("MSUF_Gameplay_ApexFontSizeInput",
        "TOPLEFT", apexFontLabel, "BOTTOMLEFT", -4, -6, 60, 20, "apexFontSizeInput")
    _MSUF_Label("GameFontDisableSmall", "LEFT", apexFontInput, "RIGHT", 8, 0,
        "px  (default 26)", "apexFontSizeHint")
    panel.apexFontSizeInput = apexFontInput
    local function _CommitApexFont()
        local g2 = EnsureGameplayDefaults()
        local v = tonumber(apexFontInput:GetText()) or 26
        if v < 6 then v = 6 end
        if v > 128 then v = 128 end
        g2.apexAlertFontSize = v
        if ns and ns.MSUF_ApexAlert_ApplyFont then ns.MSUF_ApexAlert_ApplyFont() end
    end
    apexFontInput:SetScript("OnEnterPressed", function(self) self:ClearFocus(); _CommitApexFont(); RequestApply() end)
    apexFontInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    apexFontInput:SetScript("OnEditFocusLost",  function() _CommitApexFont(); RequestApply() end)

    -- Anzeigetext
    local apexMsgLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", apexFontInput, "BOTTOMLEFT", 0, -14,
        "Text", "apexMsgLabel")
    local apexMsgInput = _MSUF_EditBox("MSUF_Gameplay_ApexMsgInput",
        "TOPLEFT", apexMsgLabel, "BOTTOMLEFT", -4, -6, 220, 20, "apexMsgInput")
    _MSUF_Label("GameFontDisableSmall", "TOPLEFT", apexMsgInput, "BOTTOMLEFT", 0, -2,
        "Default green. Default: SHADOWSTRIKE!", "apexMsgHint")
    panel.apexMsgInput = apexMsgInput
    local function _CommitApexMsg()
        local g2 = EnsureGameplayDefaults()
        local v = apexMsgInput:GetText()
        if not v or v == "" then v = "SHADOWSTRIKE!" end
        g2.apexAlertMessage = v
        -- Preview sofort aktualisieren wenn unlocked
        local f = _G.MSUF_ApexAlertFrame
        if f and not g2.lockApexAlert then
            local ft = _G.MSUF_ApexAlertText
            if ft then
                ft:SetText("|cff00ff00" .. v .. "|r")
                f:Show()
            end
        end
    end
    apexMsgInput:SetScript("OnEnterPressed", function(self) self:ClearFocus(); _CommitApexMsg(); RequestApply() end)
    apexMsgInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    apexMsgInput:SetScript("OnEditFocusLost",  function() _CommitApexMsg(); RequestApply() end)

    local apexOffsetXSlider = _MSUF_Slider("MSUF_Gameplay_ApexAlertOffsetXSlider",
        "TOPLEFT", apexMsgInput, "BOTTOMLEFT", 0, -18,
        240, -800, 800, 1, "-800", "800", "X: 0",
        "apexAlertOffsetXSlider", "apexAlertOffsetX",
        function(v) return math.floor(v + 0.5) end,
        function(self, gdb, v)
            local t = _G[self:GetName() .. "Text"]
            if t then t:SetText(string_format("X: %d", v)) end
            local f = _G.MSUF_ApexAlertFrame
            if f then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER",
                    tonumber(gdb.apexAlertOffsetX) or 0,
                    tonumber(gdb.apexAlertOffsetY) or 60)
            end
        end,
        false
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_ApexAlertOffsetXSlider")
    panel.apexAlertOffsetXSlider = apexOffsetXSlider

    local apexOffsetYSlider = _MSUF_Slider("MSUF_Gameplay_ApexAlertOffsetYSlider",
        "TOPLEFT", apexOffsetXSlider, "BOTTOMLEFT", 0, -12,
        240, -800, 800, 1, "-800", "800", "Y: 60",
        "apexAlertOffsetYSlider", "apexAlertOffsetY",
        function(v) return math.floor(v + 0.5) end,
        function(self, gdb, v)
            local t = _G[self:GetName() .. "Text"]
            if t then t:SetText(string_format("Y: %d", v)) end
            local f = _G.MSUF_ApexAlertFrame
            if f then
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "CENTER",
                    tonumber(gdb.apexAlertOffsetX) or 0,
                    tonumber(gdb.apexAlertOffsetY) or 60)
            end
        end,
        false
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_ApexAlertOffsetYSlider")
    panel.apexAlertOffsetYSlider = apexOffsetYSlider

    -- Shadow Dance Fenster-Dauer (Kommazahl, z.B. 8.0)
    local danceWinLabel = _MSUF_Label("GameFontNormal", "TOPLEFT", apexOffsetYSlider, "BOTTOMLEFT", 0, -16,
        "Shadow Dance Dauer (s)", "apexDanceWinLabel")
    local danceWinInput = _MSUF_EditBox("MSUF_Gameplay_ApexDanceWinInput",
        "TOPLEFT", danceWinLabel, "BOTTOMLEFT", -4, -6, 80, 20, "apexDanceWinInput")
    _MSUF_Label("GameFontDisableSmall", "LEFT", danceWinInput, "RIGHT", 8, 0,
        "Default 8.0 — +3s automatisch wenn First Dance voll ausläuft.", "apexDanceWinHint")
    panel.apexDanceWinInput = danceWinInput
    local function _CommitDanceWin()
        local g2 = EnsureGameplayDefaults()
        local raw = danceWinInput:GetText():gsub(",", ".")
        local v = tonumber(raw) or 8.0
        if v <= 0 then v = 8.0 end
        g2.apexAlertDanceWindow = v
    end
    danceWinInput:SetScript("OnEnterPressed", function(self) self:ClearFocus(); _CommitDanceWin(); RequestApply() end)
    danceWinInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    danceWinInput:SetScript("OnEditFocusLost",  function() _CommitDanceWin(); RequestApply() end)

    -- Ancient Arts: track via Spell Activation Overlay (event-driven, no aura ID needed)
    local aaCheck = _MSUF_Check("MSUF_Gameplay_ApexAAOverlayCheck",
        "TOPLEFT", danceWinInput, "BOTTOMLEFT", 0, -14,
        "Track Ancient Arts via Spell Activation Overlay",
        "apexAAOverlayCheck", "apexAlertTrackOverlay")
    _MSUF_Label("GameFontDisableSmall", "TOPLEFT", aaCheck, "BOTTOMLEFT", 24, -2,
        "Shows |cff00ccffAA|r on proc. Event-driven — Sub Rogue has exactly one overlay.", "apexAAHint")
    panel.apexAAOverlayCheck = aaCheck
    if not _isRogue then aaCheck:SetEnabled(false) end

    lastControl = aaCheck

    -- Combat crosshair header + separator

    local _classSpecBottom = aaCheck
    local crosshairSeparator = _MSUF_Sep(_classSpecBottom, -20)
    local crosshairHeader = _MSUF_Header(crosshairSeparator, "Combat crosshair")

    -- Generic combat crosshair (all classes)
    local combatCrosshairCheck = _MSUF_Check("MSUF_Gameplay_CombatCrosshairCheck", "TOPLEFT", crosshairHeader, "BOTTOMLEFT", 0, -8, "Show green combat crosshair under player (in combat)", "combatCrosshairCheck", "enableCombatCrosshair",
        function() if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end end
    )

    -- Combat crosshair: melee range coloring (uses the shared melee spell selection)
    local crosshairRangeColorCheck = _MSUF_Check("MSUF_Gameplay_CrosshairRangeColorCheck", "TOPLEFT", combatCrosshairCheck, "BOTTOMLEFT", 0, -8, "Crosshair: color by melee range to target (green=in range, red=out)", "crosshairRangeColorCheck", "enableCombatCrosshairMeleeRangeColor",
        function() if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end end
    )

    local crosshairRangeHint = _MSUF_Label("GameFontDisableSmall", "TOPLEFT", crosshairRangeColorCheck, "BOTTOMLEFT", 24, -2, "Uses the spell selected below.", "crosshairRangeHintText")

    local crosshairRangeWarn = _MSUF_Label("GameFontNormalSmall", "TOPLEFT", crosshairRangeHint, "BOTTOMLEFT", 0, -2, "|cffff8800No melee range spell selected â€” Crosshair will not work.|r", "crosshairRangeWarnText")
    crosshairRangeWarn:Hide()

    -- Move "Melee range spell" selector into the Combat crosshair section (no separate header)
    if meleeSharedTitle and meleeSharedSubText and meleeLabel and meleeInput and meleeSelected and meleeUsedBy then
        meleeSharedTitle:ClearAllPoints()
        meleeSharedTitle:SetPoint("TOPLEFT", crosshairRangeWarn, "BOTTOMLEFT", 0, -12)

        meleeSharedSubText:ClearAllPoints()
        meleeSharedSubText:SetPoint("TOPLEFT", meleeSharedTitle, "BOTTOMLEFT", 0, -4)

        meleeLabel:ClearAllPoints()
        meleeLabel:SetPoint("TOPLEFT", meleeSharedSubText, "BOTTOMLEFT", 0, -10)

        meleeInput:ClearAllPoints()
        meleeInput:SetPoint("TOPLEFT", meleeLabel, "BOTTOMLEFT", -4, -6)

        meleeSelected:ClearAllPoints()
        meleeSelected:SetPoint("LEFT", meleeInput, "RIGHT", 12, 0)

        meleeUsedBy:ClearAllPoints()
        meleeUsedBy:SetPoint("TOPLEFT", meleeSelected, "BOTTOMLEFT", 0, -6)

        if meleeSharedWarn then
            -- Place the orange warning ABOVE "Selected" so it doesn't overlap the thickness/size sliders below.
            -- (Selected is horizontally in the right column; keeping the warning there avoids crowding the left label.)
            meleeSharedWarn:ClearAllPoints()
            meleeSharedWarn:SetPoint("BOTTOMLEFT", meleeSelected, "TOPLEFT", 0, 4)
        end

        -- Position per-class / per-spec checkboxes inline (horizontal) in the right column
        -- to avoid vertical overlap with the thickness/size sliders below.
        -- Layout:  Selected: Backstab (53)   [✓] Store per class
        --          Used by: Crosshair color  [✓] Store per spec
        if perClassCB then
            perClassCB:ClearAllPoints()
            perClassCB:SetPoint("LEFT", meleeSelected, "RIGHT", 8, 0)
        end
        if perSpecCB then
            perSpecCB:ClearAllPoints()
            perSpecCB:SetPoint("LEFT", meleeUsedBy, "RIGHT", 8, 0)
        end
        if panel.meleeSpellPerStorageHint then
            panel.meleeSpellPerStorageHint:Hide()
        end
    end

    -- Crosshair preview (in-menu)
    -- Shows a live preview of size/thickness and (optionally) the melee-range color mode.
    local crosshairPreview = CreateFrame("Frame", "MSUF_Gameplay_CrosshairPreview", content, "BackdropTemplate")
    crosshairPreview:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    crosshairPreview:SetBackdropColor(0, 0, 0, 0.35)
    crosshairPreview:SetBackdropBorderColor(1, 1, 1, 0.15)
    crosshairPreview:SetSize(260, 120)
    if meleeInput then
        crosshairPreview:SetPoint("TOPLEFT", meleeInput, "BOTTOMLEFT", -4, -20)
    else
        crosshairPreview:SetPoint("TOPLEFT", crosshairRangeWarn, "BOTTOMLEFT", 0, -20)
    end
    panel.crosshairPreviewFrame = crosshairPreview

    local previewTitle = crosshairPreview:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    previewTitle:SetPoint("TOPLEFT", crosshairPreview, "TOPLEFT", 8, -6)
    previewTitle:SetText("Preview")

    local previewBox = CreateFrame("Frame", nil, crosshairPreview)
    previewBox:SetPoint("TOPLEFT", crosshairPreview, "TOPLEFT", 8, -20)
    previewBox:SetPoint("BOTTOMRIGHT", crosshairPreview, "BOTTOMRIGHT", -8, 8)

    -- A small center anchor inside the preview box
    local previewCenter = CreateFrame("Frame", nil, previewBox)
    previewCenter:SetSize(1, 1)
    previewCenter:SetPoint("CENTER")

    local pLeft  = previewBox:CreateTexture(nil, "ARTWORK")
    local pRight = previewBox:CreateTexture(nil, "ARTWORK")
    local pUp    = previewBox:CreateTexture(nil, "ARTWORK")
    local pDown  = previewBox:CreateTexture(nil, "ARTWORK")
    pLeft:SetColorTexture(1, 1, 1, 1)
    pRight:SetColorTexture(1, 1, 1, 1)
    pUp:SetColorTexture(1, 1, 1, 1)
    pDown:SetColorTexture(1, 1, 1, 1)

    crosshairPreview._phase = 0
    crosshairPreview._elapsed = 0

    local function ClampInt(v, lo, hi)
        v = tonumber(v) or lo
        v = math.floor(v + 0.5)
        if v < lo then v = lo end
        if v > hi then v = hi end
        return v
    end

    local function UpdateCrosshairPreview()
        local g = EnsureGameplayDefaults()

        local thickness = ClampInt(g.crosshairThickness or 2, 1, 10)
        local size = ClampInt(g.crosshairSize or 40, 20, 80)

        -- Fit the preview box (leave padding for the title)
        local maxW = math_max(10, (previewBox:GetWidth() or 200) - 10)
        local maxH = math_max(10, (previewBox:GetHeight() or 80) - 10)
        local maxSize = math_min(size, maxW, maxH)
        if maxSize < 10 then maxSize = 10 end

        local gap = math_max(2, thickness * 2)
        if gap > maxSize - 2 then
            gap = maxSize - 2
        end

        local seg = (maxSize - gap) / 2
        if seg < 1 then seg = 1 end

        -- Layout
        pLeft:ClearAllPoints()
        pLeft:SetPoint("RIGHT", previewCenter, "CENTER", -gap / 2, 0)
        pLeft:SetSize(seg, thickness)

        pRight:ClearAllPoints()
        pRight:SetPoint("LEFT", previewCenter, "CENTER", gap / 2, 0)
        pRight:SetSize(seg, thickness)

        pUp:ClearAllPoints()
        pUp:SetPoint("BOTTOM", previewCenter, "CENTER", 0, gap / 2)
        pUp:SetSize(thickness, seg)

        pDown:ClearAllPoints()
        pDown:SetPoint("TOP", previewCenter, "CENTER", 0, -gap / 2)
        pDown:SetSize(thickness, seg)

        if not (g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor) then
            crosshairPreview._phase = 0
        end

        -- Color
        local inT = g.crosshairInRangeColor
        local outT = g.crosshairOutRangeColor
        local inR, inG, inB = (inT and inT[1]) or 0, (inT and inT[2]) or 1, (inT and inT[3]) or 0
        local outR, outG, outB = (outT and outT[1]) or 1, (outT and outT[2]) or 0, (outT and outT[3]) or 0

        local r, gCol, b, a = inR, inG, inB, 1
        if not g.enableCombatCrosshair then
            r, gCol, b, a = 0.6, 0.6, 0.6, 0.35
        else
            if g.enableCombatCrosshairMeleeRangeColor then
                -- Alternate between in-range and out-of-range preview
                if crosshairPreview._phase == 1 then
                    r, gCol, b, a = outR, outG, outB, 1
                end
            end
        end
        pLeft:SetVertexColor(r, gCol, b, a)
        pRight:SetVertexColor(r, gCol, b, a)
        pUp:SetVertexColor(r, gCol, b, a)
        pDown:SetVertexColor(r, gCol, b, a)

        -- Only animate (green <-> red) when range-color mode is enabled
        if g.enableCombatCrosshair and g.enableCombatCrosshairMeleeRangeColor then
            crosshairPreview:SetScript("OnUpdate", function(self, elapsed)
                self._elapsed = (self._elapsed or 0) + (elapsed or 0)
                if self._elapsed >= 0.85 then
                    self._elapsed = 0
                    self._phase = (self._phase == 1) and 0 or 1
                    UpdateCrosshairPreview()
                end
            end)
        else
            crosshairPreview:SetScript("OnUpdate", nil)
            crosshairPreview._elapsed = 0
            crosshairPreview._phase = 0
        end
    end

    panel.MSUF_UpdateCrosshairPreview = UpdateCrosshairPreview

    -- Combat crosshair thickness slider
    local crosshairThicknessLabel = _MSUF_Label("GameFontHighlight", "TOPLEFT", meleeSelected or (meleeSharedWarn or crosshairRangeWarn), "BOTTOMLEFT", 0, -24, "Crosshair thickness", "crosshairThicknessLabel")

    local crosshairThicknessSlider = _MSUF_Slider("MSUF_Gameplay_CrosshairThicknessSlider", "TOPLEFT", crosshairThicknessLabel, "BOTTOMLEFT", 0, -12, 240, 1, 10, 1, "1 px", "10 px", "2 px", "crosshairThicknessSlider", "crosshairThickness",
        function(v) return math.floor(v + 0.5) end,
        function(self, g, v)
            _G[self:GetName() .. "Text"]:SetText(string.format("%d px", v))
            if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end
        end,
        true
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_CrosshairThicknessSlider")

    if crosshairPreview and crosshairThicknessSlider then
        -- Keep the preview in the left column (no overlap with sliders)
        crosshairPreview:SetPoint("TOPRIGHT", crosshairThicknessSlider, "TOPLEFT", -18, 0)
    end

    -- Combat crosshair size slider
    local crosshairSizeLabel = _MSUF_Label("GameFontHighlight", "TOPLEFT", crosshairThicknessSlider, "BOTTOMLEFT", 0, -24, "Crosshair size", "crosshairSizeLabel")

    local crosshairSizeSlider = _MSUF_Slider("MSUF_Gameplay_CrosshairSizeSlider", "TOPLEFT", crosshairSizeLabel, "BOTTOMLEFT", 0, -14, 240, 20, 80, 2, "20 px", "80 px", "40 px", "crosshairSizeSlider", "crosshairSize",
        function(v)
            v = math.floor(v + 0.5)
            if v < 20 then v = 20 elseif v > 80 then v = 80 end
            return v
        end,
        function(self, g, v)
            _G[self:GetName() .. "Text"]:SetText(string.format("%d px", v))
            if panel and panel.MSUF_UpdateCrosshairPreview then panel.MSUF_UpdateCrosshairPreview() end
        end,
        true
    )
    _MSUF_SliderTextRight("MSUF_Gameplay_CrosshairSizeSlider")

    if crosshairPreview and crosshairSizeSlider then
        crosshairPreview:SetPoint("BOTTOMRIGHT", crosshairSizeSlider, "BOTTOMLEFT", -18, -4)
    end

    -- No Cooldown Manager section (removed)

    lastControl = crosshairSizeSlider
    ------------------------------------------------------
    -- Panel scripts (refresh/okay/default)
    ------------------------------------------------------

    -- Reset all gameplay option keys to their default values.
    -- We do this by nil-ing the keys and then re-running EnsureGameplayDefaults(),
    -- which repopulates defaults in one place (single source of truth).
    local _MSUF_GAMEPLAY_DEFAULT_KEYS = {
        "nameplateMeleeSpellID",
        "meleeSpellPerClass",
        "meleeSpellPerSpec",
        "nameplateMeleeSpellIDByClass",
        "nameplateMeleeSpellIDBySpec",

        "combatOffsetX",
        "combatOffsetY",
        "combatTimerAnchor",
        "combatFontSize",
        "enableCombatTimer",
        "lockCombatTimer",
        "combatTimerClickThrough",

        "combatStateOffsetX",
        "combatStateOffsetY",
        "combatStateFontSize",
        "combatStateDuration",
        "enableCombatStateText",
        "combatStateEnterText",
        "combatStateLeaveText",
        "lockCombatState",

        "enableFirstDanceTimer",

        "enablePlayerTotems",
        "playerTotemsShowText",
        "playerTotemsScaleTextByIconSize",
        "playerTotemsIconSize",
        "playerTotemsSpacing",
        "playerTotemsAnchorFrom",
        "playerTotemsAnchorTo",
        "playerTotemsGrowthDirection",
        "playerTotemsOffsetX",
        "playerTotemsOffsetY",
        "playerTotemsFontSize",
        "playerTotemsTextColor",

        "enableCombatCrosshair",
        "enableCombatCrosshairMeleeRangeColor",
        "crosshairThickness",
        "crosshairSize",

        "enableApexAlert",
        "apexAlertOffsetX",
        "apexAlertOffsetY",
        "apexAlertFontSize",
        "apexAlertMessage",
        "lockApexAlert",
        "apexAlertTrackOverlay",
        "apexAlertDanceWindow",
    }

    local function _MSUF_ResetGameplayToDefaults()
        local g = EnsureGameplayDefaults()
        for i = 1, #_MSUF_GAMEPLAY_DEFAULT_KEYS do
            g[_MSUF_GAMEPLAY_DEFAULT_KEYS[i]] = nil
        end
        return EnsureGameplayDefaults()
    end

    local function _MSUF_Clamp(v, lo, hi)
        if v == nil then return lo end
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    panel.refresh = function(self)
        self._msufSuppressSliderChanges = true
        local g = EnsureGameplayDefaults()

        -- Melee spell selection (shared)
        local meleeInput = self.meleeSpellInput
        if meleeInput then
            local id = 0
            -- Per-spec takes priority
            if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
                local specID = MSUF_GetPlayerSpecID()
                if specID then
                    id = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0
                end
            end
            -- Per-class fallback
            if id <= 0 and g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
                local _, class = UnitClass("player")
                if class then
                    id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0
                end
            end
            if id <= 0 then
                id = tonumber(g.nameplateMeleeSpellID) or 0
            end
            meleeInput:SetText((id > 0) and tostring(id) or "")
        end

        if self.meleeSpellPerClassCheck then
            self.meleeSpellPerClassCheck:SetChecked(g.meleeSpellPerClass and true or false)
        end
        if self.meleeSpellPerSpecCheck then
            self.meleeSpellPerSpecCheck:SetChecked(g.meleeSpellPerSpec and true or false)
            -- Per-spec only meaningful when per-class is on
            self.meleeSpellPerSpecCheck:SetEnabled(g.meleeSpellPerClass and true or false)
        end
        if UpdateSelectedTextFromDB then
            UpdateSelectedTextFromDB()
        end

        local function SetCheck(field, key, notFalse)
            local cb = self[field]
            if not cb then return end
            local v = notFalse and (g[key] ~= false) or (g[key] and true or false)
            cb:SetChecked(v)
        end

        local function SetSlider(field, key, default)
            local sl = self[field]
            if not sl then return end
            sl:SetValue(tonumber(g[key]) or default or 0)
        end

        -- Simple checks
        local checks = {
            {"combatTimerCheck", "enableCombatTimer"},
            {"lockCombatTimerCheck", "lockCombatTimer"},
            {"combatTimerClickThroughCheck", "combatTimerClickThrough"},

            {"combatStateCheck", "enableCombatStateText"},
            {"lockCombatStateCheck", "lockCombatState"},

            {"firstDanceCheck", "enableFirstDanceTimer"},

            {"playerTotemsCheck", "enablePlayerTotems"},
            {"playerTotemsShowTextCheck", "playerTotemsShowText"},
            {"playerTotemsScaleByIconCheck", "playerTotemsScaleTextByIconSize"},

            {"combatCrosshairCheck", "enableCombatCrosshair"},
            {"crosshairRangeColorCheck", "enableCombatCrosshairMeleeRangeColor"},

            {"apexAlertCheck",        "enableApexAlert"},
            {"apexAlertLockCheck",    "lockApexAlert"},
            {"apexAAOverlayCheck",    "apexAlertTrackOverlay"},
}
        for i = 1, #checks do
            local t = checks[i]
            SetCheck(t[1], t[2], t[3])
        end

        -- Simple sliders
        local sliders = {
            {"combatFontSizeSlider", "combatFontSize", 0},
            {"combatTimerOffsetXSlider", "combatOffsetX", 0},
            {"combatTimerOffsetYSlider", "combatOffsetY", -200},
            {"combatStateFontSizeSlider", "combatStateFontSize", 0},
            {"combatStateDurationSlider", "combatStateDuration", 1.5},

            {"playerTotemsIconSizeSlider", "playerTotemsIconSize", 24},
            {"playerTotemsSpacingSlider", "playerTotemsSpacing", 4},
            {"playerTotemsFontSizeSlider", "playerTotemsFontSize", 14},
            {"playerTotemsOffsetXSlider", "playerTotemsOffsetX", 0},
            {"playerTotemsOffsetYSlider", "playerTotemsOffsetY", -6},

            {"apexAlertOffsetXSlider",  "apexAlertOffsetX",   0},
            {"apexAlertOffsetYSlider",  "apexAlertOffsetY",   60},
        }
        for i = 1, #sliders do
            local t = sliders[i]
            SetSlider(t[1], t[2], t[3])
        end

        -- Combat Timer offset label text (refresh runs with slider-changes suppressed)
        if self.combatTimerOffsetXSlider then
            local vx = tonumber(g.combatOffsetX) or 0
            local txt = _G[self.combatTimerOffsetXSlider:GetName() .. "Text"]
            if txt then txt:SetText(string.format("X: %d", math.floor(vx + 0.5))) end
        end
        if self.combatTimerOffsetYSlider then
            local vy = tonumber(g.combatOffsetY) or -200
            local txt = _G[self.combatTimerOffsetYSlider:GetName() .. "Text"]
            if txt then txt:SetText(string.format("Y: %d", math.floor(vy + 0.5))) end
        end

        -- Combat Timer anchor dropdown
        if self.combatTimerAnchorDropdown then
            local v = g.combatTimerAnchor
            if v ~= "none" and v ~= "player" and v ~= "target" and v ~= "focus" then
                v = "none"
            end
            local txt
            if v == "player" then txt = "Player"
            elseif v == "target" then txt = "Target"
            elseif v == "focus" then txt = "Focus"
            else txt = "None" end
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self.combatTimerAnchorDropdown, v) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self.combatTimerAnchorDropdown, txt) end
        end

        -- Combat state texts
        local eb = self.combatStateEnterInput
        if eb then
            local v = g.combatStateEnterText
            eb:SetText((type(v) == "string") and v or "+Combat")
        end

        eb = self.combatStateLeaveInput
        if eb then
            local v = g.combatStateLeaveText
            eb:SetText((type(v) == "string") and v or "-Combat")
        end

        -- Crosshair special values (clamped)
        local sl = self.crosshairThicknessSlider
        if sl then
            local t = tonumber(g.crosshairThickness) or 2
            sl:SetValue(_MSUF_Clamp(math.floor(t + 0.5), 1, 10))
        end

        sl = self.crosshairSizeSlider
        if sl then
            local v = tonumber(g.crosshairSize) or 40
            sl:SetValue(_MSUF_Clamp(math.floor(v + 0.5), 20, 80))
        end

        if self.MSUF_UpdateCrosshairPreview then
            self.MSUF_UpdateCrosshairPreview()
        end
        if self.playerTotemsGrowthDropdown then
            local growth = g.playerTotemsGrowthDirection
            if growth ~= "LEFT" and growth ~= "RIGHT" and growth ~= "UP" and growth ~= "DOWN" then
                growth = "RIGHT"
            end
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self.playerTotemsGrowthDropdown, growth) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self.playerTotemsGrowthDropdown, growth) end
        end

        if self.playerTotemsAnchorFromButton and self.playerTotemsAnchorFromButton.SetText then
            local af = g.playerTotemsAnchorFrom
            if type(af) ~= "string" or af == "" then
                af = "TOPLEFT"
            end
            self.playerTotemsAnchorFromButton:SetText("From: " .. af)
        end

        if self.playerTotemsAnchorToButton and self.playerTotemsAnchorToButton.SetText then
            local at = g.playerTotemsAnchorTo
            if type(at) ~= "string" or at == "" then
                at = "BOTTOMLEFT"
            end
            self.playerTotemsAnchorToButton:SetText("To: " .. at)
        end
        if self.playerTotemsColorSwatch and self.playerTotemsColorSwatch.MSUF_Refresh then
            self.playerTotemsColorSwatch:MSUF_Refresh()
        end

        -- Apex Alert input syncs
        if self.apexFontSizeInput then
            self.apexFontSizeInput:SetText(tostring(tonumber(g.apexAlertFontSize) or 26))
        end
        if self.apexMsgInput then
            self.apexMsgInput:SetText(g.apexAlertMessage or "SHADOWSTRIKE!")
        end
        -- Dance window input sync
        if self.apexDanceWinInput then
            local dw = tonumber(g.apexAlertDanceWindow) or 8.0
            self.apexDanceWinInput:SetText(string_format("%.1f", dw))
        end

        -- Grey out dependent controls when their parent toggle is off
        if self.MSUF_UpdateGameplayDisabledStates then
            self:MSUF_UpdateGameplayDisabledStates()
        end

        -- Done syncing; re-enable bindings.
        self._msufSuppressSliderChanges = false
    end

-- Live-sync: allow the Combat Timer frame to drag-update X/Y without spamming Apply().
function panel:MSUF_SyncCombatTimerOffsetSliders()
    if not self.combatTimerOffsetXSlider or not self.combatTimerOffsetYSlider then
        return
    end
    local g = EnsureGameplayDefaults()
    self._msufSuppressSliderChanges = true
    local vx = _MSUF_RoundInt(g.combatOffsetX)
    local vy = _MSUF_RoundInt(g.combatOffsetY)
    self.combatTimerOffsetXSlider:SetValue(vx)
    self.combatTimerOffsetYSlider:SetValue(vy)

    local t = _G[self.combatTimerOffsetXSlider:GetName() .. "Text"]
    if t then t:SetText(string.format("X: %d", vx)) end
    t = _G[self.combatTimerOffsetYSlider:GetName() .. "Text"]
    if t then t:SetText(string.format("Y: %d", vy)) end

    self._msufSuppressSliderChanges = false
end

-- Live-sync: allow the Totem preview frame to drag-update X/Y without spamming Apply().
function panel:MSUF_SyncTotemOffsetSliders()
    if not self.playerTotemsOffsetXSlider or not self.playerTotemsOffsetYSlider then
        return
    end
    local g = EnsureGameplayDefaults()
    self._msufSuppressSliderChanges = true
    self.playerTotemsOffsetXSlider:SetValue(tonumber(g.playerTotemsOffsetX) or 0)
    self.playerTotemsOffsetYSlider:SetValue(tonumber(g.playerTotemsOffsetY) or -6)
    self._msufSuppressSliderChanges = false
end

    -- Most controls apply immediately, but "Okay" is still called by the Settings/Interface panel system.
    -- We use it as a safe "finalize" hook.
    panel.okay = function(self)
        if self.meleeSpellInput and self.meleeSpellInput.HasFocus and self.meleeSpellInput:HasFocus() then
            self.meleeSpellInput:ClearFocus()
        end

        ns.MSUF_RequestGameplayApply()
end

    panel.default = function(self)
        _MSUF_ResetGameplayToDefaults()
        if self.refresh then
            self:refresh()
        end

        ns.MSUF_RequestGameplayApply()
end

    
    ------------------------------------------------------
    -- Dynamic content height
    ------------------------------------------------------
    local function UpdateContentHeight()
        local minHeight = 400
        if not lastControl then
            content:SetHeight(minHeight)
            return
        end

        local bottom = lastControl:GetBottom()
        local top    = content:GetTop()
        if not bottom or not top then
            content:SetHeight(minHeight)
            return
        end

        local padding = 40
        local height  = top - bottom + padding
        if height < minHeight then
            height = minHeight
        end
        content:SetHeight(height)
    end

    panel:SetScript("OnShow", function()
        StyleAllToggles(panel)
        if panel.refresh then
            panel:refresh()
        end
        UpdateContentHeight()
    end)

-- Settings registration
    if (not panel.__MSUF_SettingsRegistered) and Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
        local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(subcategory)
        panel.__MSUF_SettingsRegistered = true
        ns.MSUF_GameplayCategory = subcategory
    elseif InterfaceOptions_AddCategory then
        panel.parent = "Midnight Simple Unit Frames"
        InterfaceOptions_AddCategory(panel)
    end

    -- Beim Ã–ffnen des Panels SavedVariables â†’ UI syncen
    panel:refresh()
    UpdateContentHeight()

    StyleAllToggles(panel)

    -- Und aktuelle Visuals anwenden
    ns.MSUF_RequestGameplayApply()

    panel.__MSUF_GameplayBuilt = true
    return panel
end

-- Lightweight wrapper: register the category at login, but build the heavy UI only when opened.
function ns.MSUF_RegisterGameplayOptions(parentCategory)
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory or not parentCategory then
        -- Fallback: if Settings API isn't available, just build immediately.
        return ns.MSUF_RegisterGameplayOptions_Full(parentCategory)
    end

    local panel = (_G and _G.MSUF_GameplayPanel) or CreateFrame("Frame", "MSUF_GameplayPanel", UIParent)
    panel.name = "Gameplay"

    -- IMPORTANT: Panels created with UIParent are shown by default.
    -- If we rely on OnShow for first-time build, we must ensure the panel starts hidden,
    -- otherwise the first Settings click may not fire OnShow.
    if not panel.__MSUF_ForceHidden then
        panel.__MSUF_ForceHidden = true
        panel:Hide()
    end

    -- Register the subcategory now (cheap) so it shows up immediately in Settings.
    if not panel.__MSUF_SettingsRegistered then
        local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(subcategory)
        ns.MSUF_GameplayCategory = subcategory
        panel.__MSUF_SettingsRegistered = true
    end

    -- Already built: nothing else to do.
    if panel.__MSUF_GameplayBuilt then
        return panel
    end

    -- First open builds the full panel. Build synchronously in OnShow so the panel is ready on the first click.

    if not panel.__MSUF_LazyBuildHooked then

        panel.__MSUF_LazyBuildHooked = true

    

        panel:HookScript("OnShow", function()

            if panel.__MSUF_GameplayBuilt or panel.__MSUF_GameplayBuilding then

                return

            end

            panel.__MSUF_GameplayBuilding = true

    

            -- Build immediately (no C_Timer.After(0)): avoids "needs second click" issues.

            ns.MSUF_RegisterGameplayOptions_Full(parentCategory)

    

            panel.__MSUF_GameplayBuilding = nil

        end)

    end

    

    return panel

    end

